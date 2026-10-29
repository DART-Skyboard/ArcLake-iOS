import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// Thin-channel support (port of the Arc Flow web sandbox's tube-fitted
// collision + hose flow physics + link diagnostic):
//   * ArcTubeFit: fits a bore (centerline waypoints + radius) to a thin /
//     elongated part so the analytic tube replaces the voxelised mesh in
//     the collision grid (a bore thinner than a voxel would otherwise
//     close up).
//   * ArcChannelPhysics: continuity (v ~ 1/A), Bernoulli with Darcy-
//     Weisbach friction, bend / inlet loss, choked-gas cap.
// ═══════════════════════════════════════════════════════════════════
struct ArcTubeBore {
    var name: String
    var pts: [SIMD3<Float>]      // bore centerline waypoints (world)
    var bore: Float              // fitted bore radius (model units)
    var outer: Float             // outer radius
    var length: Float

    /// Distance to the centerline polyline, or +inf past the open ends
    /// (so the end caps / neighbouring walls are never touched).
    func distance(to p: SIMD3<Float>) -> Float {
        guard pts.count >= 2 else { return .infinity }
        var best = Float.infinity
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let ab = b - a
            let l2 = simd_length_squared(ab)
            if l2 < 1e-12 { continue }
            let t = simd_dot(p - a, ab) / l2
            if (i == 0 && t < 0) || (i == pts.count - 2 && t > 1) { continue }
            let tc = max(0, min(1, t))
            best = min(best, simd_length(p - (a + ab * tc)))
        }
        return best
    }
    var bboxMin: SIMD3<Float> { pts.dropFirst().reduce(pts[0]) { simd_min($0, $1) } }
    var bboxMax: SIMD3<Float> { pts.dropFirst().reduce(pts[0]) { simd_max($0, $1) } }
    /// Number of >30 degree direction changes along the centerline.
    var bends: Int {
        guard pts.count >= 3 else { return 0 }
        var n = 0
        var prev = simd_normalize(pts[1] - pts[0])
        for i in 1..<(pts.count - 1) {
            let d = pts[i + 1] - pts[i]
            if simd_length(d) < 1e-9 { continue }
            let cur = simd_normalize(d)
            if simd_dot(prev, cur) < 0.866 { n += 1 }
            prev = cur
        }
        return n
    }
}

struct ArcLinkDiag: Identifiable {
    var id: String { name }
    var name: String
    var bore: Float
    var voxelsAcross: Float
    var connected: Bool
    var failAt: SIMD3<Float>?
    var note: String
}

enum ArcTubeFit {
    static func looksThin(name: String, kind: ArcGeometricClassifier.Kind?, ext: SIMD3<Float>) -> Bool {
        let d = [ext.x, ext.y, ext.z].sorted()
        let aspect = d[2] / max(1e-6, (d[0] + d[1]) * 0.5)
        let n = name.lowercased()
        let byName = ["pipe", "channel", "tube", "duct", "hose", "line"].contains { n.contains($0) }
        return kind == .pipe || byName || aspect >= 6
    }

    static func fit(part: ArcSealPart) -> ArcTubeBore? {
        let verts = part.verts
        guard verts.count >= 12 else { return nil }
        let ext = part.bmax - part.bmin
        var axis = 0
        if ext.y > ext[axis] { axis = 1 }
        if ext.z > ext[axis] { axis = 2 }
        let L = ext[axis]
        guard L > 1e-6 else { return nil }
        let cross = max(ext[(axis + 1) % 3], ext[(axis + 2) % 3])
        let n = max(6, min(48, Int(L / max(1e-6, cross * 0.5))))
        var sum = [SIMD3<Float>](repeating: .zero, count: n)
        var cnt = [Float](repeating: 0, count: n)
        func slab(_ v: SIMD3<Float>) -> Int { max(0, min(n - 1, Int((v[axis] - part.bmin[axis]) / L * Float(n)))) }
        for v in verts { let i = slab(v); sum[i] += v; cnt[i] += 1 }
        var pts: [SIMD3<Float>] = []
        var cen = [SIMD3<Float>](repeating: .zero, count: n)
        for i in 0..<n where cnt[i] > 0 { cen[i] = sum[i] / cnt[i]; pts.append(cen[i]) }
        guard pts.count >= 2 else { return nil }
        // Extend the polyline to the part's open ends along the axis.
        var first = pts[0]; first[axis] = part.bmin[axis]
        var last = pts[pts.count - 1]; last[axis] = part.bmax[axis]
        pts[0] = first; pts[pts.count - 1] = last
        // Radial distances (stride-sampled).
        var rad: [Float] = []
        let stride = max(1, verts.count / 20000)
        var k = 0
        while k < verts.count {
            let v = verts[k]
            var d = v - cen[slab(v)]
            d[axis] = 0
            rad.append(simd_length(d))
            k += stride
        }
        rad.sort()
        guard let rmax = rad.last, rmax > 1e-7 else { return nil }
        let R = rad[min(rad.count - 1, Int(Float(rad.count) * 0.98))]
        let inner = rad.filter { $0 > 0.08 * R }
        var r = inner.isEmpty ? R * 0.9 : inner[min(inner.count - 1, Int(Float(inner.count) * 0.05))]
        if r / max(1e-9, R) > 0.93 { r = R * 0.95 }       // single thin-wall shell
        return ArcTubeBore(name: part.name, pts: pts, bore: r, outer: max(R, r * 1.02), length: L)
    }
}

enum ArcChannelPhysics {
    /// Steady incompressible-liquid / choked-gas channel flow.
    /// dP: driving pressure drop (Pa), rho (kg/m^3), aRef: reference (smallest) flow
    /// area (m^2), segments: (area m^2, length m) per channel part, bends: count.
    /// Returns (velocity at aRef m/s, mass flow kg/s).
    static func flow(dP: Float, rho: Float, aRef: Float, segments: [(a: Float, len: Float)],
                     bends: Int, tempK: Float) -> (v: Float, mdot: Float) {
        guard dP > 0, rho > 0, aRef > 0 else { return (0, 0) }
        let gas = rho < 5
        let mu: Float = gas ? 1.8e-5 : 1.0e-3
        let rough: Float = 4.5e-5
        var v = sqrt(2 * dP / rho) * 0.7
        for _ in 0..<4 {
            var K: Float = 0.5 + 0.4 * Float(bends)          // inlet + bends
            for s in segments where s.len > 0 && s.a > 0 {
                let d = sqrt(4 * s.a / Float.pi)
                let vs = v * aRef / s.a                       // continuity: v ~ 1/A
                let re = max(1, rho * vs * d / mu)
                let f: Float
                if re < 2300 { f = 64 / re }
                else {
                    // Swamee-Jain (Colebrook explicit)
                    let t = log10(rough / (3.7 * d) + 5.74 / pow(re, 0.9))
                    f = 0.25 / (t * t)
                }
                let ar = aRef / s.a
                K += f * s.len / d * ar * ar                  // Darcy-Weisbach referred to aRef
            }
            v = sqrt(2 * dP / (rho * (1 + K)))
        }
        if gas { v = min(v, sqrt(1.4 * 287 * max(100, tempK))) }   // choked cap
        return (v, rho * aRef * v)
    }
}

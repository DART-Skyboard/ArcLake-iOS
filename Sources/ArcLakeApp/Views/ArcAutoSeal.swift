import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcAutoSeal — geometric joint detection (port of the Arc Flow web
// sandbox's detectPenetrationJoint / cavitiesAreConnected, ariel repo
// templates/arc-flow.html).
//
// Two parts whose meshes physically interpenetrate (a pipe pushed through
// a tank wall, a tank seated in a chamber) are tested for a through-cavity:
// sample the overlap region, label each sample "inside A only / inside B
// only / inside both", and require ONE 6-connected component to contain an
// exclusive sample of BOTH parts. If so the pair is a sealed fluid link and
// the engine applies an implied boolean cut-out of the receiving part's
// wall where it lies inside the other part's bore. If the meshes overlap
// but their hollow interiors never connect, the pair is reported as
// non-flowing (no cut-out).
// ═══════════════════════════════════════════════════════════════════

/// One mesh part (all triangles sharing a node name), world space, with a
/// three-axis parity ray index for point-in-mesh tests. Immutable after
/// init, so safe to share across threads.
final class ArcSealPart: @unchecked Sendable {
    let name: String
    let verts: [SIMD3<Float>]          // 3 per triangle
    let bmin: SIMD3<Float>
    let bmax: SIMD3<Float>
    private let n: Int                 // buckets per side
    private let buckets: [[Int32]]     // axis * n*n + bucket -> triangle ids

    var triangleCount: Int { verts.count / 3 }

    init(name: String, verts: [SIMD3<Float>]) {
        self.name = name
        self.verts = verts
        var lo = SIMD3<Float>(repeating: Float.infinity)
        var hi = SIMD3<Float>(repeating: -Float.infinity)
        for v in verts { lo = simd_min(lo, v); hi = simd_max(hi, v) }
        if verts.isEmpty { lo = .zero; hi = .zero }
        self.bmin = lo
        self.bmax = hi

        let triCount = verts.count / 3
        let side = max(8, min(96, Int(Double(triCount).squareRoot() / 2.0)))
        self.n = side
        var b = [[Int32]](repeating: [], count: 3 * side * side)
        let ext = hi - lo
        for t in 0..<triCount {
            let a = verts[t * 3], bb = verts[t * 3 + 1], c = verts[t * 3 + 2]
            let tlo = simd_min(a, simd_min(bb, c))
            let thi = simd_max(a, simd_max(bb, c))
            for axis in 0..<3 {
                let u = (axis + 1) % 3, w = (axis + 2) % 3
                let eu = max(ext[u], 1e-6), ew = max(ext[w], 1e-6)
                let u0 = max(0, min(side - 1, Int((tlo[u] - lo[u]) / eu * Float(side))))
                let u1 = max(0, min(side - 1, Int((thi[u] - lo[u]) / eu * Float(side))))
                let w0 = max(0, min(side - 1, Int((tlo[w] - lo[w]) / ew * Float(side))))
                let w1 = max(0, min(side - 1, Int((thi[w] - lo[w]) / ew * Float(side))))
                for iu in u0...u1 {
                    for iw in w0...w1 {
                        b[axis * side * side + iu * side + iw].append(Int32(t))
                    }
                }
            }
        }
        self.buckets = b
    }

    @inline(__always)
    private func rayHits(_ o: SIMD3<Float>, axis: Int, tri t: Int) -> Bool {
        let v0 = verts[t * 3]
        let e1 = verts[t * 3 + 1] - v0
        let e2 = verts[t * 3 + 2] - v0
        var d = SIMD3<Float>(0, 0, 0)
        d[axis] = 1
        let h = simd_cross(d, e2)
        let a = simd_dot(e1, h)
        if abs(a) < 1e-12 { return false }
        let f = 1 / a
        let s = o - v0
        let u = f * simd_dot(s, h)
        if u < 0 || u > 1 { return false }
        let q = simd_cross(s, e1)
        let v = f * simd_dot(d, q)
        if v < 0 || u + v > 1 { return false }
        let tt = f * simd_dot(e2, q)
        return tt > 1e-7
    }

    /// Point-in-mesh by majority vote of three axis-aligned parity rays —
    /// tolerant of the occasional edge double-hit or small mesh hole.
    func isInside(_ p: SIMD3<Float>) -> Bool {
        if verts.isEmpty { return false }
        if p.x < bmin.x || p.y < bmin.y || p.z < bmin.z ||
           p.x > bmax.x || p.y > bmax.y || p.z > bmax.z { return false }
        let ext = bmax - bmin
        var votes = 0
        for axis in 0..<3 {
            let u = (axis + 1) % 3, w = (axis + 2) % 3
            let eu = max(ext[u], 1e-6), ew = max(ext[w], 1e-6)
            let iu = max(0, min(n - 1, Int((p[u] - bmin[u]) / eu * Float(n))))
            let iw = max(0, min(n - 1, Int((p[w] - bmin[w]) / ew * Float(n))))
            var crossings = 0
            for t in buckets[axis * n * n + iu * n + iw] {
                if rayHits(p, axis: axis, tri: Int(t)) { crossings += 1 }
            }
            if crossings & 1 == 1 { votes += 1 }
        }
        return votes >= 2
    }

    var aabbVolume: Float {
        let s = bmax - bmin
        return abs(s.x * s.y * s.z)
    }
}

/// One detected joint between two parts.
public struct ArcSealJoint: Identifiable, Sendable {
    public var id: String { partA + "|" + partB }
    public let partA: String
    public let partB: String
    /// The part whose wall is cut away where it lies inside the other's bore.
    public let receiver: String
    public let centroid: SIMD3<Float>
    public let radius: Float
    public let zoneMin: SIMD3<Float>
    public let zoneMax: SIMD3<Float>
    /// true: through-cavity continuity confirmed (fluid link, cut-out applied).
    /// false: meshes overlap but their hollow interiors never connect (non-flowing).
    public let sealed: Bool
}

enum ArcAutoSeal {
    static let sampleRes = 9
    static let minOverlap: Float = 1e-6

    /// Test every unordered part pair whose AABBs intersect.
    static func detect(parts: [ArcSealPart], involving: Set<String>? = nil) -> [ArcSealJoint] {
        var out: [ArcSealJoint] = []
        guard parts.count >= 2 else { return out }
        for i in 0..<parts.count {
            for j in (i + 1)..<parts.count {
                let a = parts[i], b = parts[j]
                if let only = involving, !only.contains(a.name), !only.contains(b.name) { continue }
                guard a.triangleCount > 0, b.triangleCount > 0 else { continue }
                if a.bmin.x > b.bmax.x || b.bmin.x > a.bmax.x ||
                   a.bmin.y > b.bmax.y || b.bmin.y > a.bmax.y ||
                   a.bmin.z > b.bmax.z || b.bmin.z > a.bmax.z { continue }
                if let j = testPair(a, b) { out.append(j) }
            }
        }
        return out
    }

    private static func jitter(_ k: Float) -> Float {
        (k * 0.61803398875).truncatingRemainder(dividingBy: 1) * 0.3 - 0.15
    }

    /// Returns nil when the meshes don't actually share cavity volume.
    static func testPair(_ a: ArcSealPart, _ b: ArcSealPart) -> ArcSealJoint? {
        var lo = simd_max(a.bmin, b.bmin)
        var hi = simd_min(a.bmax, b.bmax)
        var size = hi - lo
        if size.x <= minOverlap || size.y <= minOverlap || size.z <= minOverlap { return nil }
        let pad = max(simd_length(size) * 0.08, 0.01)
        lo -= SIMD3<Float>(repeating: pad)
        hi += SIMD3<Float>(repeating: pad)
        size = hi - lo

        func sampleAt(_ r: Int, _ x: Int, _ y: Int, _ z: Int) -> SIMD3<Float> {
            let fr = Float(r)
            return SIMD3<Float>(
                lo.x + (Float(x) + 0.5 + jitter(Float(x + 1))) / fr * size.x,
                lo.y + (Float(y) + 0.5 + jitter(Float(y + 2))) / fr * size.y,
                lo.z + (Float(z) + 0.5 + jitter(Float(z + 3))) / fr * size.z)
        }

        // Stage 1 — cheap 5^3 probe: any sample inside BOTH cavities?
        let probe = 5
        var overlapsInVolume = false
        probeLoop: for z in 0..<probe { for y in 0..<probe { for x in 0..<probe {
            let p = sampleAt(probe, x, y, z)
            if a.isInside(p) && b.isInside(p) { overlapsInVolume = true; break probeLoop }
        }}}
        if !overlapsInVolume { return nil }

        // Stage 2 — full labeling grid.
        let res = sampleRes
        var labels = [Int8](repeating: 0, count: res * res * res)
        var pts = [SIMD3<Float>](repeating: .zero, count: res * res * res)
        for z in 0..<res { for y in 0..<res { for x in 0..<res {
            let p = sampleAt(res, x, y, z)
            let inA = a.isInside(p), inB = b.isInside(p)
            let i = (z * res + y) * res + x
            labels[i] = (inA && inB) ? 3 : (inA ? 1 : (inB ? 2 : 0))
            pts[i] = p
        }}}

        let sealed = cavitiesConnected(labels: labels, res: res)

        // Wall-crossing zone (see the web version's comment): anchor on the
        // label-3 samples touching whichever exclusive label has FEWER such
        // contacts — the through-going part's exit from the receiving one.
        var contacts1: [SIMD3<Float>] = [], contacts2: [SIMD3<Float>] = []
        for z in 0..<res { for y in 0..<res { for x in 0..<res {
            let i = (z * res + y) * res + x
            guard labels[i] == 3 else { continue }
            var nbs: [Int] = []
            if x > 0 { nbs.append(i - 1) }
            if x < res - 1 { nbs.append(i + 1) }
            if y > 0 { nbs.append(i - res) }
            if y < res - 1 { nbs.append(i + res) }
            if z > 0 { nbs.append(i - res * res) }
            if z < res - 1 { nbs.append(i + res * res) }
            for nb in nbs {
                if labels[nb] == 1 { contacts1.append(pts[i]); break }
                if labels[nb] == 2 { contacts2.append(pts[i]); break }
            }
        }}}
        let zone: [SIMD3<Float>]
        if !contacts1.isEmpty && !contacts2.isEmpty {
            zone = contacts1.count <= contacts2.count ? contacts1 : contacts2
        } else {
            zone = !contacts1.isEmpty ? contacts1 : contacts2
        }
        var use = zone
        if use.isEmpty {
            for i in 0..<labels.count where labels[i] == 3 { use.append(pts[i]) }
        }
        var centroid = (lo + hi) * 0.5
        var radius: Float = 0.02
        if !use.isEmpty {
            var sum = SIMD3<Float>.zero
            var zlo = SIMD3<Float>(repeating: Float.infinity)
            var zhi = SIMD3<Float>(repeating: -Float.infinity)
            for p in use { sum += p; zlo = simd_min(zlo, p); zhi = simd_max(zhi, p) }
            centroid = sum / Float(use.count)
            let ext = zhi - zlo
            let e = [ext.x, ext.y, ext.z].sorted()
            radius = max(e[1] * 0.5 + simd_length(size) / Float(res) * 0.25, 0.02)
        }

        // Receiver = the part with the larger envelope (the tank/chamber the
        // pipe is fitted into); its wall is what gets cut away.
        let receiver = a.aabbVolume >= b.aabbVolume ? a.name : b.name
        return ArcSealJoint(partA: a.name, partB: b.name, receiver: receiver,
                            centroid: centroid, radius: radius,
                            zoneMin: lo, zoneMax: hi, sealed: sealed)
    }

    /// True iff one 6-connected component of non-zero labels contains BOTH a
    /// label-1 (A-only) and a label-2 (B-only) sample. Label 3 alone never
    /// counts (a part wholly inside another would otherwise read as a joint).
    static func cavitiesConnected(labels: [Int8], res: Int) -> Bool {
        var visited = [Bool](repeating: false, count: labels.count)
        var stack: [Int] = []
        for start in 0..<labels.count {
            if labels[start] == 0 || visited[start] { continue }
            visited[start] = true
            stack.append(start)
            var sawA = false, sawB = false
            while let i = stack.popLast() {
                if labels[i] == 1 { sawA = true }
                if labels[i] == 2 { sawB = true }
                let z = i / (res * res)
                let y = (i - z * res * res) / res
                let x = i - z * res * res - y * res
                var nb: [Int] = []
                if x > 0 { nb.append(i - 1) }
                if x < res - 1 { nb.append(i + 1) }
                if y > 0 { nb.append(i - res) }
                if y < res - 1 { nb.append(i + res) }
                if z > 0 { nb.append(i - res * res) }
                if z < res - 1 { nb.append(i + res * res) }
                for k in nb where !visited[k] && labels[k] != 0 {
                    visited[k] = true
                    stack.append(k)
                }
            }
            if sawA && sawB { return true }
        }
        return false
    }
}

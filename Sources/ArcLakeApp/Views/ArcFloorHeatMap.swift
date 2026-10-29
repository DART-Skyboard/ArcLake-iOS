import Foundation
import SceneKit
import simd
import UIKit

// ═══════════════════════════════════════════════════════════════════
// ArcFloorHeatMap — tone-mapped thermal splash on the ground plane
// (port of the Arc Flow web sandbox's floor heat pass, ariel repo
// templates/arc-flow.html "tone-mapped floor thermal map").
//
// Fluid cells near the floor deposit into TWO accumulators per texel:
//   energy      (G) — how much fluid has landed there
//   heat-energy (R) — the same, weighted by normalised temperature
// At display time:   temp = heatEnergy / energy        (mean temperature)
//                    k    = 1 - exp(-1.4 * energy)     (soft saturation)
//                    col  = ramp(temp * 0.82) * (k*0.85)   — ramp capped
// below its near-white end, so thousands of overlapping deposits read as
// orange-gold instead of a blown-out white slab. Tone mapping runs on the
// CPU into a small RGBA8 texture (alpha = intensity, so the plane
// composites over whatever floor the scene already has).
// ═══════════════════════════════════════════════════════════════════

final class ArcFloorHeatMap {
    static let res = 64
    private var energy = [Float](repeating: 0, count: res * res)
    private var heatEnergy = [Float](repeating: 0, count: res * res)
    private var node: SCNNode?
    private var lo = SIMD2<Float>(0, 0)
    private var hi = SIMD2<Float>(1, 1)
    private(set) var floorY: Float = 0
    private var ticks = 0
    /// World-space band above the floor within which cells deposit.
    private(set) var band: Float = 1

    func configure(domainMin: SIMD3<Float>, domainMax: SIMD3<Float>, cellSize: Float) {
        lo = SIMD2<Float>(domainMin.x, domainMin.z)
        hi = SIMD2<Float>(domainMax.x, domainMax.z)
        floorY = domainMin.y
        band = max(cellSize * 3, 0.01)
        for i in 0..<energy.count { energy[i] = 0; heatEnergy[i] = 0 }
        ticks = 0
    }

    /// Deposit one fluid cell. `temp01` is normalised temperature (0...1).
    @inline(__always)
    func deposit(pos: SIMD3<Float>, density: Float, temp01: Float) {
        let h = pos.y - floorY
        guard h < band else { return }
        let falloff = max(0, 1 - max(0, h) / band)
        let amount = density * falloff * 0.02
        guard amount > 0 else { return }
        let u = (pos.x - lo.x) / max(1e-6, hi.x - lo.x)
        let v = (pos.z - lo.y) / max(1e-6, hi.y - lo.y)
        guard u >= 0, u < 1, v >= 0, v < 1 else { return }
        let ix = Int(u * Float(Self.res)), iz = Int(v * Float(Self.res))
        let i = iz * Self.res + ix
        energy[i] += amount
        heatEnergy[i] += amount * temp01
    }

    private static func ramp(_ tIn: Float) -> SIMD3<Float> {
        let cold = SIMD3<Float>(0.2, 0.55, 1.0)
        let mid  = SIMD3<Float>(0.0, 0.9, 0.85)
        let warm = SIMD3<Float>(1.0, 0.55, 0.15)
        let hot  = SIMD3<Float>(1.0, 0.95, 0.85)
        let t = max(0, min(1, tIn))
        if t < 0.33 { return cold + (mid - cold) * (t / 0.33) }
        if t < 0.66 { return mid + (warm - mid) * ((t - 0.33) / 0.33) }
        return warm + (hot - warm) * ((t - 0.66) / 0.34)
    }

    struct Geometry {
        var lo: SIMD2<Float>
        var hi: SIMD2<Float>
        var floorY: Float
        var band: Float
    }
    var geometry: Geometry { Geometry(lo: lo, hi: hi, floorY: floorY, band: band) }

    /// Sim queue: tone-map the accumulators into RGBA8 pixels. Returns nil
    /// except every few ticks (the texture needn't update at full rate).
    func tonemapIfDue() -> [UInt8]? {
        ticks += 1
        guard ticks % 4 == 0 else { return nil }
        let n = Self.res
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let e = energy[i]
            guard e > 1e-5 else { continue }
            let temp = max(0, min(1, heatEnergy[i] / max(e, 1e-4)))
            let k = 1 - expf(-e * 1.4)
            let c = Self.ramp(temp * 0.82)
            px[i * 4 + 0] = UInt8(max(0, min(255, c.x * 255)))
            px[i * 4 + 1] = UInt8(max(0, min(255, c.y * 255)))
            px[i * 4 + 2] = UInt8(max(0, min(255, c.z * 255)))
            px[i * 4 + 3] = UInt8(max(0, min(255, k * 0.85 * 255)))
        }
        return px
    }

    /// Main thread: put a tone-mapped image on the floor plane.
    func applyImage(_ px: [UInt8], geometry g: Geometry, in scene: SCNScene) {
        guard let image = Self.makeImage(px, Self.res) else { return }
        let sx = max(0.001, g.hi.x - g.lo.x), sz = max(0.001, g.hi.y - g.lo.y)
        let n3: SCNNode
        if let node {
            n3 = node
        } else {
            // "arc_light_" prefix: every scan/collision/thermal pass in the
            // engine already skips nodes with this prefix, so the floor
            // overlay is never mistaken for a part.
            let plane = SCNPlane(width: 1, height: 1)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
            m.diffuse.magnificationFilter = .linear
            plane.firstMaterial = m
            n3 = SCNNode(geometry: plane)
            n3.name = "arc_light_floorHeat"
            n3.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            n3.renderingOrder = -5
            scene.rootNode.addChildNode(n3)
            node = n3
        }
        n3.scale = SCNVector3(sx, sz, 1)
        n3.position = SCNVector3((g.lo.x + g.hi.x) * 0.5, g.floorY + g.band * 0.02, (g.lo.y + g.hi.y) * 0.5)
        n3.geometry?.firstMaterial?.diffuse.contents = image
    }

    func remove() {
        node?.removeFromParentNode()
        node = nil
    }

    private static func makeImage(_ px: [UInt8], _ n: Int) -> UIImage? {
        let data = Data(px)
        guard let provider = CGDataProvider(data: data as CFData),
              let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: n * 4, space: cs, bitmapInfo: info,
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

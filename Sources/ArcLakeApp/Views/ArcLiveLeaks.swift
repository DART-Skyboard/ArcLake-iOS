import Foundation
import SceneKit
import simd
import UIKit

// ═══════════════════════════════════════════════════════════════════
// ArcLiveLeaks — live pressure-driven leaks when a seal breaks mid-sim
// (port of the Arc Flow web sandbox's "LIVE PRESSURE-DRIVEN LEAKS",
// ariel repo templates/arc-flow.html).
//
// When a part is moved and a previously sealed joint no longer has a
// through-cavity, the fluid in the pressurised (source) part is converted
// from grid density into CPU particles that:
//   INSIDE  accelerate toward the gap with  a = K * dP / (pathLeft + L0)
//           where dP = P0 * (massLeft/mass0) - ambient  (mass-fraction
//           pressure decay: the rush fades as the vessel empties), and are
//           kept inside by the grid's solid wall cells (switched off inside
//           the gap mouth);
//   VENTED  past the mouth, leave with a jet speed ~ sqrt(dP), then gravity
//           + ambient-pressure drag + growing turbulence disperse them and
//           they fade out / die at the floor.
// Restoring the seal releases the group: unspent particles are returned to
// the grid. Rendering: trilinear density splat into the ray-march volume
// (see ArcVolumetricFluidRenderer.leakSplats) or a point cloud in the
// non-volumetric visual modes.
// ═══════════════════════════════════════════════════════════════════

struct ArcLeakSplat {
    var pos: SIMD3<Float>
    var w: Float      // density to deposit (already faded by age)
    var heat: Float   // 0...1
}

final class ArcLiveLeaks {
    /// Out-of-memory safety only, not a quality cap.
    static let maxParticles = 2_000_000
    static let gradK: Float = 0.35
    static let dragInside: Float = 1.2
    static let vmax: Float = 22
    static let jetK: Float = 1.0
    static let dpMin: Float = 2.0

    struct Group {
        var jointID: String
        var source: String
        var gap: SIMD3<Float>
        var outDir: SIMD3<Float>
        var radius: Float
        var p0Psi: Float
        var mass0: Float
        var massNow: Float
        var cells: [SIMD3<Int32>]      // source-cavity cells, nearest-to-gap first
        var cursor: Int = 0
        var lastDrain: Float = 0
    }

    struct Particle {
        var pos: SIMD3<Float>
        var vel: SIMD3<Float>
        var w: Float
        var heat: Float
        var age: Float = 0
        var life: Float = 0
        var state: UInt8   // 1 inside, 2 vented
        var group: Int
    }

    private(set) var groups: [Group] = []
    private(set) var particles: [Particle] = []
    private var clock: Float = 0

    var isActive: Bool { !groups.isEmpty || !particles.isEmpty }
    var activeJointIDs: Set<String> { Set(groups.map { $0.jointID }) }

    func status(for jointID: String) -> (gapDistLeft: Float, psiLeft: Float, psi0: Float)? {
        guard let g = groups.first(where: { $0.jointID == jointID }) else { return nil }
        let frac = g.mass0 > 1e-6 ? max(0, min(1, g.massNow / g.mass0)) : 0
        return (0, g.p0Psi * frac, g.p0Psi)
    }

    func open(jointID: String, source: String, gap: SIMD3<Float>, outDir: SIMD3<Float>,
              radius: Float, p0Psi: Float, cells: [SIMD3<Int32>], mass0: Float) {
        guard !groups.contains(where: { $0.jointID == jointID }) else { return }
        groups.append(Group(jointID: jointID, source: source, gap: gap, outDir: outDir,
                            radius: radius, p0Psi: p0Psi, mass0: max(mass0, 1e-4),
                            massNow: max(mass0, 1e-4), cells: cells, cursor: 0, lastDrain: -1))
    }

    /// Remove a group; returns the unspent INSIDE particles (position, weight) for re-injection.
    func close(jointID: String) -> [(SIMD3<Float>, Float)] {
        guard let gi = groups.firstIndex(where: { $0.jointID == jointID }) else { return [] }
        var back: [(SIMD3<Float>, Float)] = []
        particles.removeAll { p in
            if p.group == gi && p.state == 1 { back.append((p.pos, p.w)); return true }
            return false
        }
        // Re-index particle group references above the removed slot.
        for i in 0..<particles.count where particles[i].group > gi { particles[i].group -= 1 }
        // Vented particles of this group keep flying: detach them.
        for i in 0..<particles.count where particles[i].group == gi { particles[i].group = -1 }
        groups.remove(at: gi)
        return back
    }

    func reset() { groups.removeAll(); particles.removeAll(); clock = 0 }

    /// Pull more fluid out of each leaking source part's grid cells (nearest
    /// the gap first). `grid` density is reduced by exactly what is spawned.
    private func drain(grid: ArcSparseVoxelGrid, envTempK: Float) {
        for gi in 0..<groups.count {
            var g = groups[gi]
            // refresh remaining mass
            var mass: Float = 0
            for c in g.cells {
                let cell = grid[c]
                if !cell.isSolid { mass += cell.density }
            }
            g.massNow = mass
            var budget = max(60, g.cells.count / 20)
            while budget > 0 && particles.count < Self.maxParticles && g.cursor < g.cells.count {
                let c = g.cells[g.cursor]
                g.cursor += 1
                var cell = grid[c]
                guard !cell.isSolid, cell.density > 0.02 else { continue }
                let n = max(1, min(3, Int(cell.density * 2)))
                let take = cell.density * 0.9
                let center = grid.worldCenter(of: c)
                let h = grid.cellSize
                let heat = max(0, min(1, (cell.tempK - envTempK) / max(1, 2000 - envTempK)))
                for _ in 0..<n {
                    let j = SIMD3<Float>(Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5),
                                         Float.random(in: -0.5...0.5)) * h
                    particles.append(Particle(pos: center + j, vel: cell.velocity,
                                              w: take / Float(n), heat: heat, age: 0, life: 0,
                                              state: 1, group: gi))
                }
                cell.density -= take
                grid[c] = cell
                budget -= 1
            }
            // wrap cursor so a long leak keeps pulling from the source
            if g.cursor >= g.cells.count { g.cursor = 0 }
            groups[gi] = g
        }
    }

    /// Advance one tick. `isWall(p)` returns the wall normal if p is inside a
    /// solid cell, else nil. `scale` converts the web sandbox's unit scale to
    /// this scene (domain longest axis / 10).
    func step(dt: Float, grid: ArcSparseVoxelGrid, envTempK: Float, ambientPa: Float,
              gravity: SIMD3<Float>, scale: Float, floorY: Float) {
        guard isActive else { return }
        clock += dt
        let ambientPsi = ambientPa / 6894.76
        let atm = max(0.05, ambientPa / 101325)
        // drain every 0.2 s
        var needDrain = false
        for g in groups where clock - g.lastDrain >= 0.2 { needDrain = true; break }
        if needDrain {
            drain(grid: grid, envTempK: envTempK)
            for i in 0..<groups.count { groups[i].lastDrain = clock }
        }

        var i = 0
        while i < particles.count {
            var p = particles[i]
            var dead = false
            if p.state == 1 {
                if p.group < 0 || p.group >= groups.count { dead = true }
                else {
                    let g = groups[p.group]
                    let frac = g.mass0 > 1e-6 ? max(0, min(1, g.massNow / g.mass0)) : 0
                    let dP = max(0, g.p0Psi * frac - ambientPsi)
                    let toGap = g.gap - p.pos
                    let dist = simd_length(toGap)
                    let mouth = max(g.radius, grid.cellSize * 0.75)
                    if dist < mouth {
                        // leave through the gap: jet ~ sqrt(dP)
                        let spread = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1),
                                                  Float.random(in: -1...1)) * 0.25
                        let dir = simd_normalize(g.outDir + spread)
                        let jet = min(Self.vmax * scale, sqrt(max(dP, 1)) * Self.jetK * scale)
                        p.vel = dir * jet
                        p.state = 2
                        p.age = 0
                        p.life = Float.random(in: 1.5...3.5)
                    } else {
                        if dP > Self.dpMin {
                            let L0 = max(g.radius * 2, 0.05 * scale)
                            let a = Self.gradK * dP / (dist + L0) * scale
                            p.vel += (toGap / dist) * a * dt
                        }
                        p.vel *= expf(-Self.dragInside * dt)
                        let sp = simd_length(p.vel)
                        if sp > Self.vmax * scale { p.vel *= (Self.vmax * scale / sp) }
                        let np = p.pos + p.vel * dt
                        // walls (off inside the gap mouth)
                        let nearMouth = simd_length(g.gap - np) < mouth * 1.6
                        let cell = grid[grid.cellCoord(of: np)]
                        if cell.isSolid && !nearMouth {
                            var n = cell.solidNormal
                            if simd_length_squared(n) < 1e-6 { n = -simd_normalize(p.vel + SIMD3<Float>(1e-5, 0, 0)) }
                            let vn = simd_dot(p.vel, n)
                            if vn < 0 { p.vel -= 1.3 * vn * n }
                            // do not move into the wall this tick
                        } else {
                            p.pos = np
                        }
                    }
                }
            } else {
                p.vel += gravity * dt
                p.vel *= expf(-0.6 * atm * dt)
                p.age += dt
                let turb = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
                p.vel += turb * (0.8 * scale * min(2, p.age) * dt)
                p.pos += p.vel * dt
                if p.pos.y < floorY || p.age > p.life { dead = true }
            }
            if dead { particles.swapAt(i, particles.count - 1); particles.removeLast() }
            else { particles[i] = p; i += 1 }
        }
        // Groups with nothing left to give and no particles: retire them.
        // (jointID stays in the engine's leaking set until re-seal or restart.)
    }

    func splats() -> [ArcLeakSplat] {
        particles.map { p in
            let fade: Float = p.state == 2 ? max(0, 1 - p.age / max(p.life, 0.01)) : 1
            return ArcLeakSplat(pos: p.pos, w: p.w * fade, heat: p.heat)
        }
    }

    /// Point-cloud arrays for the non-volumetric visual modes (sim queue).
    func pointArrays() -> ([Float], [Float]) {
        var pos: [Float] = []; pos.reserveCapacity(particles.count * 3)
        var col: [Float] = []; col.reserveCapacity(particles.count * 4)
        for p in particles {
            pos += [p.pos.x, p.pos.y, p.pos.z]
            let fade: Float = p.state == 2 ? max(0, 1 - p.age / max(p.life, 0.01)) : 1
            let cool = SIMD3<Float>(0.35, 0.65, 1.0), hot = SIMD3<Float>(1.0, 0.6, 0.2)
            let c = cool + (hot - cool) * p.heat
            col += [c.x, c.y, c.z, 0.5 * fade]
        }
        return (pos, col)
    }

    /// Main thread: SceneKit geometry from point arrays.
    static func pointGeometry(pos: [Float], col: [Float], sprite: UIImage) -> SCNGeometry? {
        let n = pos.count / 3
        guard n > 0, col.count >= n * 4 else { return nil }
        let ps = SCNGeometrySource(data: Data(bytes: pos, count: pos.count * 4), semantic: .vertex,
                                   vectorCount: n, usesFloatComponents: true, componentsPerVector: 3,
                                   bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let cs = SCNGeometrySource(data: Data(bytes: col, count: col.count * 4), semantic: .color,
                                   vectorCount: n, usesFloatComponents: true, componentsPerVector: 4,
                                   bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let elem = SCNGeometryElement(indices: (0..<n).map { UInt32($0) }, primitiveType: .point)
        elem.pointSize = 3
        elem.minimumPointScreenSpaceRadius = 1.0
        elem.maximumPointScreenSpaceRadius = 6
        let geo = SCNGeometry(sources: [ps, cs], elements: [elem])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.blendMode = .add
        m.diffuse.contents = sprite
        geo.firstMaterial = m
        return geo
    }
}

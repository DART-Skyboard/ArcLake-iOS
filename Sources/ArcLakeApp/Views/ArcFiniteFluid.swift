import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcFiniteFluid — finite-mass container model (port of the Arc Flow web
// sandbox's "finite container mass / continuous flow"):
//   * Only CONTAINERS hold fluid. Pipes / chambers / nozzles start empty.
//   * A container's mass is volume x density (or the Mass field); its
//     pressure falls linearly with the fill fraction toward ambient.
//   * Mass drains through the chain of sealed (cavity-connected) parts to
//     the chain's open end; it is MOVED hop by hop in the voxel grid
//     (nothing is created, nothing re-emits).
//   * An open end whose mouth is pressed against a solid surface is
//     "plugged" and holds.
//   * continuousFlow ON replenishes the containers; OFF depletes them.
// Sim-queue owned. No locks, no blocking.
// ═══════════════════════════════════════════════════════════════════
final class ArcFiniteFluid {
    struct Tank {
        var name: String
        var rho: Float          // kg/m^3
        var p0Psi: Float        // absolute operating pressure when full
        var mass0: Float        // kg when full
        var mass: Float
        var d0: Float           // grid density-sum when full
        var color: SIMD3<Float>
    }
    struct State {
        var fill: Float
        var psi: Float
        var massKg: Float
        var flowing: Bool
        var note: String
    }

    private(set) var tanks: [String: Tank] = [:]
    private(set) var states: [String: State] = [:]
    /// Time a full container takes to drain at its design pressure (the
    /// real-time scale of the visual; the physics ratio is Bernoulli).
    var drainSeconds: Float = 60
    var isActive: Bool { !tanks.isEmpty }
    /// Last exhaust mouth (position, direction) — used by the ground wall-jet.
    private(set) var lastExit: (pos: SIMD3<Float>, dir: SIMD3<Float>)? = nil

    func reset() { tanks.removeAll(); states.removeAll() }

    // MARK: classification
    static func isContainer(_ s: ArcComponentSpec) -> Bool {
        let n = s.displayName.lowercased()
        if s.isCombustionChamber { return false }
        for w in ["nozzle", "chamber", "combustion", "throat", "exhaust", "pipe",
                  "channel", "tube", "duct", "hose", "manifold", "pressure"] where n.contains(w) { return false }
        if s.fluidType != nil { return true }
        if s.geometricKind == .container { return true }
        for w in ["tank", "vessel", "reservoir", "bottle", "dewar", "cylinder", "drum"] where n.contains(w) { return true }
        return false
    }

    // MARK: registration (after the cavity is seeded)
    func register(spec: ArcComponentSpec, rho: Float, color: SIMD3<Float>,
                  grid: ArcSparseVoxelGrid, unitM: Float) {
        let lo = grid.cellCoord(of: spec.boundingMin), hi = grid.cellCoord(of: spec.boundingMax)
        var d0: Float = 0
        if lo.x <= hi.x && lo.y <= hi.y && lo.z <= hi.z {
            for z in lo.z...hi.z { for y in lo.y...hi.y { for x in lo.x...hi.x {
                let cell = grid[SIMD3<Int32>(x, y, z)]
                if !cell.isSolid { d0 += cell.density }
            }}}
        }
        guard d0 > 1e-3 else { return }
        let s = spec.boundingMax - spec.boundingMin
        let volM3 = abs(s.x * s.y * s.z) * unitM * unitM * unitM * 0.7
        let m0: Float = spec.massKg > 0 ? Float(spec.massKg) : max(1e-6, volM3 * rho)
        tanks[spec.nodeName] = Tank(name: spec.nodeName, rho: max(1, rho),
                                    p0Psi: Float(spec.pressurePsi), mass0: m0, mass: m0,
                                    d0: d0, color: color)
    }

    // MARK: per-tick step
    private struct Plan {
        var tank: String
        var seq: [String]
        var toTank: Bool
        var take: Float
        var vScene: Float
        var exitPos: SIMD3<Float>
        var exitDir: SIMD3<Float>
        var exitR: Float
    }

    func step(dt: Float, grid: ArcSparseVoxelGrid, solver: ArcStableFluidSolver,
              specs: [ArcComponentSpec], joints: [ArcSealJoint],
              continuous: Bool, envPa: Float, unitM: Float, envTempK: Float,
              tubes: [String: ArcTubeBore] = [:], plume: ArcPlumeParams? = nil) {
        guard !tanks.isEmpty else { return }
        var specIdx: [String: Int] = [:]
        for (i, s) in specs.enumerated() { specIdx[s.nodeName] = i }
        var adj: [String: [String]] = [:]
        var jointBy: [String: ArcSealJoint] = [:]
        for j in joints where j.sealed {
            adj[j.partA, default: []].append(j.partB)
            adj[j.partB, default: []].append(j.partA)
            jointBy[j.partA + "|" + j.partB] = j
            jointBy[j.partB + "|" + j.partA] = j
        }
        let pEnvPsi = envPa / 6894.76
        func fillOf(_ t: Tank) -> Float { max(0, min(1, t.mass / max(1e-9, t.mass0))) }
        func psiOf(_ t: Tank) -> Float { pEnvPsi + max(0, t.p0Psi - pEnvPsi) * fillOf(t) }
        func center(_ n: String) -> SIMD3<Float>? {
            guard let i = specIdx[n] else { return nil }
            return (specs[i].boundingMin + specs[i].boundingMax) * 0.5
        }
        let cellH = grid.cellSize

        // ── Plans ──
        var plans: [Plan] = []
        var newStates: [String: State] = [:]
        for (name, t) in tanks {
            let f = fillOf(t)
            let pPsi = psiOf(t)
            var st = State(fill: f, psi: pPsi, massKg: t.mass, flowing: false, note: "closed")
            defer { newStates[name] = st }
            if t.mass <= t.mass0 * 1e-4 && !continuous { st.note = "empty"; continue }
            if (adj[name] ?? []).isEmpty { st.note = "no connected cavity"; continue }

            // BFS to a leaf / terminal part or a lower-pressure container.
            var prev: [String: String] = [:]
            var seen: Set<String> = [name]
            var queue: [String] = [name]
            var goal: String? = nil
            var goalTank = false
            var qi = 0
            search: while qi < queue.count {
                let u = queue[qi]; qi += 1
                for v in adj[u] ?? [] where !seen.contains(v) {
                    seen.insert(v); prev[v] = u
                    if let ot = tanks[v] {
                        if psiOf(ot) < pPsi - 1 && fillOf(ot) < 0.999 { goal = v; goalTank = true; break search }
                        continue
                    }
                    queue.append(v)
                    if (adj[v] ?? []).count == 1 { goal = v; break search }
                }
            }
            if goal == nil {
                let cand = queue.dropFirst()
                goal = cand.first(where: { n in
                    let l = (specIdx[n].map { specs[$0].displayName.lowercased() }) ?? ""
                    return l.contains("nozzle") || l.contains("chamber") || l.contains("combustion")
                        || l.contains("exhaust") || l.contains("throat")
                }) ?? cand.last
            }
            guard let g = goal else { st.note = "no outlet"; continue }
            var seq: [String] = [g]
            var cur = g
            while let p = prev[cur] { seq.append(p); cur = p }
            seq.reverse()
            guard seq.first == name, seq.count >= 2 else { st.note = "no outlet"; continue }

            // Smallest flow area along the path.
            var A = Float.greatestFiniteMagnitude
            for k in 0..<(seq.count - 1) {
                if let j = jointBy[seq[k] + "|" + seq[k + 1]] {
                    let r = max(j.radius, 1e-4) * unitM
                    A = min(A, Float.pi * r * r)
                }
            }
            var segs: [(a: Float, len: Float)] = []
            var bends = 0
            for nm in seq.dropFirst() where tanks[nm] == nil {
                if let tb = tubes[nm] {
                    let a = Float.pi * tb.bore * tb.bore * unitM * unitM
                    A = min(A, a)
                    segs.append((a, tb.length * unitM))
                    bends += tb.bends
                } else if let i = specIdx[nm] {
                    let s = specs[i].boundingMax - specs[i].boundingMin
                    let d = [abs(s.x), abs(s.y), abs(s.z)].sorted()
                    let a = 0.7854 * d[0] * d[1] * unitM * unitM
                    A = min(A, a)
                    if d[2] > 3 * max(1e-6, d[1]) { segs.append((a, d[2] * unitM)) }
                }
            }
            // Direction changes between consecutive path parts count as bends.
            if seq.count >= 3 {
                for k in 1..<(seq.count - 1) {
                    if let a = center(seq[k - 1]), let b = center(seq[k]), let c = center(seq[k + 1]) {
                        let d0 = b - a, d1 = c - b
                        if simd_length(d0) > 1e-6, simd_length(d1) > 1e-6,
                           simd_dot(simd_normalize(d0), simd_normalize(d1)) < 0.866 { bends += 1 }
                    }
                }
            }
            guard A.isFinite, A > 1e-12 else { st.note = "no flow area"; continue }

            // Exit mouth (open end of the chain) + plug test.
            var exitPos = SIMD3<Float>.zero
            var exitDir = SIMD3<Float>(0, -1, 0)
            var exitR: Float = cellH
            var dP: Float
            let dP0: Float = max(0, t.p0Psi - pEnvPsi) * 6894.76
            if goalTank, let ot = tanks[g] {
                dP = (pPsi - psiOf(ot)) * 6894.76
            } else {
                dP = (pPsi - pEnvPsi) * 6894.76
                if let gi = specIdx[g] {
                    let bmin = specs[gi].boundingMin, bmax = specs[gi].boundingMax
                    let c = (bmin + bmax) * 0.5
                    var mean = SIMD3<Float>.zero; var cnt: Float = 0
                    for nb in adj[g] ?? [] { if let nc = center(nb) { mean += nc; cnt += 1 } }
                    var delta = cnt > 0 ? c - mean / cnt : SIMD3<Float>(0, -1, 0)
                    if simd_length(delta) < 1e-6 { delta = SIMD3<Float>(0, -1, 0) }
                    var ax = 0
                    if abs(delta.y) > abs(delta[ax]) { ax = 1 }
                    if abs(delta.z) > abs(delta[ax]) { ax = 2 }
                    var dir = SIMD3<Float>.zero
                    dir[ax] = delta[ax] >= 0 ? 1 : -1
                    exitDir = dir
                    let pe1 = (ax + 1) % 3, pe2 = (ax + 2) % 3
                    exitR = max(cellH * 0.6, 0.25 * ((bmax[pe1] - bmin[pe1]) + (bmax[pe2] - bmin[pe2])))
                    lastExit = (c + dir * ((bmax[ax] - bmin[ax]) * 0.5), dir)
                    let half = (bmax[ax] - bmin[ax]) * 0.5
                    exitPos = c + dir * (half + cellH * 1.2)
                    let pc = grid.cellCoord(of: exitPos + dir * cellH)
                    if grid[pc].isSolid || grid[grid.cellCoord(of: exitPos)].isSolid
                        || grid.isFineSolid(at: exitPos + dir * cellH * 0.5) {
                        st.note = "outlet plugged"; continue
                    }
                }
            }
            guard dP > 50 else { st.note = "no pressure differential"; continue }
            let fl = ArcChannelPhysics.flow(dP: dP, rho: t.rho, aRef: A, segments: segs, bends: bends, tempK: envTempK)
            let fl0 = ArcChannelPhysics.flow(dP: max(dP0, 1), rho: t.rho, aRef: A, segments: segs, bends: bends, tempK: envTempK)
            let mdot = fl.mdot
            let mdot0 = fl0.mdot
            let ts = t.mass0 / (max(mdot0, 1e-9) * max(1, drainSeconds))
            var dm = mdot * ts * dt
            if f < 0.01 && !continuous { dm = t.mass }
            if !continuous { dm = min(dm, t.mass) }
            let take = dm / t.mass0 * t.d0
            let vmax = 45 * cellH
            let vScene = vmax * min(1, max(0.25, fl.v / max(1e-6, fl0.v)))
            st.flowing = true
            st.note = goalTank ? "transfer" : "venting"
            plans.append(Plan(tank: name, seq: seq, toTank: goalTank, take: take, vScene: vScene,
                              exitPos: exitPos, exitDir: exitDir, exitR: exitR))
        }

        // ── Grid pass: density per member node ──
        var memberSet = Set(tanks.keys)
        for p in plans { for n in p.seq { memberSet.insert(n) } }
        struct Node { var name: String; var lo: SIMD3<Float>; var hi: SIMD3<Float>; var vol: Float }
        var nodes: [Node] = []
        for n in memberSet {
            guard let i = specIdx[n] else { continue }
            let lo = specs[i].boundingMin - SIMD3<Float>(repeating: cellH * 0.5)
            let hi = specs[i].boundingMax + SIMD3<Float>(repeating: cellH * 0.5)
            let s = hi - lo
            nodes.append(Node(name: n, lo: lo, hi: hi, vol: abs(s.x * s.y * s.z)))
        }
        nodes.sort { $0.vol < $1.vol }
        var cellsOf: [String: [SIMD3<Int32>]] = [:]
        var avail: [String: Float] = [:]
        for c in grid.activeCoords() {
            let cell = grid[c]
            guard !cell.isSolid, cell.density > 0.005 else { continue }
            let p = grid.worldCenter(of: c)
            for n in nodes where p.x >= n.lo.x && p.y >= n.lo.y && p.z >= n.lo.z
                && p.x <= n.hi.x && p.y <= n.hi.y && p.z <= n.hi.z {
                cellsOf[n.name, default: []].append(c)
                avail[n.name, default: 0] += cell.density
                break
            }
        }
        func scale(_ name: String, to newSum: Float) {
            guard let a = avail[name], a > 1e-6, let cs = cellsOf[name] else { return }
            let f = max(0, newSum) / a
            for c in cs {
                var cell = grid[c]
                cell.density = min(1, cell.density * f)
                grid[c] = cell
            }
            avail[name] = max(0, newSum)
        }
        func inject(_ q: Float, near pos: SIMD3<Float>, dir: SIMD3<Float>, vel: SIMD3<Float>,
                    color: SIMD3<Float>, tag: Int32) {
            guard q > 1e-5 else { return }
            var p = pos
            var tries = 0
            while tries < 4, grid[grid.cellCoord(of: p)].isSolid { p += dir * cellH; tries += 1 }
            let n = max(1, min(8, Int(ceil(q / 0.35))))
            let per = q / Float(n)
            for _ in 0..<n {
                let j = n == 1 ? SIMD3<Float>.zero
                    : SIMD3<Float>(Float.random(in: -0.6...0.6), Float.random(in: -0.6...0.6),
                                   Float.random(in: -0.6...0.6)) * cellH
                solver.addSource(at: p + j, density: per, tempK: envTempK, velocity: vel,
                                 color: color, componentTag: tag)
            }
        }

        func injectPlume(_ q: Float, plume pm: ArcPlumeParams, pl: Plan) {
            guard q > 1e-5 else { return }
            let dir = pl.exitDir
            let ref: SIMD3<Float> = abs(dir.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let u = simd_normalize(simd_cross(dir, ref))
            let w = simd_cross(dir, u)
            let n = max(1, min(12, Int(ceil(q / 0.3))))
            let per = q / Float(n)
            let vmag = pl.vScene * pm.vScaleRel
            let hot = SIMD3<Float>(1.0, 0.62, 0.2)
            for _ in 0..<n {
                let ang = Float.random(in: 0..<(2 * Float.pi))
                let rr = sqrt(Float.random(in: 0..<1)) * pl.exitR * 0.85
                let radial = u * cos(ang) + w * sin(ang)
                let frac = rr / max(1e-6, pl.exitR)
                let vel = dir * vmag + radial * (vmag * tan(pm.halfAngle) * frac)
                solver.addSource(at: pl.exitPos + radial * rr, density: per, tempK: pm.Te,
                                 velocity: vel, color: hot, componentTag: -1)
            }
            // Mach diamonds: hot spots along the axis at the shock-cell spacing.
            if pm.diamondSpacing > 0 {
                let spacing = pm.diamondSpacing * 2 * pl.exitR
                for k in 1...4 {
                    solver.addSource(at: pl.exitPos + dir * (spacing * Float(k)), density: 0,
                                     tempK: pm.Te * 1.25, velocity: .zero, color: hot, componentTag: -1)
                }
            }
        }

        // ── Apply plans ──
        for pl in plans {
            guard let t = tanks[pl.tank] else { continue }
            var take = pl.take
            // Tank side.
            let aT = avail[pl.tank] ?? 0
            if continuous {
                if aT > 0.05 && aT < t.d0 { scale(pl.tank, to: min(aT * 1.5, t.d0)) }
            } else {
                take = min(take, aT * 0.98)
                if take > 0 { scale(pl.tank, to: aT - take) }
            }
            guard take > 0 else { continue }
            let seq = pl.seq
            func hopDir(_ k: Int) -> SIMD3<Float> {
                guard let a = center(seq[k]), let b = center(seq[k + 1]) else { return SIMD3<Float>(0, -1, 0) }
                let d = b - a
                return simd_length(d) < 1e-6 ? SIMD3<Float>(0, -1, 0) : simd_normalize(d)
            }
            func hopPos(_ k: Int) -> SIMD3<Float>? {
                if let j = jointBy[seq[k] + "|" + seq[k + 1]] { return j.centroid }
                return center(seq[k + 1])
            }
            // Exit (downstream end first so material arrives next tick).
            if !pl.toTank, let last = seq.last {
                let aL = avail[last] ?? 0
                let q = min(take, aL * 0.9)
                if q > 0 {
                    scale(last, to: aL - q)
                    if let pm = plume {
                        injectPlume(q, plume: pm, pl: pl)
                    } else {
                        inject(q, near: pl.exitPos, dir: pl.exitDir, vel: pl.exitDir * pl.vScene,
                               color: t.color, tag: -1)
                    }
                }
            }
            // Hops, descending, then the tank's own hop.
            if seq.count >= 3 {
                for k in stride(from: seq.count - 2, through: 1, by: -1) {
                    let from = seq[k]
                    let aF = avail[from] ?? 0
                    let q = min(take, aF * 0.9)
                    guard q > 0, let pos = hopPos(k) else { continue }
                    scale(from, to: aF - q)
                    let d = hopDir(k)
                    inject(q, near: pos, dir: d, vel: d * pl.vScene, color: t.color,
                           tag: Int32(specIdx[seq[k + 1]] ?? -1))
                }
            }
            if let pos = hopPos(0) {
                let d = hopDir(0)
                inject(take, near: pos, dir: d, vel: d * pl.vScene, color: t.color,
                       tag: Int32(specIdx[seq[1]] ?? -1))
            }
        }

        // ── Derive masses from the grid (captures leaks / drainage by gravity) ──
        for (name, var t) in tanks {
            let a = avail[name] ?? 0
            if continuous {
                t.mass = t.mass0
            } else {
                t.mass = t.mass0 * max(0, min(1, a / max(1e-6, t.d0)))
                if t.mass < t.mass0 * 1e-3 {
                    // Run dry: clear the residual film.
                    scale(name, to: 0)
                    t.mass = 0
                }
            }
            tanks[name] = t
            var st = newStates[name] ?? State(fill: 0, psi: pEnvPsi, massKg: 0, flowing: false, note: "")
            st.fill = fillOf(t); st.psi = psiOf(t); st.massKg = t.mass
            if t.mass <= 0 && !continuous { st.note = "empty"; st.flowing = false }
            newStates[name] = st
        }
        states = newStates
    }
}

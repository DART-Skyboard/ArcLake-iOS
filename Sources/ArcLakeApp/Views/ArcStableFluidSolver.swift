import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcStableFluidSolver — Jos Stam's "Stable Fluids" (SIGGRAPH 1999)
// implemented against ArcSparseVoxelGrid.
//
// Unconditionally stable at any time step: advection is solved by
// backward semi-Lagrangian tracing (look where this parcel of fluid
// CAME from, sample it there) rather than forward integration, so
// there is no CFL-type blow-up to guard against — this replaces
// ArcFluidEngine v2's VMAX velocity clamp, which was a band-aid for
// exactly that instability in the old explicit-Euler SPH step.
//
// Vstep (velocity): addForce → advect → diffuse → project
// Sstep (scalar, density/temp): addSource → advect → diffuse → dissipate
//
// Diffusion and projection use Gauss-Seidel relaxation rather than
// Stam's FFT solver — FFT requires a dense periodic domain, and this
// grid is sparse and bounded by mesh geometry, so Gauss-Seidel (which
// only needs a neighbor stencil) is the correct fit here. This is the
// same substitution Stam's paper itself recommends for non-periodic
// boundary conditions.
//
// Reference: Jos Stam, "Stable Fluids," SIGGRAPH 1999.
// Integrated: Radical Deepscale LLC / DART Meadow — Arc Edge CFD v3.0
// ═══════════════════════════════════════════════════════════════════

public final class ArcStableFluidSolver {

    public let grid: ArcSparseVoxelGrid

    /// Gauss-Seidel iteration count for diffuse/project solves.
    /// 20 matches Stam's reference implementation; higher converges
    /// tighter at linear cost, lower is cheaper but more viscous-looking.
    public var relaxIterations = 20

    /// Viscosity / thermal diffusion rate — mode-dependent, set by
    /// ArcFluidEngine from ArcFluidParams.visc.
    public var viscosity: Float = 0.02
    public var thermalDiffusion: Float = 0.08
    public var densityDissipation: Float = 0.001

    /// Ambient reference temperature for buoyancy and the "relax toward
    /// ambient" dissipation term — set by ArcFluidEngine.start(...) from
    /// envTempK. Replaces the hardcoded `293` literal (v3.1 fix, item 10)
    /// so buoyancy/dissipation respect a non-default environment temp.
    public var ambientTempK: Float = 293

    public init(grid: ArcSparseVoxelGrid) {
        self.grid = grid
    }

    // MARK: — Vstep: velocity update

    public func velocityStep(dt: Float, gravity: SIMD3<Float>) {
        addForces(dt: dt, gravity: gravity)
        advectVelocity(dt: dt)
        diffuseVelocity(dt: dt)
        project()
    }

    private func addForces(dt: Float, gravity: SIMD3<Float>) {
        grid.forEachActive { _, cell in
            guard !cell.isSolid else { return }
            // Buoyancy: hotter cells rise (thermal lift), opposing gravity
            // proportional to (T - ambient) — simple Boussinesq approximation,
            // consistent with ArcFluidEngine's existing thermal/pressure coupling.
            let buoyancy = max(0, (cell.tempK - ambientTempK) * 0.00004)
            cell.velocity += (gravity * (1 - buoyancy) ) * dt
        }
    }

    /// Backward semi-Lagrangian advection — the core of why this is
    /// "stable" at any dt. For each cell, trace a particle backward
    /// along the current velocity field by dt, and sample the
    /// previous field there (trilinear-interpolated).
    private func advectVelocity(dt: Float) {
        // v3.1 fix (item 10): materialize the 6-neighborhood of every
        // active cell BEFORE sampling, so fluid can flow into a
        // not-yet-materialized neighboring voxel instead of being
        // silently discarded at the edge of the active set. `ensure`
        // starts a freshly-created cell's empty streak at 0, so this
        // doesn't fight with the reclaim-timing fix (ArcSparseVoxelGrid.
        // advanceFrame/ensure).
        materializeActiveHalo()

        let coords = grid.activeCoords()
        var sampled: [(SIMD3<Int32>, SIMD3<Float>)] = []
        sampled.reserveCapacity(coords.count)
        for c in coords {
            let cell = grid[c]
            guard !cell.isSolid else { continue }
            let worldPos = grid.worldCenter(of: c)
            let backPos = worldPos - cell.velocity * dt
            // v3.1 fix (item 3): clip the backward-trace sample position
            // at the first solid cell encountered along the segment from
            // worldPos to backPos, so a thin wall can't leak the far
            // side's fluid state into this cell via trilinear
            // interpolation. The clip happens here (the caller), not
            // inside trilinearSample itself, since other callers may
            // want the raw unclipped interpolation.
            let clippedBackPos = clipSampleAgainstWalls(from: worldPos, to: backPos)
            let sample = grid.trilinearSample(at: clippedBackPos)
            sampled.append((c, sample.velocity))
        }
        for (c, v) in sampled {
            var cell = grid[c]
            cell.velocityPrev = cell.velocity
            cell.velocity = v
            grid[c] = cell
        }
    }

    /// Materialize the 6-connected face neighborhood of every currently
    /// active cell. Cheap relative to the Gauss-Seidel passes (one pass,
    /// no relaxation), and ensures advection/diffusion have somewhere to
    /// write when fluid is about to move into an empty neighboring cell.
    private func materializeActiveHalo() {
        let coords = grid.activeCoords()
        for c in coords {
            for n in grid.neighbors6(of: c) {
                _ = grid.ensure(n)
            }
        }
    }

    /// Walk from `worldPos` toward `backPos` in a small fixed number of
    /// steps, stopping (clipping) at the first step whose cell is solid
    /// — either at the main grid resolution or the fine boundary lookup
    /// (see ArcSparseVoxelGrid.isFineSolid, the v3.1 adaptive-collision
    /// addition for tight passages). Doesn't need to be exact, just has
    /// to stop fluid state from sampling across a wall.
    private func clipSampleAgainstWalls(from worldPos: SIMD3<Float>, to backPos: SIMD3<Float>) -> SIMD3<Float> {
        let steps = 6
        var lastSafe = worldPos
        for i in 1...steps {
            let t = Float(i) / Float(steps)
            let p = worldPos + (backPos - worldPos) * t
            let c = grid.cellCoord(of: p)
            if grid[c].isSolid || grid.isFineSolid(at: p) {
                return lastSafe
            }
            lastSafe = p
        }
        return backPos
    }

    /// Implicit diffusion via Gauss-Seidel relaxation. Implicit (rather
    /// than explicit forward diffusion) is what makes this stable for
    /// any diffusion rate × dt — an explicit version would need a tiny
    /// dt to not oscillate/blow up for viscous fluids.
    private func diffuseVelocity(dt: Float) {
        guard viscosity > 0 else { return }
        // v3.1 fix (item 10): per the classic Stable Fluids discretization,
        // the implicit diffusion coefficient scales with 1/cellSize² so
        // world-space diffusion rate is independent of voxel resolution.
        let h = grid.cellSize
        let a = dt * viscosity / (h * h)
        let coords = grid.activeCoords()

        // v3.1 fix (item 1): snapshot the just-advected velocity field
        // into velocityPrev at the START of this diffuse call, before
        // the relaxation loop. The old code read cell.velocityPrev as
        // the Gauss-Seidel source term, but velocityPrev was only ever
        // set by advectVelocity — it held the PRE-advection value for
        // the whole diffuse pass, so diffusion kept pulling the
        // just-advected field back toward stale (pre-advection) data
        // every sweep instead of relaxing around the current advected
        // state.
        for c in coords {
            var cell = grid[c]
            cell.velocityPrev = cell.velocity
            grid[c] = cell
        }

        for _ in 0..<relaxIterations {
            for c in coords {
                var cell = grid[c]
                guard !cell.isSolid else { continue }
                var sum = SIMD3<Float>.zero
                var count: Float = 0
                for n in grid.neighbors6(of: c) {
                    let nc = grid[n]
                    guard !nc.isSolid else { continue }
                    sum += nc.velocity
                    count += 1
                }
                guard count > 0 else { continue }
                cell.velocity = (cell.velocityPrev + a * sum) / (1 + a * count)
                grid[c] = cell
            }
        }
    }

    /// Helmholtz-Hodge projection: decompose the velocity field into a
    /// divergence-free part + a gradient field, subtract the gradient.
    /// This is what actually enforces incompressibility (∇·u = 0) —
    /// SPH v2 only approximated this through pairwise pressure forces.
    public func project() {
        let coords = grid.activeCoords()
        let h = grid.cellSize

        // Divergence of velocity field at each cell
        for c in coords {
            var cell = grid[c]
            guard !cell.isSolid else { continue }
            var div: Float = 0
            let axes: [(SIMD3<Int32>, SIMD3<Int32>, KeyPath<SIMD3<Float>, Float>)] = [
                (SIMD3<Int32>(1,0,0), SIMD3<Int32>(-1,0,0), \.x),
                (SIMD3<Int32>(0,1,0), SIMD3<Int32>(0,-1,0), \.y),
                (SIMD3<Int32>(0,0,1), SIMD3<Int32>(0,0,-1), \.z),
            ]
            for (pos, neg, axis) in axes {
                let vPos = grid[c &+ pos].velocity[keyPath: axis]
                let vNeg = grid[c &+ neg].velocity[keyPath: axis]
                div += (vPos - vNeg)
            }
            cell.divergence = -0.5 * h * div
            cell.pressure = 0
            grid[c] = cell
        }

        // Solve Poisson equation for pressure via Gauss-Seidel
        for _ in 0..<relaxIterations {
            for c in coords {
                var cell = grid[c]
                guard !cell.isSolid else { continue }
                var sum: Float = 0
                var count: Float = 0
                for n in grid.neighbors6(of: c) {
                    let nc = grid[n]
                    guard !nc.isSolid else { continue }
                    sum += nc.pressure
                    count += 1
                }
                guard count > 0 else { continue }
                cell.pressure = (cell.divergence + sum) / count
                grid[c] = cell
            }
        }

        // Subtract pressure gradient from velocity — result is divergence-free.
        //
        // v3.1 fix (item 10): the Poisson solve above EXCLUDES solid
        // neighbors from its averaging (count only increments for
        // non-solid neighbors), but this gradient step used to read
        // pressure=0 for a solid neighbor unconditionally — an
        // inconsistent boundary treatment between the two passes. Make
        // the gradient step use the same solid-neighbor exclusion: for
        // each axis, if the neighbor on one side is solid, mirror the
        // opposite-side value (zero-gradient / free-slip at the wall,
        // matching "excluded from averaging" rather than "pressure is
        // exactly 0 at the wall") instead of substituting a literal 0.
        for c in coords {
            var cell = grid[c]
            guard !cell.isSolid else { continue }
            let xPosCell = grid[c &+ SIMD3<Int32>(1,0,0)]
            let xNegCell = grid[c &- SIMD3<Int32>(1,0,0)]
            let yPosCell = grid[c &+ SIMD3<Int32>(0,1,0)]
            let yNegCell = grid[c &- SIMD3<Int32>(0,1,0)]
            let zPosCell = grid[c &+ SIMD3<Int32>(0,0,1)]
            let zNegCell = grid[c &- SIMD3<Int32>(0,0,1)]

            let pxPos = xPosCell.isSolid ? (xNegCell.isSolid ? cell.pressure : xNegCell.pressure) : xPosCell.pressure
            let pxNeg = xNegCell.isSolid ? (xPosCell.isSolid ? cell.pressure : xPosCell.pressure) : xNegCell.pressure
            let pyPos = yPosCell.isSolid ? (yNegCell.isSolid ? cell.pressure : yNegCell.pressure) : yPosCell.pressure
            let pyNeg = yNegCell.isSolid ? (yPosCell.isSolid ? cell.pressure : yPosCell.pressure) : yNegCell.pressure
            let pzPos = zPosCell.isSolid ? (zNegCell.isSolid ? cell.pressure : zNegCell.pressure) : zPosCell.pressure
            let pzNeg = zNegCell.isSolid ? (zPosCell.isSolid ? cell.pressure : zPosCell.pressure) : zNegCell.pressure

            cell.velocity.x -= 0.5 * (pxPos - pxNeg) / h
            cell.velocity.y -= 0.5 * (pyPos - pyNeg) / h
            cell.velocity.z -= 0.5 * (pzPos - pzNeg) / h

            // Also respect the fine-resolution boundary lookup: if this
            // cell's world center sits inside a fine solid sub-cell
            // (narrow-passage boundary finer than the main grid, see
            // ArcSparseVoxelGrid's adaptive-collision addition), zero
            // the velocity outright rather than let a spurious gradient
            // push fluid through a sub-voxel wall the coarse isSolid
            // flag doesn't see.
            if grid.isFineSolid(at: grid.worldCenter(of: c)) {
                cell.velocity = .zero
            }
            grid[c] = cell
        }
    }

    // MARK: — Sstep: scalar (density / temperature) update

    public func scalarStep(dt: Float) {
        advectScalars(dt: dt)
        diffuseScalars(dt: dt)
        dissipateDensity(dt: dt)
    }

    private func advectScalars(dt: Float) {
        // v3.1 fix (item 10): same halo pre-materialization as
        // advectVelocity, so scalar transport (density/temperature) can
        // flow into not-yet-materialized neighboring cells too.
        materializeActiveHalo()

        let coords = grid.activeCoords()
        var sampled: [(SIMD3<Int32>, Float, Float)] = []
        sampled.reserveCapacity(coords.count)
        for c in coords {
            let cell = grid[c]
            guard !cell.isSolid else { continue }
            let worldPos = grid.worldCenter(of: c)
            let backPos = worldPos - cell.velocity * dt
            // v3.1 fix (item 3): same wall-clipping walk as
            // advectVelocity — a thin wall must not leak the far side's
            // density/temperature into this cell via interpolation.
            let clippedBackPos = clipSampleAgainstWalls(from: worldPos, to: backPos)
            let sample = grid.trilinearSample(at: clippedBackPos)
            sampled.append((c, sample.density, sample.tempK))
        }
        for (c, d, t) in sampled {
            var cell = grid[c]
            cell.densityPrev = cell.density
            cell.density = d
            cell.tempK = t
            grid[c] = cell
        }
    }

    private func diffuseScalars(dt: Float) {
        guard thermalDiffusion > 0 else { return }
        // v3.1 fix (item 10): same cellSize² scaling as diffuseVelocity.
        let h = grid.cellSize
        let a = dt * thermalDiffusion / (h * h)
        let coords = grid.activeCoords()

        // v3.1 fix (item 1): snapshot the just-advected density AND
        // temperature into densityPrev/tempKPrev at the START of this
        // diffuse call, before the relaxation loop — same stale-snapshot
        // bug as diffuseVelocity, but here it hit two fields: densityPrev
        // was only ever set by advectScalars (same issue as velocity),
        // and tempK had NO saved pre-diffusion value at all — the old
        // code read back into `cell.tempK` on every sweep, which isn't
        // even a valid implicit-diffusion source term (it's the value
        // being solved for, re-used as its own prior). tempKPrev (added
        // to ArcVoxelCell) fixes this the same way densityPrev does.
        for c in coords {
            var cell = grid[c]
            cell.densityPrev = cell.density
            cell.tempKPrev = cell.tempK
            grid[c] = cell
        }

        for _ in 0..<relaxIterations {
            for c in coords {
                var cell = grid[c]
                guard !cell.isSolid else { continue }
                var sumD: Float = 0, sumT: Float = 0, count: Float = 0
                for n in grid.neighbors6(of: c) {
                    let nc = grid[n]
                    guard !nc.isSolid else { continue }
                    sumD += nc.density
                    sumT += nc.tempK
                    count += 1
                }
                guard count > 0 else { continue }
                cell.density = (cell.densityPrev + a * sumD) / (1 + a * count)
                cell.tempK   = (cell.tempKPrev + a * sumT) / (1 + a * count)
                grid[c] = cell
            }
        }
    }

    private func dissipateDensity(dt: Float) {
        guard densityDissipation > 0 else { return }
        grid.forEachActive { _, cell in
            cell.density = max(0, cell.density - densityDissipation * dt)
            // Temperature relaxes toward ambient slowly — keeps thermal
            // colormap from being permanently "stuck hot" once a
            // combustion event passes. v3.1 fix (item 10): use the
            // configured ambientTempK instead of the hardcoded 293,
            // consistent with addForces' buoyancy term.
            cell.tempK += (ambientTempK - cell.tempK) * min(1, densityDissipation * 4 * dt)
        }
    }

    // MARK: — Sources

    /// Inject density/temperature/velocity at a world-space point —
    /// used by ArcFluidEngine's cavity-fill / inlet logic instead of
    /// spawning raw SPH particles.
    public func addSource(at worldPos: SIMD3<Float>, density: Float, tempK: Float,
                           velocity: SIMD3<Float>, color: SIMD3<Float>, componentTag: Int32) {
        let c = grid.cellCoord(of: worldPos)
        var cell = grid[c]
        cell.density = min(1, cell.density + density)
        cell.tempK = max(cell.tempK, tempK)
        cell.velocity += velocity
        cell.r = color.x; cell.g = color.y; cell.b = color.z
        cell.componentTag = componentTag
        grid[c] = cell
    }
}

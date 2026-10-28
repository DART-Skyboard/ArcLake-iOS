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
            let buoyancy = max(0, (cell.tempK - 293) * 0.00004)
            cell.velocity += (gravity * (1 - buoyancy) ) * dt
        }
    }

    /// Backward semi-Lagrangian advection — the core of why this is
    /// "stable" at any dt. For each cell, trace a particle backward
    /// along the current velocity field by dt, and sample the
    /// previous field there (trilinear-interpolated).
    private func advectVelocity(dt: Float) {
        let coords = grid.activeCoords()
        var sampled: [(SIMD3<Int32>, SIMD3<Float>)] = []
        sampled.reserveCapacity(coords.count)
        for c in coords {
            let cell = grid[c]
            guard !cell.isSolid else { continue }
            let worldPos = grid.worldCenter(of: c)
            let backPos = worldPos - cell.velocity * dt
            let sample = grid.trilinearSample(at: backPos)
            sampled.append((c, sample.velocity))
        }
        for (c, v) in sampled {
            var cell = grid[c]
            cell.velocityPrev = cell.velocity
            cell.velocity = v
            grid[c] = cell
        }
    }

    /// Implicit diffusion via Gauss-Seidel relaxation. Implicit (rather
    /// than explicit forward diffusion) is what makes this stable for
    /// any diffusion rate × dt — an explicit version would need a tiny
    /// dt to not oscillate/blow up for viscous fluids.
    private func diffuseVelocity(dt: Float) {
        guard viscosity > 0 else { return }
        let a = dt * viscosity
        let coords = grid.activeCoords()
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

        // Subtract pressure gradient from velocity — result is divergence-free
        for c in coords {
            var cell = grid[c]
            guard !cell.isSolid else { continue }
            let pxPos = grid[c &+ SIMD3<Int32>(1,0,0)].pressure
            let pxNeg = grid[c &- SIMD3<Int32>(1,0,0)].pressure
            let pyPos = grid[c &+ SIMD3<Int32>(0,1,0)].pressure
            let pyNeg = grid[c &- SIMD3<Int32>(0,1,0)].pressure
            let pzPos = grid[c &+ SIMD3<Int32>(0,0,1)].pressure
            let pzNeg = grid[c &- SIMD3<Int32>(0,0,1)].pressure
            cell.velocity.x -= 0.5 * (pxPos - pxNeg) / h
            cell.velocity.y -= 0.5 * (pyPos - pyNeg) / h
            cell.velocity.z -= 0.5 * (pzPos - pzNeg) / h
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
        let coords = grid.activeCoords()
        var sampled: [(SIMD3<Int32>, Float, Float)] = []
        sampled.reserveCapacity(coords.count)
        for c in coords {
            let cell = grid[c]
            guard !cell.isSolid else { continue }
            let worldPos = grid.worldCenter(of: c)
            let backPos = worldPos - cell.velocity * dt
            let sample = grid.trilinearSample(at: backPos)
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
        let a = dt * thermalDiffusion
        let coords = grid.activeCoords()
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
                cell.tempK   = (cell.tempK + a * sumT) / (1 + a * count)
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
            // combustion event passes.
            cell.tempK += (293 - cell.tempK) * min(1, densityDissipation * 4 * dt)
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

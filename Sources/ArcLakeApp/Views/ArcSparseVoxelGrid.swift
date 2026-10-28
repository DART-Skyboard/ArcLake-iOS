import Foundation
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcSparseVoxelGrid — sparse voxel storage for Arc Edge CFD v3.0.
//
// Backs the Stam "Stable Fluids" solver (ArcStableFluidSolver.swift).
// Cells materialize lazily as fluid enters a region and are reclaimed
// once empty, so memory tracks active fluid volume rather than the
// full domain bounding box — important for large combustion-chamber
// / cavity-fill scenes on-device.
//
// Reference: Jos Stam, "Stable Fluids," SIGGRAPH 1999.
//   Grid-based velocity/scalar storage, semi-Lagrangian advection.
//   See ArcStableFluidSolver.swift for the solver itself.
//
// Integrated: Radical Deepscale LLC / DART Meadow — Arc Edge CFD v3.0
// ═══════════════════════════════════════════════════════════════════

/// One voxel's simulation state.
public struct ArcVoxelCell {
    public var velocity:      SIMD3<Float> = .zero
    public var velocityPrev:  SIMD3<Float> = .zero
    public var density:       Float = 0
    public var densityPrev:   Float = 0
    public var tempK:         Float = 293
    /// Pre-diffusion snapshot of tempK, taken at the start of each
    /// diffuseScalars sweep — mirrors densityPrev's role for temperature
    /// (see diffuseScalars in ArcStableFluidSolver.swift; fix for the
    /// stale-snapshot diffusion bug, v3.1).
    public var tempKPrev:     Float = 293
    public var pressure:      Float = 0      // scratch for projection solve
    public var divergence:    Float = 0      // scratch for projection solve
    public var isSolid:       Bool  = false  // mesh-collision boundary cell
    public var solidNormal:   SIMD3<Float> = .zero
    /// Index into ArcFluidEngine.componentSpecs this cell belongs to, or -1.
    public var componentTag:  Int32 = -1
    /// Particle color carried through for visual seeding (combustion fuel/ox tint).
    public var r: Float = 0.7, g: Float = 0.7, b: Float = 1.0

    /// True when this cell has no fluid AND is not a solid boundary cell.
    /// isSolid must never be considered "empty" — a zero-density/velocity
    /// wall cell is still a wall, and must never be reclaimed by the
    /// density/velocity emptiness check (v3.1 fix: wall cells were being
    /// evicted within ~1 tick because every Gauss-Seidel write bumped the
    /// empty streak — see ArcSparseVoxelGrid.advanceFrame).
    public var isEmpty: Bool {
        guard !isSolid else { return false }
        return density < 1e-4 && simd_length_squared(velocity) < 1e-6
    }
}

/// Sparse voxel grid keyed by Morton-coded integer cell coordinates.
/// Dictionary-backed (not a true octree) for v1 — correctness and
/// simplicity first; octree LOD is a documented follow-on, not a
/// blocker (see docs/StableFluidsArchitecture.md).
public final class ArcSparseVoxelGrid {

    /// World-space size of one voxel cell, in scene units.
    public var cellSize: Float

    /// World-space domain bounds — fit to scene model bounding box.
    public private(set) var domainMin: SIMD3<Float> = .zero
    public private(set) var domainMax: SIMD3<Float> = .zero

    private var cells: [Int64: ArcVoxelCell] = [:]

    /// Frames an empty cell must stay empty before being reclaimed —
    /// avoids thrashing allocate/free at a boundary that's oscillating
    /// right at the epsilon. Advanced exactly once per simulation tick
    /// by `advanceFrame()` — NOT per subscript write (v3.1 fix: the old
    /// code bumped this on every write, and the solver writes each
    /// active cell many times per tick via Gauss-Seidel relaxation, so
    /// a cell could hit the reclaim threshold within its first tick).
    private let reclaimAfterFrames = 8
    private var emptyStreak: [Int64: Int] = [:]

    /// Supplementary solid-boundary lookup at a finer virtual cell size
    /// than the main simulation grid — see `markFineSolid`/`isFineSolid`.
    /// This is the adaptive-collision-resolution piece (v3.1, item 5 of
    /// the solver-correctness pass): the FLUID SIMULATION grid stays at
    /// its existing fixed `cellSize` (no change to ArcVoxelCell's
    /// physics field layout, no perf regression to the bulk Vstep/Sstep
    /// solve), but the WALL BOUNDARY the fluid can't cross is tracked at
    /// a second, smaller resolution exactly where mesh triangle density
    /// is high (joints, nozzle throats, pipe-to-tank interfaces) — see
    /// docs/StableFluidsArchitecture.md "v3.1: adaptive collision
    /// resolution" for the full rationale. Consulted only by the
    /// wall-clipping walk in advectVelocity/advectScalars and by
    /// project()'s boundary handling — never by the bulk Gauss-Seidel
    /// stencils, which keep using `isSolid` at the normal resolution.
    private var fineSolidCells: Set<Int64> = []
    /// Fine lookup is at half the normal cellSize — chosen as the
    /// simplest step that meaningfully tightens narrow-passage coverage
    /// without a second full grid resolution concept.
    public let fineSubdivision: Int32 = 2

    public init(cellSize: Float = 2.0) {
        self.cellSize = cellSize
    }

    // MARK: — Domain

    /// Fit the voxel domain to a world-space bounding box, choosing a
    /// cell size so the longest axis spans roughly `targetResolution`
    /// cells. Mirrors ArcFluidEngine.fitDomainToScene's padding logic.
    public func fitDomain(min lo: SIMD3<Float>, max hi: SIMD3<Float>,
                           targetResolution: Int = 48) {
        guard hi.x > lo.x else { return }

        // v3.1 fix (item 7): cell keys are computed from world position
        // via the CURRENT domainMin/cellSize at lookup time (see
        // cellCoord/key above) — they are NOT absolute, domain-independent
        // identifiers. If this grid already holds cells and we change
        // domainMin/cellSize without remapping, every existing cell's
        // key now resolves to the WRONG world position (a later lookup
        // for the same world point computes a different key than the
        // one under which the cell's contents are stored). Snapshot the
        // old mapping, compute the new one, then re-key every existing
        // cell (main + fine solid) under the new mapping before
        // committing it, so expansion-after-fill is correct.
        let hadCells = !cells.isEmpty || !fineSolidCells.isEmpty
        let oldDomainMin = domainMin
        let oldCellSize = cellSize
        let oldFineSolidWorld: [SIMD3<Float>] = hadCells
            ? fineSolidCells.map { worldCenterOfFineKey($0, domainMin: oldDomainMin, cellSize: oldCellSize) }
            : []
        let oldCellsSnapshot = cells  // [key: cell], keys are old-mapping-relative

        let pad: Float = 1.5
        let center = (lo + hi) * 0.5
        let halfSize = (hi - lo) * 0.5 * pad
        domainMin = center - halfSize
        domainMax = center + halfSize
        let longest = max(domainMax.x - domainMin.x,
                       max(domainMax.y - domainMin.y, domainMax.z - domainMin.z))
        cellSize = max(0.05, longest / Float(max(8, targetResolution)))

        guard hadCells else { return }

        // Remap main cells: decode each old key back to its world center
        // under the OLD mapping, then re-insert under the NEW mapping's
        // key for that same world position.
        if !oldCellsSnapshot.isEmpty {
            let bias: Int64 = 1 << 20
            var remapped: [Int64: ArcVoxelCell] = [:]
            remapped.reserveCapacity(oldCellsSnapshot.count)
            for (oldKey, cell) in oldCellsSnapshot {
                let z = oldKey & 0x1FFFFF
                let y = (oldKey >> 21) & 0x1FFFFF
                let x = (oldKey >> 42) & 0x1FFFFF
                let oldCoord = SIMD3<Int32>(Int32(x - bias), Int32(y - bias), Int32(z - bias))
                let worldPos = oldDomainMin + (SIMD3<Float>(Float(oldCoord.x), Float(oldCoord.y), Float(oldCoord.z)) + 0.5) * oldCellSize
                let newCoord = cellCoord(of: worldPos)
                remapped[key(newCoord)] = cell
            }
            cells = remapped
            // Empty streaks don't carry meaningful identity across a
            // remap (reclaim timing resets cleanly) — drop them rather
            // than try to remap into possibly-colliding new keys.
            emptyStreak.removeAll(keepingCapacity: true)
        }

        // Remap fine solid-boundary cells the same way, under the fine
        // (half-size) virtual resolution.
        if !oldFineSolidWorld.isEmpty {
            var remappedFine: Set<Int64> = []
            remappedFine.reserveCapacity(oldFineSolidWorld.count)
            for worldPos in oldFineSolidWorld {
                remappedFine.insert(fineKey(of: worldPos))
            }
            fineSolidCells = remappedFine
        }
    }

    // MARK: — Coordinate conversion

    @inline(__always) public func cellCoord(of worldPos: SIMD3<Float>) -> SIMD3<Int32> {
        let rel = (worldPos - domainMin) / cellSize
        return SIMD3<Int32>(Int32(floor(rel.x)), Int32(floor(rel.y)), Int32(floor(rel.z)))
    }

    @inline(__always) public func worldCenter(of c: SIMD3<Int32>) -> SIMD3<Float> {
        domainMin + (SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)) + 0.5) * cellSize
    }

    /// Morton-ish interleave key. Not a true Z-order curve (keeps the
    /// shift-by-21-bits math simple for signed coords via a bias),
    /// but gives a stable, collision-free dictionary key for the
    /// cell coordinate range this engine operates over (±1,048,575).
    @inline(__always) private func key(_ c: SIMD3<Int32>) -> Int64 {
        let bias: Int64 = 1 << 20
        let x = Int64(c.x) + bias, y = Int64(c.y) + bias, z = Int64(c.z) + bias
        precondition(x >= 0 && y >= 0 && z >= 0 && x < (1<<21) && y < (1<<21) && z < (1<<21),
                     "ArcSparseVoxelGrid: cell coord out of key range")
        return (x << 42) | (y << 21) | z
    }

    /// Fine (sub-voxel) cell coordinate at `fineSubdivision`× the normal
    /// resolution — used only by the supplementary solid-boundary lookup.
    @inline(__always) public func fineCellCoord(of worldPos: SIMD3<Float>) -> SIMD3<Int32> {
        let fineSize = cellSize / Float(fineSubdivision)
        let rel = (worldPos - domainMin) / fineSize
        return SIMD3<Int32>(Int32(floor(rel.x)), Int32(floor(rel.y)), Int32(floor(rel.z)))
    }

    @inline(__always) private func fineKey(of worldPos: SIMD3<Float>) -> Int64 {
        key(fineCellCoord(of: worldPos))  // same packed-key scheme, different coordinate space
    }

    /// Decode a fine key back to its world-space center under an
    /// arbitrary (domainMin, cellSize) mapping — used by fitDomain's
    /// remap when the grid's own domainMin/cellSize have already
    /// changed and we need the OLD mapping to recover world position.
    private func worldCenterOfFineKey(_ k: Int64, domainMin oldDomainMin: SIMD3<Float>, cellSize oldCellSize: Float) -> SIMD3<Float> {
        let bias: Int64 = 1 << 20
        let z = k & 0x1FFFFF
        let y = (k >> 21) & 0x1FFFFF
        let x = (k >> 42) & 0x1FFFFF
        let c = SIMD3<Int32>(Int32(x - bias), Int32(y - bias), Int32(z - bias))
        let fineSize = oldCellSize / Float(fineSubdivision)
        return oldDomainMin + (SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)) + 0.5) * fineSize
    }

    /// Mark the fine sub-cell containing `worldPos` as a solid boundary
    /// cell. Called from syncMeshCollisionToGrid when a region is
    /// flagged as a tight passage (high triangle density per cell).
    public func markFineSolid(at worldPos: SIMD3<Float>) {
        fineSolidCells.insert(fineKey(of: worldPos))
    }

    /// True if `worldPos` falls inside a fine-resolution solid boundary
    /// cell. Does NOT imply the containing coarse cell is solid (coarse
    /// isSolid is checked separately) — this is purely the finer wall
    /// test used by the advection wall-clipping walk and projection's
    /// boundary handling.
    public func isFineSolid(at worldPos: SIMD3<Float>) -> Bool {
        fineSolidCells.contains(fineKey(of: worldPos))
    }

    public var fineSolidCellCount: Int { fineSolidCells.count }

    // MARK: — Access

    /// Read a cell, or an empty default if unmaterialized.
    ///
    /// v3.1 fix (item 2): the setter used to advance `emptyStreak` on
    /// EVERY write, but the solver writes each active cell many times
    /// per tick (once per Gauss-Seidel relaxation iteration in
    /// diffuse/project, etc.) — so a genuinely-empty cell could reach
    /// `reclaimAfterFrames` within its very first tick, making reclaim
    /// timing effectively unpredictable regardless of the isSolid fix.
    /// The streak is now advanced ONLY by `advanceFrame()`, called
    /// exactly once per `stepGrid()` tick. The setter's job is just to
    /// store the value and reset the streak to 0 whenever a write gives
    /// the cell nonzero density/velocity or isSolid (isEmpty already
    /// accounts for isSolid, so this condition is simply "not empty").
    @inline(__always) public subscript(c: SIMD3<Int32>) -> ArcVoxelCell {
        get { cells[key(c)] ?? ArcVoxelCell() }
        set {
            let k = key(c)
            if newValue.isEmpty {
                // Leave any existing streak as-is; advanceFrame() owns
                // incrementing it. If this cell was never tracked
                // (freshly materialized empty halo cell, see
                // advectVelocity/advectScalars' 6-neighborhood
                // pre-materialization), start its streak at 0 so it
                // isn't immediately eligible for reclaim.
                if emptyStreak[k] == nil { emptyStreak[k] = 0 }
                cells[k] = newValue
                if (emptyStreak[k] ?? 0) >= reclaimAfterFrames {
                    cells.removeValue(forKey: k)
                    emptyStreak.removeValue(forKey: k)
                }
            } else {
                emptyStreak[k] = 0
                cells[k] = newValue
            }
        }
    }

    /// Advance the empty-streak counter for every currently-tracked
    /// cell once. Call exactly once per simulation tick (ArcFluidEngine.
    /// stepGrid), never per Gauss-Seidel iteration or per write — see
    /// the subscript setter's doc comment. Reclaims any cell that both
    /// is still empty and has now reached `reclaimAfterFrames`.
    public func advanceFrame() {
        guard !cells.isEmpty else { return }
        var toRemove: [Int64] = []
        for k in cells.keys {
            guard let cell = cells[k], cell.isEmpty else { continue }
            let streak = (emptyStreak[k] ?? 0) + 1
            if streak >= reclaimAfterFrames {
                toRemove.append(k)
            } else {
                emptyStreak[k] = streak
            }
        }
        for k in toRemove {
            cells.removeValue(forKey: k)
            emptyStreak.removeValue(forKey: k)
        }
    }

    /// Materialize (or fetch) a cell for writing, bypassing the reclaim
    /// streak reset — used by the solver's inner loops where a cell is
    /// about to be written every substep. Also used to pre-materialize
    /// the 6-neighborhood of active cells before advection so fluid can
    /// flow into not-yet-materialized neighbors; a cell newly created
    /// here starts with emptyStreak = 0 (fresh), not immediately
    /// eligible for reclaim.
    @inline(__always) public func ensure(_ c: SIMD3<Int32>) -> ArcVoxelCell {
        let k = key(c)
        if let existing = cells[k] { return existing }
        let fresh = ArcVoxelCell()
        cells[k] = fresh
        emptyStreak[k] = 0
        return fresh
    }

    public var activeCellCount: Int { cells.count }

    /// All materialized cell coordinates — the solver's working set.
    /// Decoded back from the packed key each call; cache the result
    /// per-frame rather than calling this in an inner loop.
    public func activeCoords() -> [SIMD3<Int32>] {
        let bias: Int64 = 1 << 20
        return cells.keys.map { k in
            let z = k & 0x1FFFFF
            let y = (k >> 21) & 0x1FFFFF
            let x = (k >> 42) & 0x1FFFFF
            return SIMD3<Int32>(Int32(x - bias), Int32(y - bias), Int32(z - bias))
        }
    }

    public func forEachActive(_ body: (SIMD3<Int32>, inout ArcVoxelCell) -> Void) {
        for c in activeCoords() {
            var cell = self[c]
            body(c, &cell)
            self[c] = cell
        }
    }

    /// 6-connected face neighbors (±X, ±Y, ±Z) — the stencil the
    /// solver's diffuse/project Gauss-Seidel relaxation uses.
    @inline(__always) public func neighbors6(of c: SIMD3<Int32>) -> [SIMD3<Int32>] {
        [
            c &+ SIMD3<Int32>(1,0,0), c &- SIMD3<Int32>(1,0,0),
            c &+ SIMD3<Int32>(0,1,0), c &- SIMD3<Int32>(0,1,0),
            c &+ SIMD3<Int32>(0,0,1), c &- SIMD3<Int32>(0,0,1),
        ]
    }

    /// Trilinear sample at an arbitrary world-space point — the core
    /// operation semi-Lagrangian backward advection needs, since a
    /// traced-back position almost never lands exactly on a cell
    /// center.
    public func trilinearSample(at worldPos: SIMD3<Float>) -> ArcVoxelCell {
        let rel = (worldPos - domainMin) / cellSize - 0.5
        let base = SIMD3<Int32>(Int32(floor(rel.x)), Int32(floor(rel.y)), Int32(floor(rel.z)))
        let f = SIMD3<Float>(rel.x - floor(rel.x), rel.y - floor(rel.y), rel.z - floor(rel.z))

        var result = ArcVoxelCell()
        var totalW: Float = 0
        for dz in 0...1 { for dy in 0...1 { for dx in 0...1 {
            let off = SIMD3<Int32>(Int32(dx), Int32(dy), Int32(dz))
            let c = base &+ off
            let wx: Float = dx == 1 ? f.x : (1-f.x)
            let wy: Float = dy == 1 ? f.y : (1-f.y)
            let wz: Float = dz == 1 ? f.z : (1-f.z)
            let w = wx*wy*wz
            guard w > 0 else { continue }
            let cell = self[c]
            result.velocity    += cell.velocity * w
            result.density     += cell.density * w
            result.tempK       += (cell.tempK - 293) * w  // accumulate delta, add base back below
            totalW += w
        }}}
        if totalW > 1e-6 {
            result.tempK = 293 + result.tempK  // re-add base after weighted delta sum
        } else {
            result.tempK = 293
        }
        return result
    }

    /// Clear scratch fields (pressure/divergence) without touching
    /// velocity/density — called once per projection solve.
    public func resetProjectionScratch() {
        forEachActive { _, cell in
            cell.pressure = 0
            cell.divergence = 0
        }
    }

    public func removeAll() {
        cells.removeAll(keepingCapacity: true)
        emptyStreak.removeAll(keepingCapacity: true)
        fineSolidCells.removeAll(keepingCapacity: true)
    }
}

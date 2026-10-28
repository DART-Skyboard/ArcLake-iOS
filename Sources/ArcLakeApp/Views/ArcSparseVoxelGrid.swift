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
    public var pressure:      Float = 0      // scratch for projection solve
    public var divergence:    Float = 0      // scratch for projection solve
    public var isSolid:       Bool  = false  // mesh-collision boundary cell
    public var solidNormal:   SIMD3<Float> = .zero
    /// Index into ArcFluidEngine.componentSpecs this cell belongs to, or -1.
    public var componentTag:  Int32 = -1
    /// Particle color carried through for visual seeding (combustion fuel/ox tint).
    public var r: Float = 0.7, g: Float = 0.7, b: Float = 1.0

    public var isEmpty: Bool {
        density < 1e-4 && simd_length_squared(velocity) < 1e-6
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
    /// right at the epsilon.
    private let reclaimAfterFrames = 8
    private var emptyStreak: [Int64: Int] = [:]

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
        let pad: Float = 1.5
        let center = (lo + hi) * 0.5
        let halfSize = (hi - lo) * 0.5 * pad
        domainMin = center - halfSize
        domainMax = center + halfSize
        let longest = max(domainMax.x - domainMin.x,
                       max(domainMax.y - domainMin.y, domainMax.z - domainMin.z))
        cellSize = max(0.05, longest / Float(max(8, targetResolution)))
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

    // MARK: — Access

    /// Read a cell, or an empty default if unmaterialized.
    @inline(__always) public subscript(c: SIMD3<Int32>) -> ArcVoxelCell {
        get { cells[key(c)] ?? ArcVoxelCell() }
        set {
            let k = key(c)
            if newValue.isEmpty {
                let streak = (emptyStreak[k] ?? 0) + 1
                if streak >= reclaimAfterFrames {
                    cells.removeValue(forKey: k)
                    emptyStreak.removeValue(forKey: k)
                    return
                }
                emptyStreak[k] = streak
                cells[k] = newValue
            } else {
                emptyStreak.removeValue(forKey: k)
                cells[k] = newValue
            }
        }
    }

    /// Materialize (or fetch) a cell for writing, bypassing the reclaim
    /// streak reset — used by the solver's inner loops where a cell is
    /// about to be written every substep.
    @inline(__always) public func ensure(_ c: SIMD3<Int32>) -> ArcVoxelCell {
        cells[key(c)] ?? ArcVoxelCell()
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
    }
}

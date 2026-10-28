# Arc Edge CFD v3.0 — Sparse Voxel Stable Fluids Architecture

Status: v3.0 merged and live (build 390/1.5.9). This doc now also covers
the v3.1 correctness-fix pass (CodeRabbit findings on PR #2 + the
adaptive-collision-resolution addition) — see "v3.1: fixes and adaptive
collision resolution" below.

Build target: 1.5.9+.

## Why

`ArcFluidEngine` (Arc Edge CFD v2.0) is a world-space SPH solver — Müller/Charypar/Gross
2003 kernels, spatial hash, explicit Euler integration, with a hard `VMAX` velocity
clamp as the only stability mechanism. That clamp is the tell: explicit integration
has no stability guarantee at the frame times a phone actually delivers, so motion
is being contained rather than correctly solved. Visual fluid motion in the 3D
viewport reads as particle spray rather than continuous fluid.

Jos Stam's "Stable Fluids" (SIGGRAPH 1999) is unconditionally stable at any time
step because advection is solved by backward semi-Lagrangian tracing rather than
forward integration, and incompressibility is enforced by an explicit
Helmholtz-Hodge projection rather than approximated through pairwise pressure forces.

This doc scopes a full replacement: SPH is removed, not wrapped. The engine's grid
is sparse-voxel (octree), not dense, to stay memory/perf-reasonable on-device for
large cavity/combustion-chamber domains and to leave room for level-of-detail later
(coarser cells far from inlet/outlet/combustion zones).

## Hard compatibility contract

`ArcCFDComponentPanel.swift` and `ArcFluidView.swift`'s Measure tab read **only**:

- `eng.isRunning: Bool`
- `eng.measure: ArcFluidMeasure` (particleCount, avgTempK, avgSpeed, reynoldsNum,
  regime, maxPressurePa, totalKE, inletFlow, outletFlow)
- `eng.componentSpecs: [ArcComponentSpec]` (currentTempK, currentPressureMPa,
  stressLevel, fillLevel, alloy, isInlet/isOutlet, particleCapacity, volumeM3)
- `eng.selectedComponentName`, `eng.selectComponent(_:in:)` (used by `ArcSceneView`
  for glow-on-select only — no simulation coupling)
- `eng.scanComponentSpecsPublic(_:)`, `eng.start(in:elementSymbols:envTempK:envPressurePa:)`,
  `eng.stop()`, `eng.setScene(_:)`

None of these names, types, or field names change. The UI layer (`ArcCFDComponentPanel`,
`ArcFluidView`, `ArcComponentConfigView`, `ArcMeshSelectorView`) needs **zero edits**.
`ArcFluidMeasure.particleCount` is repurposed to mean "voxels with non-trivial density"
rather than literal SPH particles — still a meaningful, monotonic-with-activity number
for the same UI.

`ArcWindTunnel.swift` is explicitly out of scope. It's a separate raytraced external
aero-analysis system (Cp/Mach/boundary-layer), not a cavity solver, and shares only
the thermal colormap convention. Not touched by this work.

## New files

1. **`ArcSparseVoxelGrid.swift`** — sparse voxel storage + domain management
   - Cell = `(velocity: SIMD3<Float>, velocityPrev: SIMD3<Float>, density: Float,
     densityPrev: Float, tempK: Float, pressure: Float, divergence: Float,
     componentTag: Int32)`
   - Backing store: `[Int64: VoxelCell]` dictionary keyed by Morton-coded (x,y,z) —
     simplest correct sparse structure; octree LOD is a follow-on, not blocking v1.
   - `cellSize: Float` derived from scene bounding box / target resolution (replaces
     `fitDomainToScene`'s dense `W/H/D`).
   - `neighbors6(of:)`, `trilinearSample(at: SIMD3<Float>) -> VoxelCell` (for
     semi-Lagrangian backward trace landing between cell centers).
   - `insert`/`ensure(at:)` — cells materialize lazily as fluid enters them, freed
     when density + velocity drop below epsilon for N frames (keeps sparsity real,
     not just nominal).

2. **`ArcStableFluidSolver.swift`** — Stam's algorithm against the sparse grid
   - `Vstep`: addForce (gravity, buoyancy from `componentTag` pressure/thermal state)
     → `advectSemiLagrangian` (backward trace + trilinear sample, unconditionally
     stable at any `dt`) → `diffuseImplicit` (Gauss-Seidel relaxation, 20 iterations,
     sparse-safe since it only touches materialized + boundary-adjacent cells — no
     FFT, which requires a periodic dense domain we don't have) → `project`
     (Helmholtz-Hodge: solve Poisson for pressure via Gauss-Seidel, subtract
     gradient — enforces ∇·u=0, replaces `VMAX` clamping entirely).
   - `Sstep`: same shape for density/temperature scalar transport (replaces the
     ad hoc `pts[i].tempK = envTempK + pthermal` heuristic with real advected
     temperature).
   - Mesh collision: triangle-vs-voxel-face test at grid build time marks boundary
     cells solid; solver applies free-slip/no-slip boundary conditions on those
     faces instead of SPH's per-particle reflect-and-push.

3. **`ArcFluidEngine.swift`** (modified, not replaced) — becomes the orchestration
   + compatibility layer:
   - `pts: [ArcParticle]` stays, now purely visual: seeded/reseeded from the grid's
     velocity+density field each frame for the SceneKit point-cloud render
     (`uploadParticleCloud` unchanged) and for combustion-reaction color logic
     (`applyCombustionReaction` unchanged — it already reads `pts[i].r/g/b` and
     chamber bounding box, which still works once particles are grid-sampled).
   - `stepSPH()` renamed internally to `stepGrid()`, same call signature/timing
     (`Task.detached`, 16.6ms cadence) so nothing above it changes.
   - `scanComponentSpecs`/`autoFillCombustionDemo`/`fillComponentCavity` unchanged
     in interface; cavity fill now seeds grid cells with density+temp+pressure
     instead of spawning raw SPH particles directly.
   - `updateComponentMeasurements`, `updateThermalColormap` unchanged interfaces —
     now sample grid cells near each component instead of iterating `pts` directly
     (cheaper: O(components × local cells) instead of O(components × all particles)).

4. **`ArcStableFluids.metal`** + Metal pipeline glue in `ArcStableFluidSolver.swift`
   — GPU compute kernel ports of advect/diffuse/project over a flattened active-cell
   buffer (built CPU-side each frame from the sparse dictionary, dispatched as one
   `MTLComputePipelineState` per step). CPU path stays as the correctness reference
   and the fallback for devices/simulators without compute support; built and
   validated after the CPU version is confirmed correct in CI/TestFlight.

## Mantis Nav

Verified, no simulation-side change needed. `ArcMantisNav`/`MantisNavigationView`
never call into `ArcFluidEngine`, and all three gesture guards in `ArcSceneView`
(`handleOrbit`/`handlePan`/`handleDolly`) gate purely on
`labVM.mantis.isActive`/`cameraMode`/`mantisTabIndex == activeTabIndex` — none of
them touch fluid-engine state. The only coupling is the tap-to-select handler
(`componentSpecs`/`selectComponent`), both preserved exactly by this migration.

Originally planned a "skip grid stepping when the fluid tab isn't visible" perf
courtesy — dropped after checking `ArcLabViewModel`: each scene tab tracks its own
`tabStates[i].isCFDActive`, and `ArcFluidEngine.shared` is a singleton, which means
running CFD on one tab while viewing/using Mantis Nav on another tab is already a
supported, intentional use case. Gating grid compute on "is the fluid view the
visible tab" would silently break that. Left alone.

## Credits (→ ArcSettingsView "About / Open Source")

Correction from an earlier draft of this doc: the "About / Open Source" section in
`ArcSettingsView.swift` already existed and was already populated (it was only the
file's header *comment* that still called it a to-do) — including an existing
MetalANGLE credit. Added to the existing section rather than building a new one:

- Jos Stam, "Stable Fluids," SIGGRAPH 1999 — semi-Lagrangian advection, implicit
  diffusion, Helmholtz-Hodge projection (new, this pass)
- Müller, Charypar & Gross, SCA 2003 — SPH kernels (existing credit, reworded to
  note it now informs the particle visual layer + buoyancy coupling, not the core
  solver)
- Ihmsen et al. 2012, CGI — spray/foam reference (existing credit, kept)
- MetalANGLE [MIT] — already credited in Settings as GL-translation research; noted
  there that it was considered for the v3.0 Metal compute pass and not adopted
  (nothing legacy-GL to translate, this project targets Metal natively), rather
  than silently leaving the existing credit unexplained for this use case.

## v3.1: fixes and adaptive collision resolution

A round of correctness bugs found by CodeRabbit's automated review on
the merged v3.0 PR (#2), verified against the actual code, fixed in a
single follow-up branch (`fix/solver-correctness-batch`):

1. **Stale-snapshot diffusion.** `diffuseVelocity`/`diffuseScalars` were
   reading `velocityPrev`/`densityPrev`/(and `tempK`, which had no prior
   field at all) as the Gauss-Seidel source term, but those were never
   refreshed after advection ran that tick — diffusion kept relaxing
   toward PRE-advection data every sweep. Fixed by snapshotting the
   just-advected field into `velocityPrev`/`densityPrev`/`tempKPrev`
   (new field on `ArcVoxelCell`) at the start of each diffuse call.
2. **Wall cells reclaimed as empty, and reclaim timing was
   per-write.** `ArcVoxelCell.isEmpty` now returns `false` whenever
   `isSolid` is true. Separately, the empty-streak counter used to
   advance on every subscript write — and the solver writes each active
   cell many times per tick (once per Gauss-Seidel iteration) — so a
   cell could hit the `reclaimAfterFrames` threshold within one tick
   regardless of the isSolid fix. `ArcSparseVoxelGrid.advanceFrame()` now
   owns advancing the streak, called exactly once per `stepGrid()` tick;
   the subscript setter only stores/resets, never increments.
3. **Advection samples through walls.** `trilinearSample` has no wall
   awareness (by design — other callers want the raw interpolation), so
   `advectVelocity`/`advectScalars` now walk a fixed number of steps from
   the cell's world position toward its backward-traced sample position
   and clip at the first solid cell (coarse `isSolid` or the new fine
   lookup, see below) encountered, before calling `trilinearSample`.
4. **Mesh-collision coverage gap (the actual root cause of visible
   fluid-through-walls).** `syncMeshCollisionToGrid` used to sample only
   7 points per triangle (corners + centroid + edge midpoints) and mark
   one cell per sample — a triangle spanning multiple voxel widths left
   most of the cells it crossed unmarked. It now rasterizes each
   triangle into every cell its bounding box overlaps, keeping only
   cells that pass a real triangle-vs-AABB separating-axis test
   (Akenine-Möller), capped at `maxCellsPerTriangle` (400) per triangle
   with a skip+warning for degenerate huge triangles.
6. **Combustion heat/exhaust discarded on reseed.** `applyCombustionReaction`
   used to write only to `pts[]`, which `reseedParticlesFromGrid()`
   rebuilds from the grid every tick — the writes were a dead end. It now
   also writes heat + downward exhaust velocity directly into the grid
   cells under each reacting particle, which the *next* tick's
   `velocityStep`/`scalarStep` then actually sees.
7. **Domain remap on cavity expansion.** Cell keys are computed from
   world position via the grid's CURRENT `domainMin`/`cellSize` at
   lookup time — not fixed at insert time. `fitDomain` expanding the
   domain on an already-populated grid (as `fillComponentCavity` can
   trigger) used to silently orphan every existing cell's contents at
   the wrong world position. `fitDomain` now detects a non-empty grid
   and remaps every existing cell (and fine solid sub-cell) to the new
   mapping before returning.
8. **`fitVoxelDomainToScene` ignored non-identity node transforms.** It
   merged each node's LOCAL `boundingBox` directly into the domain
   bounds; now transforms all 8 corners of each node's local bounding
   box through `node.worldTransform` first, matching (and extending —
   8 corners vs. 2) the existing world-transform pattern used elsewhere
   in the file.
9. **Outlet drain only touched one cell.** The stream-preset outlet
   drain read/halved a single cell at the outlet zone's exact center and
   didn't check `isSolid`, so neighboring fluid within `outletRadius`
   wasn't drained or counted, and a stale solid cell could falsely count
   as draining. Ported the pre-rebuild SPH code's radius-based approach:
   every non-solid cell whose world center falls within `outletRadius`
   of the outlet zone is now drained and counted. `outletRadius`/
   `outletZone` are plain world-space scene units — no `SCALE` factor
   reintroduced (it's intentionally gone from the Swift sources).
10. **Smaller items**, also fixed: projection's pressure-gradient step now
    excludes solid neighbors the same way the Poisson solve does (mirrors
    the opposite-side value instead of substituting pressure=0); the
    implicit diffusion coefficient now includes the `1/cellSize²` term
    the classic discretization calls for; the Measure panel's "Particles"
    row is relabeled "Active Voxels" (the `eng.measure.particleCount`
    field name is unchanged, per the compatibility contract);
    `advectVelocity`/`advectScalars` now pre-materialize the 6-neighborhood
    of active cells before sampling so fluid can flow into not-yet-active
    neighbors; `uploadParticleCloud()`'s zero-point guard now clears
    `cloudNode.geometry` instead of leaving the last nonempty cloud
    visible; buoyancy and the ambient-relaxation term in `dissipateDensity`
    now use a configurable `solver.ambientTempK` (set from `envTempK`)
    instead of a hardcoded `293`.

### Adaptive collision resolution (item 5)

The user's explicit ask, folded into the item-4 mesh-sync rewrite rather
than a separate pass: joints and narrow passages (pipe-to-tank
interfaces, nozzle throats) need finer collision resolution than the
bulk of the domain, without paying for a finer *simulation* grid
everywhere.

**Approach chosen:** a second, smaller-resolution lookup for solid
boundary only — not a full octree, which stays out of scope per the
"explicitly not done" section below; a genuinely adaptive
simulation-cell-size approach would need `ArcVoxelCell`'s layout and the
Gauss-Seidel stencils to vary resolution, which is a much larger change
than this pass's bar (compile+archive correctness, not a redesign).

- `ArcSparseVoxelGrid` gained a supplementary `fineSolidCells: Set<Int64>`
  keyed at `fineSubdivision` (2×) the normal `cellSize` — i.e. half-size
  virtual sub-cells — plus `markFineSolid(at:)` / `isFineSolid(at:)`.
- During the triangle rasterization pass (item 4), `syncMeshCollisionToGrid`
  counts how many triangles overlap each coarse cell. A cell crossing
  `tightPassageTriangleThreshold` (6) triangles is flagged a tight
  passage — multiple mesh surfaces converging inside one voxel, which is
  exactly the joint/throat case. Its fine sub-cells are then also marked
  solid via `markFineSolidSubcells`.
- The fine lookup is consulted ONLY by the two places fluid could
  otherwise leak through a sub-voxel gap: the wall-clipping walk in
  `advectVelocity`/`advectScalars` (item 3) and `project()`'s boundary
  handling (zeroing velocity in a fine-solid cell rather than trusting a
  possibly-spurious pressure gradient there). The bulk Gauss-Seidel
  stencils in diffuse/project keep using coarse `isSolid` exclusively —
  so there is no perf regression to the main solve, and `ArcVoxelCell`'s
  physics field layout is unchanged.
- Net effect: the FLUID SIMULATION grid and the WALL BOUNDARY the fluid
  can't cross are now two different resolutions by design. This keeps
  cost bounded (the fine lookup only grows where triangle density is
  genuinely high) while tightening exactly the crevices that were
  letting fluid leak through narrow collision geometry.
- `fitDomain`'s remap (item 7) carries `fineSolidCells` through a domain
  expansion the same way it carries the main `cells` dictionary.

## Explicitly not done in this pass

- `ArcWindTunnel.swift` — untouched, separate system.
- Full octree LOD (coarsening distant cells) — dictionary-keyed sparse storage only
  for v1; octree is a follow-on once the solver is proven correct.
- `ArcEdgeMath.swift` (DOC/Sigma-Meridian spline positioning) is not re-derived into
  the voxel math — it's scene-decoration/arc-layout math, not a fluid coordinate
  system, and nothing here requires changing it.

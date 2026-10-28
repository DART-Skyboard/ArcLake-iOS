# Arc Edge CFD v3.0 — Sparse Voxel Stable Fluids Architecture

Status: design doc, pre-implementation. Build target: 1.5.9+.

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

## Explicitly not done in this pass

- `ArcWindTunnel.swift` — untouched, separate system.
- Full octree LOD (coarsening distant cells) — dictionary-keyed sparse storage only
  for v1; octree is a follow-on once the solver is proven correct.
- `ArcEdgeMath.swift` (DOC/Sigma-Meridian spline positioning) is not re-derived into
  the voxel math — it's scene-decoration/arc-layout math, not a fluid coordinate
  system, and nothing here requires changing it.

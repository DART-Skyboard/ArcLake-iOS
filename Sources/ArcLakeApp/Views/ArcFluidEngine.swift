import Foundation
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcFluidEngine — Arc Edge CFD: mesh-conformal sparse-voxel fluid
// dynamics (Stable Fluids).
//
// v3.0: the simulation core is now ArcStableFluidSolver running on
// ArcSparseVoxelGrid (see those files) — unconditionally stable
// semi-Lagrangian advection + Helmholtz-Hodge projection, replacing
// v2's explicit-Euler SPH step and its VMAX clamp band-aid.
// `pts`/ArcParticle remain as a thin VISUAL layer only: each frame
// they're reseeded from the grid for the SceneKit point-cloud render
// and combustion color logic. All public properties/methods below
// (measure, componentSpecs, start/stop/setScene, selectComponent...)
// are unchanged so ArcCFDComponentPanel, ArcFluidView,
// ArcComponentConfigView, and ArcMeshSelectorView need no edits.
//
// Physics references:
//   Jos Stam — "Stable Fluids," SIGGRAPH 1999 (grid solver, v3.0)
//   Müller, Charypar & Gross — SCA 2003 (SPH kernels, v2.0 — kept for
//   buoyancy/density-coupling constants and the particle visual layer)
//   https://matthias-research.github.io/pages/publications/sca03.pdf
//   Sebastian Lague — Fluid-Sim (MIT)
//   https://github.com/SebLague/Fluid-Sim
//   dartsolarpunk/Fluid-Sim · dartsolarpunk/fluid
//   https://sph-tutorial.physics-simulation.org/pdf/SPH_Tutorial.pdf
//   Ihmsen et al. 2012 — Spray Foam Bubbles (CGI)
//   https://cg.informatik.uni-freiburg.de/publications/2012_CGI_sprayFoamBubbles.pdf
//
//  Integrated: Radical Deepscale LLC / DART Meadow — Arc Edge CFD v3.0
// ═══════════════════════════════════════════════════════════════════

// MARK: — Fluid mode
// Particle visual rendering mode
public enum ArcParticleVisual: String, CaseIterable, Identifiable {
    case points    = "Points"    // fast dot particles
    case spheres   = "Spheres"   // larger spheres, metaball-like blend
    case arcWave   = "Arc Wave"  // arc traces that react to physics
    public var id: String { rawValue }
    var icon: String {
        switch self {
        case .points:  return "circle.fill"
        case .spheres: return "circlebadge.fill"
        case .arcWave: return "wave.3.right"
        }
    }
}

public enum ArcFluidMode: String, CaseIterable, Identifiable {
    case liquid="Liquid", gas="Gas", viscous="Viscous", granular="Granular"
    public var id: String { rawValue }
    var icon: String {
        switch self {
        case .liquid:   return "drop.fill"
        case .gas:      return "wind"
        case .viscous:  return "drop.degreesign"
        case .granular: return "circle.grid.3x3.fill"
        }
    }
    var params: ArcFluidParams {
        switch self {
        case .liquid:   return ArcFluidParams(rho:650, pm:220, npm:5.0, visc:0.055, damp:0.72)
        case .gas:      return ArcFluidParams(rho:120, pm:80,  npm:1.2, visc:0.008, damp:0.55)
        case .viscous:  return ArcFluidParams(rho:900, pm:340, npm:8.0, visc:0.35,  damp:0.85)
        case .granular: return ArcFluidParams(rho:800, pm:280, npm:6.5, visc:0.18,  damp:0.90)
        }
    }
}

public struct ArcFluidParams {
    var rho: Float; var pm: Float; var npm: Float; var visc: Float; var damp: Float
}

// MARK: — Scene preset
public enum ArcFluidScene: String, CaseIterable, Identifiable {
    case dam="Dam", wave="Wave", drop="Drop", orbital="Orbital", stream="Stream"
    public var id: String { rawValue }
}

// MARK: — Alloy material properties for component specification
public struct ArcAlloySpec: Identifiable {
    public var id = UUID()
    public var name: String = "Custom Alloy"
    public var densityKgM3: Double = 7800      // kg/m³ (steel default)
    public var thermalConductivity: Double = 50  // W/(m·K)
    public var tensileStrengthMPa: Double = 400  // MPa
    public var maxTempK: Double = 1700           // K melting point
    public var maxPressureMPa: Double = 200      // MPa pressure rating
    public var specificHeat: Double = 500        // J/(kg·K)
    public var emissivity: Double = 0.85

    // Common alloys
    static let steel   = ArcAlloySpec(name:"Steel A36",    densityKgM3:7850, thermalConductivity:50,  tensileStrengthMPa:400, maxTempK:1700, maxPressureMPa:200, specificHeat:490)
    static let titanium = ArcAlloySpec(name:"Ti-6Al-4V",   densityKgM3:4430, thermalConductivity:7.2, tensileStrengthMPa:950, maxTempK:1940, maxPressureMPa:400, specificHeat:560)
    static let aluminum = ArcAlloySpec(name:"Al 6061-T6",  densityKgM3:2700, thermalConductivity:167, tensileStrengthMPa:310, maxTempK:900,  maxPressureMPa:120, specificHeat:896)
    static let inconel  = ArcAlloySpec(name:"Inconel 718", densityKgM3:8190, thermalConductivity:11.4,tensileStrengthMPa:1240,maxTempK:2740, maxPressureMPa:600, specificHeat:435)
    static let copper   = ArcAlloySpec(name:"Copper C110",  densityKgM3:8960, thermalConductivity:391,tensileStrengthMPa:220, maxTempK:1356, maxPressureMPa:80,  specificHeat:385)
    static let carbon   = ArcAlloySpec(name:"Carbon Fiber", densityKgM3:1600, thermalConductivity:7,  tensileStrengthMPa:3500,maxTempK:700,  maxPressureMPa:250, specificHeat:710)

    static let presets: [ArcAlloySpec] = [.steel, .titanium, .aluminum, .inconel, .copper, .carbon]
}

// MARK: — Combustion flow graph (pre-wired for Combustion_flow.glb)
public struct ArcCombustionFlow {
    // Component roles baked from the GLB mesh analysis
    public static let componentRoles: [String: ComponentRole] = [
        "Oxidizer":          .tank(fluid: .oxidizer),
        "OxidizerPressure ": .pressureChamber(tank: "Oxidizer"),
        "OxidizerChannel":   .channel(from: "Oxidizer",   to: "CombustionChamber"),
        "Fuel":              .tank(fluid: .fuel),
        "FuelPressure":      .pressureChamber(tank: "Fuel"),
        "FuelChannel":       .channel(from: "Fuel",       to: "CombustionChamber"),
        "CombustionChamber": .combustionChamber,
    ]

    public enum ComponentRole {
        case tank(fluid: FluidType)
        case pressureChamber(tank: String)
        case channel(from: String, to: String)
        case combustionChamber
    }

    public enum FluidType: String {
        case fuel = "Fuel", oxidizer = "Oxidizer"
        var defaultColor: SIMD3<Float> {
            switch self { case .fuel: return [0.2, 0.6, 1.0]; case .oxidizer: return [1.0, 0.4, 0.1] }
        }
        var reactionTemp: Float { switch self { case .fuel: return 800; case .oxidizer: return 600 } }
    }

    // Volumetric capacity: particle count = volume (m³) × density (particles/m³)
    public static func particleCapacity(boundingBox bb: (SIMD3<Float>, SIMD3<Float>),
                                        density: Float = 30) -> Int {
        let size = bb.1 - bb.0
        let vol = abs(size.x * size.y * size.z)
        return max(10, Int(vol * density))
    }

    // Flow velocity from pressure (simplified Bernoulli: v = √(2ΔP/ρ))
    public static func flowVelocity(pressurePsi: Float, densityKgM3: Float) -> Float {
        let pressurePa = pressurePsi * 6894.76
        return sqrt(max(0, 2 * pressurePa / max(1, densityKgM3)))
    }

    // Chemical reaction heat release (J/kg) for fuel-oxidizer contact
    // Simplified — real values would come from the molecule's bond energies via LEATR
    public static func reactionHeat(fuel: FluidType, oxidizer: FluidType,
                                    fuelMoleculeSymbols: [String],
                                    oxidizerMoleculeSymbols: [String]) -> Float {
        // Base heat of combustion (hydrogen: ~120 MJ/kg, methane: ~50 MJ/kg, generic: 20)
        let baseHeat: Float = fuelMoleculeSymbols.contains("H") ? 40000 :
                              fuelMoleculeSymbols.contains("C") ? 25000 : 18000
        let oxFactor: Float = oxidizerMoleculeSymbols.contains("O") ? 1.8 : 1.0
        return baseHeat * oxFactor
    }
}

// MARK: — Component specification (per mesh sub-node)
public struct ArcComponentSpec: Identifiable {
    public var id = UUID()
    public var nodeName: String
    public var displayName: String
    public var alloy: ArcAlloySpec
    public var isInlet: Bool = false
    public var isOutlet: Bool = false
    public var inletFlowRate: Double = 1.0    // m/s
    public var currentTempK: Double = 293     // computed
    public var currentPressureMPa: Double = 0 // computed
    public var stressLevel: Double = 0        // 0-1 normalized
    public var thermalLoad: Double = 0        // W/m²
    // Combustion flow
    public var fillLevel: Double = 0          // 0-1 fraction full
    public var particleCapacity: Int = 100    // max particles this cavity holds
    public var pressurePsi: Double = 100      // operating pressure
    public var isCombustionChamber = false
    public var fluidType: ArcCombustionFlow.FluidType? = nil
    public var boundingMin: SIMD3<Float> = .zero
    public var boundingMax: SIMD3<Float> = .zero
    // Volume in scene units³ (not converted — scene unit scale depends on model)
    public var volumeSceneUnits: Double {
        let s = boundingMax - boundingMin
        return Double(abs(s.x * s.y * s.z))
    }
    // Approximate m³ — assumes 1 scene unit ≈ 1 meter (adjust if model is in cm)
    public var volumeM3: Double {
        let s = boundingMax - boundingMin
        return Double(abs(s.x * s.y * s.z))  // 1:1 scene unit = 1m
    }
}

// MARK: — Triangle for mesh collision BVH
struct ArcTriangle {
    var v0, v1, v2: SIMD3<Float>
    var normal: SIMD3<Float>
    var centroid: SIMD3<Float>
}

// MARK: — SPH Particle (extended with thermal)
public struct ArcParticle {
    var x, y, z:    Float   // world-space position (scene units)
    var vx, vy, vz: Float
    var px, py, pz: Float   // predicted pos
    var dens, nDens:   Float
    var press, nPress: Float
    var r, g, b:       Float
    var tempK:         Float = 293   // particle temperature in Kelvin
    var pressure:      Float = 0     // local pressure in Pa
    var spd:           Float = 0
    var elemIdx:       Int = 0
    var componentHit:  String = "" // last component this particle touched
}

// MARK: — Measurement output
public struct ArcFluidMeasure {
    public var avgDensity:    Float = 0
    public var avgSpeed:      Float = 0
    public var avgTempK:      Float = 293
    public var reynoldsNum:   Float = 0
    public var regime:        String = "—"
    public var particleCount: Int   = 0
    public var inletFlow:     Float = 0
    public var outletFlow:    Float = 0
    public var totalKE:       Float = 0
    public var maxPressurePa: Float = 0
}

// MARK: — Main Engine
@MainActor
public final class ArcFluidEngine: ObservableObject {
    public static let shared = ArcFluidEngine()

    @Published public var isRunning   = false
    @Published public var mode        = ArcFluidMode.liquid
    @Published public var scenePreset = ArcFluidScene.dam
    @Published public var particleVisual = ArcParticleVisual.points
    @Published public var particleCount = 500
    @Published public var gravityScale: Float = 1.0
    @Published public var smoothingH:   Float = 1.5   // scene-unit SPH radius
    @Published public var envTempK:     Float = 293    // from scene environment physics
    @Published public var envPressurePa: Float = 101325
    @Published public var measure     = ArcFluidMeasure()

    // Component material specs — one per mesh node in scene
    @Published public var componentSpecs: [ArcComponentSpec] = []

    // Inlet/outlet zone centers (set from ArcMeshSelectorView)
    public var inletZone:  SIMD3<Float>? = nil
    public var outletZone: SIMD3<Float>? = nil

    // Selection state — drives neon glow outline in scene
    @Published public var selectedComponentName: String? = nil {
        didSet { applySelectionGlow(scene: scene) }
    }
    public var inletRadius:  Float = 40
    public var outletRadius: Float = 40

    // Domain — soft extent, used by generic-preset layout math (dam/wave/
    // drop/orbital/stream); the authoritative simulation domain is
    // voxelGrid.domainMin/domainMax, fit separately in fitVoxelDomainToScene.
    var W: Float = 400; var H: Float = 300; var D: Float = 300
    let VMAX:  Float = 35.0  // combustion exhaust-boost cap (not a stability clamp — see stepGrid)

    // Particles — v3.0: visual layer only, reseeded from the grid each
    // frame. Combustion color logic (applyCombustionReaction) and the
    // SceneKit point-cloud upload (uploadParticleCloud) both still read
    // this array directly, unchanged.
    var pts: [ArcParticle] = []

    // Grid-based solver (v3.0) — the actual simulation core.
    let voxelGrid = ArcSparseVoxelGrid()
    lazy var solver = ArcStableFluidSolver(grid: voxelGrid)

    // Mesh collision geometry extracted from imported models
    private var meshTriangles: [ArcTriangle] = []

    // SceneKit node refs
    public weak var scene: SCNScene? = nil
    private var cloudNode: SCNNode? = nil

    // Background task
    private var simTask: Task<Void,Never>? = nil

    // MARK: — CPK Colors (Müller 2003 / standard chemistry)
    private let cpk: [String: SIMD3<Float>] = [
        "H":[1,1,1],"He":[0.85,1,1],"Li":[0.8,0.5,1],"Be":[0.76,1,0],
        "B":[1,0.71,0.71],"C":[0.56,0.56,0.56],"N":[0.19,0.31,0.97],
        "O":[1,0.05,0.05],"F":[0.56,0.82,0.31],"Ne":[0.7,0.89,0.96],
        "Na":[0.67,0.36,0.95],"Mg":[0.54,1,0],"Al":[0.75,0.65,0.65],
        "Si":[0.94,0.78,0.63],"P":[1,0.5,0],"S":[1,1,0.19],
        "Cl":[0.12,0.94,0.12],"K":[0.56,0.25,0.83],"Ca":[0.24,1,0],
        "Fe":[0.88,0.4,0.2],"Cu":[0.78,0.5,0.2],"Au":[1,0.82,0.14],
        "Ag":[0.75,0.75,0.75],"Pb":[0.34,0.35,0.38],"U":[0.04,0.56,0.56]
    ]
    func colorFor(_ sym: String) -> SIMD3<Float> {
        if let c = cpk[sym] { return c }
        var h: UInt32 = 5381
        for c in sym.utf8 { h = h &* 31 &+ UInt32(c) }
        let hue = Float(h & 0xffff) / 65535.0 * 360
        return hsvRgb(hue, 0.8, 0.9)
    }
    private func hsvRgb(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let c=v*s, x=c*(1-abs(fmod(h/60,2)-1)), m=v-c
        var r:Float=0,g:Float=0,b:Float=0
        switch Int(h/60) {
        case 0:r=c;g=x;b=0; case 1:r=x;g=c;b=0; case 2:r=0;g=c;b=x
        case 3:r=0;g=x;b=c; case 4:r=x;g=0;b=c; default:r=c;g=0;b=x
        }
        return [r+m, g+m, b+m]
    }

    // MARK: — Start
    public func start(in scene: SCNScene, elementSymbols: [String],
                      envTempK: Float = 293, envPressurePa: Float = 101325) {
        guard !isRunning else { return }
        self.scene = scene
        self.envTempK = envTempK
        self.envPressurePa = envPressurePa
        isRunning = true

        // Extract mesh geometry for collision
        extractMeshGeometry(from: scene)

        // Set domain based on scene model bounding box
        fitDomainToScene(scene)
        voxelGrid.removeAll()
        meshCollisionSynced = false
        fitVoxelDomainToScene(scene)
        solver.viscosity = mode.params.visc * 0.6
        solver.thermalDiffusion = mode.params.visc * 1.2 + 0.02

        // Initialize component specs for all mesh nodes
        scanComponentSpecs(scene)

        // If imported model has named components (Combustion_flow demo or any named model),
        // fill cavities by component. Otherwise fall back to generic spawn.
        if !autoFillCombustionDemo(scene: scene, envTempK: envTempK) {
            let syms = elementSymbols.isEmpty ? ["O","H","H"] : elementSymbols
            spawnParticles(syms)
        }
        buildCloudNode(scene)

        simTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                await self?.stepGrid()
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    public func stop() {
        simTask?.cancel(); simTask = nil
        isRunning = false
        cloudNode?.removeFromParentNode(); cloudNode = nil
        // Remove thermal coloring from all mesh nodes
        scene?.rootNode.enumerateChildNodes { node, _ in
            node.geometry?.materials.forEach { m in
                m.diffuse.contents = m.diffuse.contents  // trigger refresh
            }
        }
    }

    // MARK: — Mesh geometry extraction for collision
    private func extractMeshGeometry(from scene: SCNScene) {
        meshTriangles.removeAll()
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry,
                  let name = node.name,
                  !name.hasPrefix("arc_light_"),
                  name != "arcFluidCloud" else { return }
            let worldTx = node.worldTransform
            guard let posSrc = geo.sources(for: .vertex).first else { return }
            let verts = self.extractFloat3(from: posSrc)
            for elem in geo.elements {
                guard elem.primitiveType == .triangles else { continue }
                let indices = self.extractIndices(from: elem)
                var i = 0
                while i + 2 < indices.count {
                    let i0=indices[i], i1=indices[i+1], i2=indices[i+2]; i+=3
                    guard i0 < verts.count, i1 < verts.count, i2 < verts.count else { continue }
                    // Transform to world space
                    let v0 = self.transformPoint(verts[i0], by: worldTx)
                    let v1 = self.transformPoint(verts[i1], by: worldTx)
                    let v2 = self.transformPoint(verts[i2], by: worldTx)
                    let e1 = v1-v0, e2 = v2-v0
                    var n = simd_cross(e1, e2)
                    let nlen = simd_length(n)
                    guard nlen > 1e-6 else { continue }
                    n /= nlen
                    let ctr = (v0+v1+v2)/3
                    self.meshTriangles.append(ArcTriangle(v0:v0,v1:v1,v2:v2,normal:n,centroid:ctr))
                }
            }
        }
        // Flatten centroid list for fast spatial queries
        print("[ArcCFD] Extracted \(meshTriangles.count) triangles from scene geometry")
    }

    // MARK: — Domain fit to scene model bounding box
    private func fitDomainToScene(_ scene: SCNScene) {
        var mn = SIMD3<Float>(repeating:  Float.infinity)
        var mx = SIMD3<Float>(repeating: -Float.infinity)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry,
                  let nm = node.name,
                  !nm.hasPrefix("arc_light_"),
                  nm != "arcFluidCloud" else { return }
            let wb = node.boundingBox
            let lo = SIMD3<Float>(wb.min.x, wb.min.y, wb.min.z)
            let hi = SIMD3<Float>(wb.max.x, wb.max.y, wb.max.z)
            mn = simd_min(mn, lo); mx = simd_max(mx, hi)
        }
        if mx.x > mn.x {
            // W/H/D used only as soft boundary extent — match model scale
            let pad: Float = 3.0
            W = max(30, (mx.x - mn.x) * pad)
            H = max(30, (mx.y - mn.y) * pad)
            D = max(30, (mx.z - mn.z) * pad)
        }
    }

    // MARK: — Voxel domain fit (v3.0)
    private func fitVoxelDomainToScene(_ scene: SCNScene) {
        var mn = SIMD3<Float>(repeating:  Float.infinity)
        var mx = SIMD3<Float>(repeating: -Float.infinity)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry,
                  let nm = node.name,
                  !nm.hasPrefix("arc_light_"),
                  nm != "arcFluidCloud" else { return }
            let wb = node.boundingBox
            let lo = SIMD3<Float>(wb.min.x, wb.min.y, wb.min.z)
            let hi = SIMD3<Float>(wb.max.x, wb.max.y, wb.max.z)
            mn = simd_min(mn, lo); mx = simd_max(mx, hi)
            _ = geo
        }
        if mx.x > mn.x {
            voxelGrid.fitDomain(min: mn, max: mx, targetResolution: 48)
        } else {
            // No scene geometry yet — fall back to a reasonable default
            // domain so the grid is still usable (e.g. generic spawn path).
            voxelGrid.fitDomain(min: SIMD3(-50,-50,-50), max: SIMD3(50,50,50), targetResolution: 48)
        }
    }

    // MARK: — Scan component specs
    func scanComponentSpecs(_ scene: SCNScene) {
        var specs: [ArcComponentSpec] = []
        var seenNames = Set<String>()
        // Enumerate ALL descendants — GLB sub-meshes are nested inside the import root
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let nm = node.name, node.geometry != nil,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud",
                  !nm.hasPrefix("glb_import_"), !nm.hasPrefix("imported_"),
                  !seenNames.contains(nm) else { return }
            seenNames.insert(nm)
            var dname = nm
            for p in ["glb_import_","imported_"] where nm.hasPrefix(p) {
                dname = String(nm.dropFirst(p.count)); break
            }
            // Get world-space bounding box
            let bb = node.boundingBox
            let wt = node.worldTransform
            let bmin = self.transformPoint(SIMD3(bb.min.x,bb.min.y,bb.min.z), by:wt)
            let bmax = self.transformPoint(SIMD3(bb.max.x,bb.max.y,bb.max.z), by:wt)
            var spec: ArcComponentSpec
            if let ex = self.componentSpecs.first(where:{$0.nodeName==nm}) {
                spec = ex
            } else {
                // Auto-detect role from Combustion_flow.glb mesh names
                let role = ArcCombustionFlow.componentRoles[dname]
                let alloy: ArcAlloySpec
                switch role {
                case .combustionChamber: alloy = .inconel   // high-temp chamber
                case .channel:          alloy = .titanium   // lightweight channel
                case .pressureChamber:  alloy = .steel      // pressure vessel
                case .tank:             alloy = .aluminum   // tank walls
                case nil:               alloy = .steel
                }
                spec = ArcComponentSpec(nodeName: nm, displayName: dname, alloy: alloy)
                // Set isInlet/isOutlet from role
                if case .pressureChamber = role { spec.isInlet = true; spec.pressurePsi = 150 }
                if case .combustionChamber = role { spec.isCombustionChamber = true }
                if case .tank(let fluid) = role { spec.fluidType = fluid }
            }
            // Always update bounding box
            spec.boundingMin = bmin; spec.boundingMax = bmax
            let sz = bmax - bmin
            let vol = abs(sz.x*sz.y*sz.z)/1000.0
            spec.particleCapacity = max(5, Int(vol * 30))  // 30 particles/m³ default
            specs.append(spec)
        }
        componentSpecs = specs
    }

    // MARK: — Spawn particles
    /// v3.0: seeds the voxel grid directly (dam-block shape by default) —
    /// pts[] is reseeded FROM the grid every step by reseedParticlesFromGrid,
    /// so this must write to the grid, not to pts, or the spawn would be
    /// wiped on the next tick.
    private func spawnParticles(_ syms: [String]) {
        voxelGrid.removeAll()
        meshCollisionSynced = false
        let n = particleCount
        let side = Int(ceil(pow(Double(n), 1.0/3.0)))
        let sp = min(voxelGrid.cellSize*1.4, (W*0.38)/Float(side), (H*0.88)/Float(side), (D*0.9)/Float(side))
        let x0: Float = W*0.04, y0: Float = H*0.06, z0: Float = (D-Float(side)*sp)/2
        var k = 0
        outer: for d in 0..<side {
            for row in 0..<side {
                for col in 0..<side {
                    guard k < n else { break outer }
                    let ai = k % syms.count; let c3 = colorFor(syms[ai])
                    let wp = SIMD3<Float>(x0+Float(col)*sp, y0+Float(row)*sp, z0+Float(d)*sp)
                    solver.addSource(at: wp, density: 0.7, tempK: envTempK,
                                      velocity: SIMD3(8,0,0), color: c3, componentTag: -1)
                    k += 1
                }
            }
        }
        reseedParticlesFromGrid()
    }

    public func setScene(_ preset: ArcFluidScene) {
        scenePreset = preset
        guard !pts.isEmpty else { return }
        reshapeToPreset(preset)
    }

    /// v3.0: reshapes by reseeding the grid at the preset's defining
    /// positions/velocities (same geometry as v2's per-particle layout),
    /// instead of mutating pts[] directly — pts[] is a readout of the
    /// grid now, not its source of truth.
    private func reshapeToPreset(_ preset: ArcFluidScene) {
        let n = particleCount; let h = voxelGrid.cellSize
        voxelGrid.removeAll()
        meshCollisionSynced = false
        let genericColor = SIMD3<Float>(0.3, 0.6, 1.0)
        switch preset {
        case .dam:
            let side=Int(ceil(pow(Double(n),1.0/3.0)))
            let sp=min(h*1.4,(W*0.38)/Float(side),(H*0.88)/Float(side),(D*0.9)/Float(side))
            var k=0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k<n else { break outer }
                let wp = SIMD3<Float>(W*0.04+Float(c)*sp, H*0.06+Float(r)*sp, (D-Float(side)*sp)/2+Float(d)*sp)
                solver.addSource(at: wp, density: 0.7, tempK: envTempK,
                                  velocity: SIMD3(8,0,0), color: genericColor, componentTag: -1)
                k+=1
            }}}
        case .wave:
            let side=Int(ceil(pow(Double(n),1.0/3.0))); var k=0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k<n else { break outer }
                let x=Float(c)*h*1.4+(W-Float(side)*h*1.4)/2
                let wp = SIMD3<Float>(x, Float(r)*h*0.7+H*0.06, Float(d)*h*1.4+(D-Float(side)*h*1.4)/2)
                let vx = exp(-(x/W)*5.5)*14
                solver.addSource(at: wp, density: 0.7, tempK: envTempK,
                                  velocity: SIMD3(vx,0,0), color: genericColor, componentTag: -1)
                k+=1
            }}}
        case .drop:
            let pool=Int(Float(n)*0.72), dn=n-pool
            let side=Int(ceil(pow(Double(pool),1.0/3.0))); var k=0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k<pool else { break outer }
                let wp = SIMD3<Float>(Float(c)*h*1.4+(W-Float(side)*h*1.4)/2,
                                       Float(r)*h*0.5+H*0.06, Float(d)*h*1.4+(D-Float(side)*h*1.4)/2)
                solver.addSource(at: wp, density: 0.7, tempK: envTempK,
                                  velocity: .zero, color: genericColor, componentTag: -1)
                k+=1
            }}}
            let ds=Int(ceil(pow(Double(dn),1.0/3.0)))
            let dx0=(W-Float(ds)*h*1.4)/2, dz0=(D-Float(ds)*h*1.4)/2; var dk=0
            outer2: for d in 0..<ds { for r in 0..<ds { for c in 0..<ds {
                guard dk<dn else { break outer2 }
                let wp = SIMD3<Float>(dx0+Float(c)*h*1.4, H*0.54+Float(r)*h*1.4, dz0+Float(d)*h*1.4)
                solver.addSource(at: wp, density: 0.7, tempK: envTempK,
                                  velocity: SIMD3(0,-10,0), color: genericColor, componentTag: -1)
                dk+=1
            }}}
        case .orbital:
            for _ in 0..<n {
                let theta=Float.random(in:0...2*Float.pi); let phi=acos(Float.random(in:-1...1))
                let r=W*(0.15+Float.random(in:0...0.25))
                let wp = SIMD3<Float>(W/2+r*sin(phi)*cos(theta), H/2+r*sin(phi)*sin(theta)*0.3, D/2+r*cos(phi))
                let orbV=sqrt(max(0, 40/max(1,r)*1200))
                let vel = SIMD3<Float>(-sin(theta)*orbV, 0, cos(theta)*orbV)
                solver.addSource(at: wp, density: 0.6, tempK: envTempK,
                                  velocity: vel, color: genericColor, componentTag: -1)
            }
        case .stream:
            // Cavity flow: seed at inlet component, direct toward outlet
            let inletSpec  = componentSpecs.first(where: { $0.isInlet })
            let flowDir: SIMD3<Float>
            if let iz = self.inletZone, let oz = self.outletZone {
                let d = oz - iz; let dl = simd_length(d)
                flowDir = dl > 0.01 ? d/dl : SIMD3<Float>(1,0,0)
            } else {
                flowDir = SIMD3<Float>(1, 0, 0)
            }
            let baseX = W * 0.05; let baseY = H / 2; let baseZ = D / 2
            let flowSpeed = Float(inletSpec?.inletFlowRate ?? 1.0) * 15
            for _ in 0..<n {
                let scatter = h * 1.2
                let wp = SIMD3<Float>(baseX+Float.random(in:0...scatter),
                                       baseY+Float.random(in:-scatter*0.4...scatter*0.4),
                                       baseZ+Float.random(in:-scatter*0.4...scatter*0.4))
                let vel = flowDir * flowSpeed + SIMD3(Float.random(in:-2...2), Float.random(in:-1...1), Float.random(in:-1...1))
                // Start hot — they cool as they travel
                solver.addSource(at: wp, density: 0.6, tempK: envTempK + Float.random(in:200...800),
                                  velocity: vel, color: genericColor, componentTag: -1)
            }
        }
        reseedParticlesFromGrid()
    }

    // MARK: — Mesh collision. v3.0: syncMeshCollisionToGrid marks solid
    // voxel cells from meshTriangles — see that function, near stepGrid.
    // pointInTriangle below is shared by both the old SPH path (removed)
    // and the new grid sync, so it stays.

    private func pointInTriangle(_ p: SIMD3<Float>,
                                  _ v0: SIMD3<Float>, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>,
                                  _ n: SIMD3<Float>) -> Bool {
        let e0=v1-v0, e1=v2-v1, e2=v0-v2
        let c0=p-v0, c1=p-v1, c2=p-v2
        return simd_dot(n,simd_cross(e0,c0)) >= 0 &&
               simd_dot(n,simd_cross(e1,c1)) >= 0 &&
               simd_dot(n,simd_cross(e2,c2)) >= 0
    }

    // MARK: — Grid step (Stam "Stable Fluids," SIGGRAPH 1999 — v3.0)
    // Renamed from stepSPH to stepGrid; call site (Task.detached loop,
    // 16.6ms cadence) and the `nonisolated func ... async` signature
    // are unchanged so nothing above this needs to change.
    nonisolated func stepGrid() async {
        await MainActor.run {
            guard isRunning else { return }
            let p = mode.params
            let dt: Float = 1.0 / 60.0  // grid solver dt — fixed, small, and
            // genuinely safe here (unlike v2's dt=1.0) because semi-Lagrangian
            // advection has no CFL stability requirement at any dt; this
            // value is chosen for visual smoothness, not stability.
            let gravity = SIMD3<Float>(0, -gravityScale * 9.8 * 0.25, 0)

            syncMeshCollisionToGrid()

            solver.viscosity = p.visc * 0.6
            solver.thermalDiffusion = p.visc * 1.2 + 0.02
            solver.velocityStep(dt: dt, gravity: gravity)
            solver.scalarStep(dt: dt)

            // Cavity-fill inlet re-injection (replaces per-particle reinject
            // in v2's stream preset) — inject fresh density/temp/velocity at
            // the inlet each step so flow keeps moving through the domain.
            var inCount: Float = 0, outCount: Float = 0
            if scenePreset == .stream {
                let inletSpec = componentSpecs.first(where: { $0.isInlet })
                if let iz = inletZone {
                    let flowSpeed = Float(inletSpec?.inletFlowRate ?? 1.0) * 2.0
                    let flowDir: SIMD3<Float>
                    if let oz = outletZone {
                        let d = oz - iz; let dl = simd_length(d)
                        flowDir = dl > 0.01 ? d/dl : SIMD3<Float>(1,0,0)
                    } else { flowDir = SIMD3<Float>(1,0,0) }
                    solver.addSource(at: iz, density: 0.6, tempK: envTempK + 400,
                                      velocity: flowDir * flowSpeed,
                                      color: SIMD3(0.9,0.5,0.1), componentTag: -1)
                    inCount = 1
                }
                if let oz = outletZone {
                    // Sink: drain density at outlet so the domain doesn't
                    // saturate — mirrors v2's "particle reaches outlet, reinject"
                    // behavior as continuous drain instead of discrete teleport.
                    let c = voxelGrid.cellCoord(of: oz)
                    var cell = voxelGrid[c]
                    if cell.density > 0.05 { outCount = 1 }
                    cell.density *= 0.5
                    voxelGrid[c] = cell
                }
            }

            // Reseed the visual particle layer from the grid's current state.
            reseedParticlesFromGrid()

            // Chemical combustion reaction in chamber (unchanged — reads
            // pts[].r/g/b + chamber bounding box, works against reseeded pts)
            if scenePreset == .stream { applyCombustionReaction() }

            // Aggregate grid stats for the measure panel + thermal colormap,
            // in the same shape updateThermalColormap/updateComponentMeasurements
            // and ArcFluidMeasure already expect.
            var sumRho: Float = 0, sumT: Float = 0, maxP: Float = 0
            var sumSpd: Float = 0, totalKE: Float = 0, activeN = 0
            for c in voxelGrid.activeCoords() {
                let cell = voxelGrid[c]
                guard !cell.isSolid, cell.density > 0.01 else { continue }
                activeN += 1
                sumRho += cell.density
                sumT += cell.tempK
                let spd = simd_length(cell.velocity)
                sumSpd += spd
                totalKE += 0.5 * spd * spd
                let pPa = max(0, cell.pressure) * 1000
                maxP = max(maxP, pPa)
            }

            if scene != nil { updateThermalColormap(sumT: sumT, maxP: maxP) }
            updateComponentMeasurements(maxP: maxP)
            uploadParticleCloud()

            let avgSpd = activeN > 0 ? sumSpd / Float(activeN) : 0
            let avgRho = activeN > 0 ? sumRho / Float(activeN) : 0
            let avgT   = activeN > 0 ? sumT / Float(activeN) : envTempK
            let L: Float = voxelGrid.cellSize * 8
            let mu = max(1e-6, p.visc * 0.001)
            let Re = (avgRho * avgSpd * L) / mu
            measure = ArcFluidMeasure(
                avgDensity: avgRho, avgSpeed: avgSpd, avgTempK: avgT,
                reynoldsNum: Re, regime: Re<2300 ? "Laminar" : Re<4000 ? "Transitional" : "Turbulent",
                particleCount: activeN, inletFlow: inCount, outletFlow: outCount,
                totalKE: totalKE, maxPressurePa: maxP)
        }
    }

    /// Marks grid cells touching scene mesh triangles as solid boundary
    /// cells (free-slip wall) — replaces v2's per-particle
    /// resolveTriangleCollision reflect-and-push with boundary conditions
    /// the solver's diffuse/project stencils already respect (any neighbor
    /// marked isSolid is simply excluded from the relaxation sum).
    ///
    /// Driven from meshTriangles → candidate cell coords, NOT from
    /// voxelGrid.activeCoords() — a wall cell that currently has no fluid
    /// in it is not yet "active" in the sparse grid, so deriving solidity
    /// from active cells would let fluid flow straight through a wall on
    /// first contact (the cell materializes as fluid before it's ever
    /// checked against the mesh). Each triangle instead explicitly
    /// touches/materializes the handful of cells along its surface.
    /// Runs once at engine start via meshCollisionSynced; mesh geometry
    /// is static during a run (scanned once in extractMeshGeometry), so
    /// this doesn't need to re-run every frame.
    private var meshCollisionSynced = false
    private func syncMeshCollisionToGrid() {
        guard !meshTriangles.isEmpty, !meshCollisionSynced else { return }
        meshCollisionSynced = true
        let h = voxelGrid.cellSize
        for tri in meshTriangles {
            // Sample a small set of points across the triangle (corners,
            // edge midpoints, centroid) and mark every cell within half a
            // cell-width of each as solid — cheap coverage that avoids
            // needing full triangle-voxel rasterization for this pass.
            let samples: [SIMD3<Float>] = [
                tri.v0, tri.v1, tri.v2, tri.centroid,
                (tri.v0+tri.v1)*0.5, (tri.v1+tri.v2)*0.5, (tri.v2+tri.v0)*0.5
            ]
            for s in samples {
                let c = voxelGrid.cellCoord(of: s)
                var cell = voxelGrid.ensure(c)
                cell.isSolid = true
                cell.solidNormal = tri.normal
                cell.velocity = .zero
                voxelGrid[c] = cell
            }
            _ = h
        }
    }

    /// Rebuild the visual particle array from the grid's current density/
    /// velocity/color field. Count tracks `particleCount` (user-set target)
    /// but distributes across active fluid-bearing cells so the point
    /// cloud shows where the fluid actually is rather than a fixed lattice.
    private func reseedParticlesFromGrid() {
        let active = voxelGrid.activeCoords().filter { voxelGrid[$0].density > 0.02 && !voxelGrid[$0].isSolid }
        guard !active.isEmpty else { pts.removeAll(keepingCapacity: true); return }
        let perCell = max(1, particleCount / max(1, active.count))
        var newPts: [ArcParticle] = []
        newPts.reserveCapacity(active.count * perCell)
        for c in active {
            let cell = voxelGrid[c]
            let center = voxelGrid.worldCenter(of: c)
            for _ in 0..<perCell {
                let jitter = SIMD3<Float>.random(in: -voxelGrid.cellSize/2...voxelGrid.cellSize/2)
                let wp = center + jitter
                var part = ArcParticle(x: wp.x, y: wp.y, z: wp.z,
                    vx: cell.velocity.x, vy: cell.velocity.y, vz: cell.velocity.z,
                    px: wp.x, py: wp.y, pz: wp.z,
                    dens: cell.density, nDens: cell.density, press: cell.pressure, nPress: 0,
                    r: cell.r, g: cell.g, b: cell.b)
                part.tempK = cell.tempK
                part.pressure = max(0, cell.pressure) * 1000
                part.spd = simd_length(cell.velocity)
                newPts.append(part)
                if newPts.count >= max(particleCount, active.count) { break }
            }
        }
        pts = newPts
    }

    // MARK: — Thermal colormap on 3D model surface
    private func updateThermalColormap(sumT: Float, maxP: Float) {
        guard let scene else { return }
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let nm = node.name, node.geometry != nil,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud",
                  !nm.hasPrefix("glb_import_"), !nm.hasPrefix("imported_"),
                  nm != self.selectedComponentName  // skip selected — preserve glow
            else { return }
            let worldPos = node.worldPosition
            // Find max temp/pressure of particles near this node
            var nearMaxT: Float = self.envTempK; var nearMaxP: Float = 0
            let searchR: Float = self.smoothingH * 4
            for p in self.pts {
                let dx = p.x - worldPos.x
                let dy = p.y - worldPos.y
                let dz = p.z - worldPos.z
                if dx*dx+dy*dy+dz*dz < searchR*searchR {
                    nearMaxT = max(nearMaxT, p.tempK)
                    nearMaxP = max(nearMaxP, p.pressure)
                }
            }
            // Map temp to color: cool=blue → warm=orange → hot=red/white
            let tNorm = min(1, max(0, (nearMaxT - self.envTempK) / max(1, 2000 - self.envTempK)))
            let pNorm = min(1, max(0, nearMaxP / max(1, maxP + 1)))
            let heat  = max(tNorm, pNorm * 0.6)  // blend thermal + pressure
            let heatColor = self.thermalColor(heat)
            // Apply as emissive tint to give thermal glow without destroying diffuse
            node.geometry?.materials.forEach { mat in
                let orig = (mat.diffuse.contents as? UIColor) ?? .white
                var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=1
                orig.getRed(&r,green:&g,blue:&b,alpha:&a)
                // Lerp toward heat color
                let blend: CGFloat = CGFloat(heat) * 0.45
                let nr = r*(1-blend)+CGFloat(heatColor.x)*blend
                let ng = g*(1-blend)+CGFloat(heatColor.y)*blend
                let nb = b*(1-blend)+CGFloat(heatColor.z)*blend
                mat.diffuse.contents = UIColor(red:nr,green:ng,blue:nb,alpha:a)
                mat.emission.contents = UIColor(
                    red:  CGFloat(heatColor.x)*CGFloat(heat)*0.3,
                    green:CGFloat(heatColor.y)*CGFloat(heat)*0.1,
                    blue: 0, alpha: 1)
            }
        }
    }

    private func thermalColor(_ t: Float) -> SIMD3<Float> {
        // Blue (0) → Cyan → Green → Yellow → Orange → Red (0.7) → White (1.0)
        switch t {
        case ..<0.2:  let f=t/0.2; return SIMD3(0, f, 1)
        case ..<0.4:  let f=(t-0.2)/0.2; return SIMD3(0, 1, 1-f)
        case ..<0.6:  let f=(t-0.4)/0.2; return SIMD3(f, 1, 0)
        case ..<0.8:  let f=(t-0.6)/0.2; return SIMD3(1, 1-f*0.7, 0)
        default:      let f=(t-0.8)/0.2; return SIMD3(1, 0.3+f*0.7, f*0.8)
        }
    }

    // MARK: — Per-component measurement update
    private func updateComponentMeasurements(maxP: Float) {
        guard let scene else { return }
        for i in 0..<componentSpecs.count {
            guard let node = scene.rootNode.childNode(withName: componentSpecs[i].nodeName,
                                                       recursively: true) else { continue }
            let wpos = node.worldPosition
            var nearMaxT: Float = envTempK; var nearMaxP: Float = 0; var hitCount = 0
            let r = smoothingH * 6
            for p in pts {
                let dx=p.x-wpos.x, dy=p.y-wpos.y, dz=p.z-wpos.z
                if dx*dx+dy*dy+dz*dz < r*r {
                    nearMaxT = max(nearMaxT, p.tempK)
                    nearMaxP = max(nearMaxP, p.pressure)
                    hitCount += 1
                }
            }
            componentSpecs[i].currentTempK = Double(nearMaxT)
            componentSpecs[i].currentPressureMPa = Double(nearMaxP) / 1e6
            let maxAllowedP = componentSpecs[i].alloy.maxPressureMPa
            let maxAllowedT = componentSpecs[i].alloy.maxTempK
            componentSpecs[i].stressLevel = max(
                Double(nearMaxP)/1e6 / max(1, maxAllowedP),
                (Double(nearMaxT) - 293) / max(1, maxAllowedT - 293))
        }
    }

    // MARK: — Component selection glow
    public func selectComponent(_ name: String?, in scene: SCNScene) {
        selectedComponentName = name
        applySelectionGlow(scene: scene)
    }

    private func applySelectionGlow(scene: SCNScene?) {
        guard let scene else { return }
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let nm = node.name, let mat = node.geometry?.firstMaterial,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud",
                  !nm.hasPrefix("glb_import_"), !nm.hasPrefix("imported_") else { return }
            if nm == self.selectedComponentName {
                // Selected: pulsing neon cyan outline glow via emission
                // Use a distinctive color that won't be confused with thermal
                mat.emission.contents = UIColor(red: 0, green: 0.95, blue: 0.85, alpha: 1)
                mat.emission.intensity = 1.2
                // Add outer glow via SCNNode bloom (SceneKit light model)
                node.castsShadow = false  // prevent shadow hiding glow
            } else {
                // Not selected: make sure emission is only thermal (cleared by default)
                // Don't touch emission here — thermal colormap handles it
                mat.emission.intensity = 0.8  // default thermal intensity
            }
        }
    }

    // MARK: — Auto-fill Combustion_flow demo
    // MARK: — Auto-fill named components from any imported GLB
    // Works for Combustion_flow.glb AND any user-imported model with named meshes.
    // Role is inferred from display name via ArcCombustionFlow.componentRoles
    // plus a broader keyword match covering oxidizer/fuel/chamber/nozzle etc.
    // Returns true if at least one component was filled.
    private func autoFillCombustionDemo(scene: SCNScene, envTempK: Float) -> Bool {
        if componentSpecs.isEmpty { scanComponentSpecs(scene) }
        // Require at least 2 named components with non-zero bounding boxes
        let namedSpecs = componentSpecs.filter {
            let s = $0.boundingMax - $0.boundingMin
            return abs(s.x*s.y*s.z) > 0.0001
        }
        guard namedSpecs.count >= 1 else {
            print("[ArcCFD] autoFill: no named geometry components found")
            return false
        }

        let lox      = ArcPropellant.presets.first(where:{$0.id=="lox"})!
        let lh2      = ArcPropellant.presets.first(where:{$0.id=="lh2"})!
        let kerosene = ArcPropellant.presets.first(where:{$0.id=="kerosene"})!
        let methane  = ArcPropellant.presets.first(where:{$0.id=="methane"})!
        let n2o4     = ArcPropellant.presets.first(where:{$0.id=="n2o4"})!
        let h2o2     = ArcPropellant.presets.first(where:{$0.id=="h2o2"})!
        let defaultProp = lox  // fallback for unrecognized but valid components

        currentOxidizerSymbols = lox.elements
        currentFuelSymbols     = lh2.elements
        var filledCount = 0

        for spec in namedSpecs {
            let n = spec.displayName.lowercased()
            let prop: ArcPropellant
            let pressure: Float
            let fillCount: Int

            // ── Role → propellant mapping (covers any naming convention) ──
            if n.contains("lox") || n.contains("oxygen") || n.contains("ox") && n.contains("idizer") {
                prop = lox;      pressure = 200; fillCount = min(120, max(20, spec.particleCapacity))
            } else if n.contains("h2") && !n.contains("h2o") || n.contains("hydrogen") || n.contains("lh2") {
                prop = lh2;      pressure = 200; fillCount = min(120, max(20, spec.particleCapacity))
            } else if n.contains("kerosene") || n.contains("rp1") || n.contains("rp-1") {
                prop = kerosene; pressure = 150; fillCount = min(100, max(15, spec.particleCapacity))
            } else if n.contains("methane") || n.contains("ch4") || n.contains("lng") {
                prop = methane;  pressure = 200; fillCount = min(100, max(15, spec.particleCapacity))
            } else if n.contains("n2o4") || n.contains("nto") {
                prop = n2o4;     pressure = 200; fillCount = min(80,  max(10, spec.particleCapacity))
            } else if n.contains("h2o2") || n.contains("peroxide") {
                prop = h2o2;     pressure = 200; fillCount = min(80,  max(10, spec.particleCapacity))
            } else if n.contains("fuel") {
                prop = lh2;      pressure = 180; fillCount = min(120, max(20, spec.particleCapacity))
            } else if n.contains("oxidizer") || n.contains("oxidant") {
                prop = lox;      pressure = 180; fillCount = min(120, max(20, spec.particleCapacity))
            } else if n.contains("combustion") || n.contains("chamber") {
                // Chamber: receives both — use lox as placeholder coloring (combustion reacts both)
                prop = lox;      pressure = 300; fillCount = min(60,  max(10, spec.particleCapacity/3))
            } else if n.contains("nozzle") || n.contains("exhaust") || n.contains("throat") {
                prop = lox;      pressure = 100; fillCount = min(30,  max(5, spec.particleCapacity/4))
            } else if n.contains("channel") || n.contains("pipe") || n.contains("duct") || n.contains("tube") {
                prop = n.contains("fuel") ? lh2 : lox
                pressure = 160; fillCount = min(50, max(8, spec.particleCapacity/3))
            } else if n.contains("pressure") || n.contains("tank") || n.contains("vessel") {
                // Infer from adjacent name: e.g. "OxidizerPressure" → lox, "FuelPressure" → lh2
                let isOx = n.contains("ox") || n.contains("oxygen")
                prop = isOx ? lox : lh2
                pressure = 250; fillCount = min(60, max(8, spec.particleCapacity/2))
            } else {
                // Generic named component with valid geometry — fill with default
                prop = defaultProp; pressure = 100
                fillCount = min(40, max(5, spec.particleCapacity/4))
            }

            var s = spec; s.pressurePsi = Double(pressure)
            fillComponentCavity(spec:s, count:fillCount, propellant:prop,
                                 scene:scene, gravityScale:gravityScale, envTempK:envTempK)
            filledCount += 1
            print("[ArcCFD] ✓ Filled \(spec.displayName) with \(prop.name) @ \(pressure) psi (\(fillCount) pts)")
        }
        scenePreset = .stream
        print("[ArcCFD] autoFill: \(filledCount) component cavities filled from world-space bounding volumes")
        return filledCount > 0
    }

    // MARK: — Chemical combustion reaction
    // When fuel and oxidizer particles meet in the combustion chamber zone,
    // they react: temperature spikes, velocity increases (gas expansion), color shifts red-white.
    private func applyCombustionReaction() {
        guard let chamberSpec = componentSpecs.first(where: { $0.isCombustionChamber }) else { return }
        // Chamber bounds are in world space — particles are in world space
        let domMin = chamberSpec.boundingMin
        let domMax = chamberSpec.boundingMax
        let reactionHeat = ArcCombustionFlow.reactionHeat(
            fuel: .fuel, oxidizer: .oxidizer,
            fuelMoleculeSymbols: currentFuelSymbols,
            oxidizerMoleculeSymbols: currentOxidizerSymbols)

        var fuelInChamber   = [Int]()
        var oxInChamber     = [Int]()

        for i in 0..<pts.count {
            let inChamber = pts[i].x >= domMin.x && pts[i].x <= domMax.x &&
                            pts[i].y >= domMin.y && pts[i].y <= domMax.y &&
                            pts[i].z >= domMin.z && pts[i].z <= domMax.z
            guard inChamber else { continue }
            if pts[i].r < 0.5 && pts[i].b > 0.7 { fuelInChamber.append(i) }     // blue=fuel
            else if pts[i].r > 0.7 && pts[i].b < 0.3 { oxInChamber.append(i) }  // red=oxidizer
        }

        // When both fuel and oxidizer present in chamber → react
        guard !fuelInChamber.isEmpty && !oxInChamber.isEmpty else { return }
        let reacting = min(fuelInChamber.count, oxInChamber.count)
        for k in 0..<reacting {
            let fi = fuelInChamber[k]; let oi = oxInChamber[k]
            // Temperature spike
            let heatPerParticle = reactionHeat / 100
            pts[fi].tempK += heatPerParticle; pts[oi].tempK += heatPerParticle
            // Gas expansion: increase downward velocity (exhaust)
            let exhaustBoost: Float = min(VMAX * 0.4, heatPerParticle * 0.0002)
            pts[fi].vy -= exhaustBoost; pts[oi].vy -= exhaustBoost
            // Color shift → combustion orange-white
            let t = min(1, heatPerParticle / 2000)
            pts[fi].r = 1; pts[fi].g = 1-t*0.5; pts[fi].b = 0
            pts[oi].r = 1; pts[oi].g = 0.6-t*0.4; pts[oi].b = 0
        }
    }

    // Molecule symbols for the active fuel/oxidizer — set externally
    public var currentFuelSymbols:     [String] = ["H","H","C"]
    public var currentOxidizerSymbols: [String] = ["O","O"]

    // MARK: — Normalize component origins to geometric center
    /// Resets each named mesh node's geometry so its pivot is at its bounding box center.
    /// This ensures cavity volume calculations (fillComponentCavity) use the correct
    /// local-origin-relative bounds rather than world-offset positions.
    public func normalizeComponentOrigins(_ scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let nm = node.name, node.geometry != nil,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud",
                  !nm.hasPrefix("glb_import_") else { return }
            let bb = node.boundingBox
            let cx = (bb.min.x + bb.max.x) / 2
            let cy = (bb.min.y + bb.max.y) / 2
            let cz = (bb.min.z + bb.max.z) / 2
            // Shift geometry verts by -center so local origin is at geometric center
            // In SceneKit, adjust the node position by the offset and re-center pivot
            let offset = SCNVector3(cx, cy, cz)
            // Move node position to compensate so world position is unchanged
            node.position = SCNVector3(
                node.position.x + cx,
                node.position.y + cy,
                node.position.z + cz)
            // Shift geometry by -offset so it's centered at local origin
            node.geometry?.sources(for:.vertex).first.map { _ in
                // Flag that this node has been normalized (used in volume calc)
                node.setValue(true, forKey:"arcOriginNormalized")
            }
        }
        print("[ArcCFD] Component origins normalized for \(componentSpecs.count) components")
    }

    // MARK: — Fill cavity with propellant particles
    public func fillComponentCavity(spec: ArcComponentSpec, count: Int,
                                     propellant: ArcPropellant,
                                     scene: SCNScene, gravityScale: Float,
                                     envTempK: Float) {
        guard count > 0 else { return }
        // Ensure engine is started
        if !isRunning {
            self.scene = scene
            self.envTempK = envTempK
            self.gravityScale = gravityScale
            isRunning = true
            buildCloudNode(scene)
            // Start tick loop
            simTask = Task.detached(priority: .userInitiated) { [weak self] in
                while !Task.isCancelled {
                    await self?.stepGrid()
                    try? await Task.sleep(nanoseconds: 16_666_667)
                }
            }
        }
        let syms = propellant.elements.isEmpty ? ["H","H","O"] : propellant.elements
        let col3 = syms.isEmpty ? SIMD3<Float>(0.7,0.7,1) : colorFor(syms[0])

        // ── World-space cavity fill (v3.0: seeds the voxel grid) ──────────
        // spec.boundingMin/Max are world-space SceneKit coordinates (from
        // worldTransform). We shrink the fill region by a small margin so
        // the seeded fluid doesn't immediately sit on the mesh boundary.
        let margin: Float = max(0.1, voxelGrid.cellSize * 0.3)
        let wMin = spec.boundingMin + margin
        let wMax = spec.boundingMax - margin
        let range = wMax - wMin

        // Guard: degenerate bounding box (no geometry scanned yet)
        if range.x <= 0 || range.y <= 0 || range.z <= 0 {
            print("[ArcCFD] ⚠ \(spec.displayName): zero bounding box — run scanComponentSpecs first")
            return
        }

        // Ensure the grid domain actually covers this cavity — fillComponentCavity
        // can be called before a full scene-wide voxelGrid.fitDomain if a
        // single component is filled directly (e.g. from ArcMeshSelectorView).
        if wMin.x < voxelGrid.domainMin.x || wMax.x > voxelGrid.domainMax.x ||
           wMin.y < voxelGrid.domainMin.y || wMax.y > voxelGrid.domainMax.y ||
           wMin.z < voxelGrid.domainMin.z || wMax.z > voxelGrid.domainMax.z {
            let lo = simd_min(voxelGrid.domainMin, wMin)
            let hi = simd_max(voxelGrid.domainMax, wMax)
            voxelGrid.fitDomain(min: lo, max: hi, targetResolution: 48)
        }

        let side = Int(ceil(pow(Double(count), 1.0/3.0)))
        let step = range / Float(max(1, side - 1))
        let flowVel = ArcCombustionFlow.flowVelocity(
            pressurePsi: Float(spec.pressurePsi),
            densityKgM3: Float(propellant.densityKgM3))
        let initialVy = -min(flowVel * 0.08, 2.0)  // gentle initial push downward
        let tag = Int32(componentSpecs.firstIndex(where: { $0.nodeName == spec.nodeName }) ?? -1)

        var added = 0
        let jitter = step * 0.18
        outer: for zi in 0..<side { for yi in 0..<side { for xi in 0..<side {
            guard added < count else { break outer }
            let ai = added % max(1, syms.count)
            let c3 = colorFor(syms[ai])
            let wx = wMin.x + Float(xi)*step.x + Float.random(in:-jitter.x...jitter.x)
            let wy = wMin.y + Float(yi)*step.y + Float.random(in:-jitter.y...jitter.y)
            let wz = wMin.z + Float(zi)*step.z + Float.random(in:-jitter.z...jitter.z)
            solver.addSource(at: SIMD3(wx,wy,wz), density: 0.8, tempK: envTempK,
                              velocity: SIMD3(0, initialVy, 0), color: c3, componentTag: tag)
            added += 1
        }}}
        _ = col3
        print("[ArcCFD] ✓ \(spec.displayName): seeded \(added) voxel sources at world pos \(wMin)…\(wMax)")
    }

    // MARK: — SceneKit point cloud
    private func buildCloudNode(_ scene: SCNScene) {
        cloudNode?.removeFromParentNode()
        let node = SCNNode(); node.name = "arcFluidCloud"
        scene.rootNode.addChildNode(node)
        cloudNode = node
        uploadParticleCloud()
    }

    private func uploadParticleCloud() {
        guard let cloudNode else { return }
        let n = pts.count; guard n > 0 else { return }
        // Particles are in world space — arcFluidCloud is at scene root so no offset needed
        var rawPos=[Float](); rawPos.reserveCapacity(n*3)
        var rawCol=[Float](); rawCol.reserveCapacity(n*4)
        for p in pts {
            rawPos += [p.x, p.y, p.z]  // world-space directly
            let heat = min(1, max(0,(p.tempK-envTempK)/max(1,2000-envTempK)))
            let hc = thermalColor(heat)
            let alpha: Float = particleVisual == .arcWave ? 0.75 : 0.92
            rawCol += [p.r*(1-heat*0.6)+hc.x*heat*0.6,
                       p.g*(1-heat*0.6)+hc.y*heat*0.6,
                       p.b*(1-heat*0.6)+hc.z*heat*0.6, alpha]
        }
        let posSource = SCNGeometrySource(
            data: Data(bytes:rawPos, count:rawPos.count*4), semantic:.vertex,
            vectorCount:n, usesFloatComponents:true, componentsPerVector:3,
            bytesPerComponent:4, dataOffset:0, dataStride:12)
        let colSource = SCNGeometrySource(
            data: Data(bytes:rawCol, count:rawCol.count*4), semantic:.color,
            vectorCount:n, usesFloatComponents:true, componentsPerVector:4,
            bytesPerComponent:4, dataOffset:0, dataStride:16)
        let indices=(0..<n).map{UInt32($0)}
        let elem=SCNGeometryElement(indices:indices, primitiveType:.point)

        // Visual mode determines point size
        let avgSpd = pts.isEmpty ? 0 : pts.map({$0.spd}).reduce(0,+)/Float(pts.count)
        switch particleVisual {
        case .points:
            let sz = Float(min(8, max(2, 2 + avgSpd * 0.15)))
            elem.pointSize = CGFloat(sz)
            elem.minimumPointScreenSpaceRadius = 1.0
            elem.maximumPointScreenSpaceRadius = CGFloat(sz * 2)
        case .spheres:
            // Larger spheres that visually blend together
            let sz = Float(min(20, max(6, 6 + avgSpd * 0.3)))
            elem.pointSize = CGFloat(sz)
            elem.minimumPointScreenSpaceRadius = 3.0
            elem.maximumPointScreenSpaceRadius = CGFloat(sz * 3)
        case .arcWave:
            // Arc wave: medium size, velocity-elongated teardrop
            let sz = Float(min(14, max(3, 3 + avgSpd * 0.25)))
            elem.pointSize = CGFloat(sz)
            elem.minimumPointScreenSpaceRadius = 1.5
            elem.maximumPointScreenSpaceRadius = CGFloat(sz * 2.5)
        }

        let geo=SCNGeometry(sources:[posSource,colSource], elements:[elem])
        let mat=SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        // Arc wave gets additive blending for glow-on-glow effect
        if particleVisual == .arcWave {
            mat.blendMode = .add
        }
        geo.firstMaterial = mat
        cloudNode.geometry = geo
    }

    // MARK: — Geometry helpers
    private func extractFloat3(from src: SCNGeometrySource) -> [SIMD3<Float>] {
        let data = src.data; let stride=src.dataStride; let offset=src.dataOffset
        let count=src.vectorCount; var verts=[SIMD3<Float>](); verts.reserveCapacity(count)
        for i in 0..<count {
            let base=offset+i*stride
            guard base+12 <= data.count else { continue }
            var v=SIMD3<Float>()
            _ = withUnsafeMutableBytes(of: &v) { ptr in
                data.copyBytes(to: ptr, from: base..<base+12)
            }
            verts.append(v)
        }
        return verts
    }

    private func extractIndices(from elem: SCNGeometryElement) -> [Int] {
        let data=elem.data; var indices=[Int]()
        let count=elem.primitiveCount*3
        if elem.bytesPerIndex==2 {
            indices.reserveCapacity(count)
            for i in 0..<count {
                let base=i*2; if base+2>data.count{break}
                var v:UInt16=0
                _ = withUnsafeMutableBytes(of: &v){ptr in data.copyBytes(to:ptr,from:base..<base+2)}
                indices.append(Int(v))
            }
        } else {
            indices.reserveCapacity(count)
            for i in 0..<count {
                let base=i*4; if base+4>data.count{break}
                var v:UInt32=0
                _ = withUnsafeMutableBytes(of: &v){ptr in data.copyBytes(to:ptr,from:base..<base+4)}
                indices.append(Int(v))
            }
        }
        return indices
    }

    private func transformPoint(_ p: SIMD3<Float>, by m: SCNMatrix4) -> SIMD3<Float> {
        let x=m.m11*p.x+m.m21*p.y+m.m31*p.z+m.m41
        let y=m.m12*p.x+m.m22*p.y+m.m32*p.z+m.m42
        let z=m.m13*p.x+m.m23*p.y+m.m33*p.z+m.m43
        return SIMD3<Float>(x,y,z)
    }
}




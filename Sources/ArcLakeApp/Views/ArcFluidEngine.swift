import Foundation
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcFluidEngine — Arc Edge CFD: mesh-conformal SPH fluid dynamics.
//
// Physics references:
//   Müller, Charypar & Gross — SCA 2003 (SPH kernels)
//   https://matthias-research.github.io/pages/publications/sca03.pdf
//   Sebastian Lague — Fluid-Sim (MIT)
//   https://github.com/SebLague/Fluid-Sim
//   dartsolarpunk/Fluid-Sim · dartsolarpunk/fluid
//   https://sph-tutorial.physics-simulation.org/pdf/SPH_Tutorial.pdf
//   Ihmsen et al. 2012 — Spray Foam Bubbles (CGI)
//   https://cg.informatik.uni-freiburg.de/publications/2012_CGI_sprayFoamBubbles.pdf
//
//  Integrated: Radical Deepscale LLC / DART Meadow — Arc Edge CFD v2.0
// ═══════════════════════════════════════════════════════════════════

// MARK: — Fluid mode
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
    @Published public var particleCount = 500
    @Published public var gravityScale: Float = 1.0
    @Published public var smoothingH:   Float = 30.0
    @Published public var envTempK:     Float = 293    // from scene environment physics
    @Published public var envPressurePa: Float = 101325
    @Published public var measure     = ArcFluidMeasure()

    // Component material specs — one per mesh node in scene
    @Published public var componentSpecs: [ArcComponentSpec] = []

    // Domain — will be set from scene model bounding box
    var W: Float = 400; var H: Float = 300; var D: Float = 300
    let SCALE: Float = 0.8
    let VMAX:  Float = 35.0

    // Particles
    var pts: [ArcParticle] = []

    // Mesh collision geometry extracted from imported models
    private var meshTriangles: [ArcTriangle] = []
    private var meshBVH: [SIMD3<Float>] = []  // flat list of triangle centers for fast lookup

    // SceneKit node refs
    public weak var scene: SCNScene? = nil
    private var cloudNode: SCNNode? = nil

    // Spatial hash
    private var cells: [[Int]] = []
    private var cgx: Float=0, cgy: Float=0, cgz: Float=0
    private var cgW: Int=0, cgH: Int=0, cgD: Int=0

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

    // MARK: — SPH Kernels (Müller et al. SCA 2003)
    private var kSp2:Float=0, kSp3:Float=0, kSp2g:Float=0, kSp3g:Float=0, kP6:Float=0
    private var hCached:Float = -1
    private func rebuildKernels(_ h: Float) {
        let pi = Float.pi
        kSp2  = 15/(2*pi*pow(h,5)); kSp3  = 15/(pi*pow(h,6))
        kSp2g = 15/(pi*pow(h,5));   kSp3g = 45/(pi*pow(h,6))
        kP6   = 315/(64*pi*pow(h,9)); hCached = h
    }
    @inline(__always) private func sp2(_ d:Float,_ h:Float)->Float  { guard d<h else{return 0}; let v=h-d; return v*v*kSp2 }
    @inline(__always) private func sp3(_ d:Float,_ h:Float)->Float  { guard d<h else{return 0}; let v=h-d; return v*v*v*kSp3 }
    @inline(__always) private func dsp2(_ d:Float,_ h:Float)->Float { guard d<=h else{return 0}; return -(h-d)*kSp2g }
    @inline(__always) private func dsp3(_ d:Float,_ h:Float)->Float { guard d<=h else{return 0}; return -(h-d)*(h-d)*kSp3g }
    @inline(__always) private func p6(_ d2:Float,_ h:Float)->Float  { let v=h*h-d2; guard v>0 else{return 0}; return v*v*v*kP6 }

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

        // Initialize component specs for all mesh nodes
        scanComponentSpecs(scene)

        // Spawn particles
        let syms = elementSymbols.isEmpty ? ["O","H","H"] : elementSymbols
        spawnParticles(syms)
        buildCloudNode(scene)

        simTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                await self?.stepSPH()
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
                    let v0 = self.transformPoint(verts[i0], by: worldTx) * self.SCALE
                    let v1 = self.transformPoint(verts[i1], by: worldTx) * self.SCALE
                    let v2 = self.transformPoint(verts[i2], by: worldTx) * self.SCALE
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
        meshBVH = meshTriangles.map { $0.centroid }
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
            let sz = (mx - mn) / SCALE
            let pad: Float = 1.2
            W = max(200, sz.x * pad * 2)
            H = max(200, sz.y * pad * 2)
            D = max(200, sz.z * pad * 2)
        }
    }

    // MARK: — Scan component specs
    func scanComponentSpecs(_ scene: SCNScene) {
        var specs: [ArcComponentSpec] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let nm = node.name, node.geometry != nil,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud" else { return }
            var dname = nm
            for p in ["glb_import_","imported_"] where nm.hasPrefix(p) {
                dname = String(nm.dropFirst(p.count)); break
            }
            // Keep existing spec if already configured
            if let ex = self.componentSpecs.first(where:{$0.nodeName==nm}) {
                specs.append(ex)
            } else {
                specs.append(ArcComponentSpec(nodeName: nm, displayName: dname, alloy: .steel))
            }
        }
        componentSpecs = specs
    }

    // MARK: — Spawn particles
    private func spawnParticles(_ syms: [String]) {
        let n = particleCount
        let side = Int(ceil(pow(Double(n), 1.0/3.0)))
        let sp = min(smoothingH*0.6, (W*0.38)/Float(side), (H*0.88)/Float(side), (D*0.9)/Float(side))
        let x0: Float = W*0.04, y0: Float = H*0.06, z0: Float = (D-Float(side)*sp)/2
        pts.removeAll(keepingCapacity: true)
        var k = 0
        outer: for d in 0..<side {
            for row in 0..<side {
                for col in 0..<side {
                    guard k < n else { break outer }
                    let ai = k % syms.count; let c3 = colorFor(syms[ai])
                    var p = ArcParticle(x:x0+Float(col)*sp+Float.random(in: -0.5...0.5),
                                        y:y0+Float(row)*sp+Float.random(in: -0.5...0.5),
                                        z:z0+Float(d)*sp+Float.random(in: -0.5...0.5),
                                        vx:8, vy:0, vz:0,
                                        px:0, py:0, pz:0,
                                        dens:0, nDens:0, press:0, nPress:0,
                                        r:c3.x, g:c3.y, b:c3.z)
                    p.tempK = envTempK; k += 1; pts.append(p)
                }
            }
        }
    }

    public func setScene(_ preset: ArcFluidScene) {
        scenePreset = preset
        guard !pts.isEmpty else { return }
        reshapeToPreset(preset)
    }

    private func reshapeToPreset(_ preset: ArcFluidScene) {
        let n = pts.count; let h = smoothingH
        switch preset {
        case .dam:
            let side=Int(ceil(pow(Double(n),1.0/3.0)))
            let sp=min(h*0.6,(W*0.38)/Float(side),(H*0.88)/Float(side),(D*0.9)/Float(side))
            var k=0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k<n else { break outer }
                pts[k].x=W*0.04+Float(c)*sp+Float.random(in:-0.5...0.5)
                pts[k].y=H*0.06+Float(r)*sp+Float.random(in:-0.5...0.5)
                pts[k].z=(D-Float(side)*sp)/2+Float(d)*sp
                pts[k].vx=8; pts[k].vy=0; pts[k].vz=0; k+=1
            }}}
        case .wave:
            let side=Int(ceil(pow(Double(n),1.0/3.0))); var k=0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k<n else { break outer }
                let x=Float(c)*h*0.62+(W-Float(side)*h*0.62)/2
                pts[k].x=x; pts[k].y=Float(r)*h*0.31+H*0.06; pts[k].z=Float(d)*h*0.62+(D-Float(side)*h*0.62)/2
                pts[k].vx=exp(-(x/W)*5.5)*14; pts[k].vy=0; pts[k].vz=0; k+=1
            }}}
        case .drop:
            let pool=Int(Float(n)*0.72), dn=n-pool
            let side=Int(ceil(pow(Double(pool),1.0/3.0))); var k=0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k<pool else { break outer }
                pts[k].x=Float(c)*h*0.62+(W-Float(side)*h*0.62)/2+Float.random(in:-0.5...0.5)
                pts[k].y=Float(r)*h*0.19+H*0.06; pts[k].z=Float(d)*h*0.62+(D-Float(side)*h*0.62)/2
                pts[k].vx=0;pts[k].vy=0;pts[k].vz=0; k+=1
            }}}
            let ds=Int(ceil(pow(Double(dn),1.0/3.0)))
            let dx0=(W-Float(ds)*h*0.62)/2, dz0=(D-Float(ds)*h*0.62)/2; var dk=0
            outer2: for d in 0..<ds { for r in 0..<ds { for c in 0..<ds {
                guard dk<dn,k<n else { break outer2 }
                pts[k].x=dx0+Float(c)*h*0.62; pts[k].y=H*0.54+Float(r)*h*0.62
                pts[k].z=dz0+Float(d)*h*0.62; pts[k].vx=0;pts[k].vy = -10;pts[k].vz=0
                k+=1; dk+=1
            }}}
        case .orbital:
            for i in 0..<n {
                let theta=Float.random(in:0...2*Float.pi); let phi=acos(Float.random(in:-1...1))
                let r=W*(0.15+Float.random(in:0...0.25))
                pts[i].x=W/2+r*sin(phi)*cos(theta); pts[i].y=H/2+r*sin(phi)*sin(theta)*0.3; pts[i].z=D/2+r*cos(phi)
                let orbV=sqrt(max(0, 40/max(1,r)*1200))
                pts[i].vx = -sin(theta)*orbV; pts[i].vy=0; pts[i].vz=cos(theta)*orbV
            }
        case .stream:
            // Spawn near scene inlet component if designated
            let inletSpec = componentSpecs.first(where: { $0.isInlet })
            let startX: Float = inletSpec != nil ? W * 0.05 : W * 0.05
            for i in 0..<n {
                pts[i].x=startX+Float.random(in:0...smoothingH*2)
                pts[i].y=H/2+Float.random(in:-smoothingH...smoothingH)
                pts[i].z=D/2+Float.random(in:-smoothingH...smoothingH)
                pts[i].vx=Float(inletSpec?.inletFlowRate ?? 1.0)*12
                pts[i].vy=0; pts[i].vz=0
            }
        }
    }

    // MARK: — Spatial hash
    private func buildGrid() {
        let h=smoothingH; let n=pts.count; guard n>0 else { return }
        var mn=SIMD3<Float>(repeating:Float.infinity), mx=SIMD3<Float>(repeating:-Float.infinity)
        for p in pts {
            mn=simd_min(mn,SIMD3(p.px,p.py,p.pz)); mx=simd_max(mx,SIMD3(p.px,p.py,p.pz))
        }
        cgx=mn.x-h; cgy=mn.y-h; cgz=mn.z-h
        cgW=max(1,Int((mx.x-mn.x+2*h)/h)+1)
        cgH=max(1,Int((mx.y-mn.y+2*h)/h)+1)
        cgD=max(1,Int((mx.z-mn.z+2*h)/h)+1)
        let tot=cgW*cgH*cgD
        if cells.count != tot { cells=Array(repeating:[],count:tot) }
        else { for i in 0..<tot { cells[i].removeAll(keepingCapacity:true) } }
        for i in 0..<n {
            let cx=Int((pts[i].px-cgx)/h), cy=Int((pts[i].py-cgy)/h), cz=Int((pts[i].pz-cgz)/h)
            let idx=cx+cy*cgW+cz*cgW*cgH
            if idx>=0 && idx<tot { cells[idx].append(i) }
        }
    }

    private func neighbors(_ px:Float,_ py:Float,_ pz:Float) -> [Int] {
        let h=smoothingH
        let cx=Int((px-cgx)/h), cy=Int((py-cgy)/h), cz=Int((pz-cgz)/h)
        var result=[Int](); result.reserveCapacity(64)
        for oz in -1...1 { let nz=cz+oz; guard nz>=0&&nz<cgD else{continue}
            for oy in -1...1 { let ny=cy+oy; guard ny>=0&&ny<cgH else{continue}
                for ox in -1...1 { let nx=cx+ox; guard nx>=0&&nx<cgW else{continue}
                    result.append(contentsOf: cells[nx+ny*cgW+nz*cgW*cgH]) }}}
        return result
    }

    // MARK: — Mesh collision (particle vs triangle SDF)
    // Fast point-triangle distance + reflection for solid boundaries
    private func resolveTriangleCollision(_ i: Int) {
        guard !meshTriangles.isEmpty else { return }
        let pos = SIMD3<Float>(pts[i].x, pts[i].y, pts[i].z)
        let vel = SIMD3<Float>(pts[i].vx, pts[i].vy, pts[i].vz)
        let h = smoothingH * 0.4   // collision radius

        // Find nearby triangles using centroid proximity
        for (ti, ctr) in meshBVH.enumerated() {
            let dc = simd_distance(pos, ctr)
            guard dc < h * 8 else { continue }
            let tri = meshTriangles[ti]
            // Signed distance from point to triangle plane
            let toPoint = pos - tri.v0
            let sdist = simd_dot(toPoint, tri.normal)
            guard abs(sdist) < h else { continue }
            // Check if point projection is inside triangle
            guard pointInTriangle(pos, tri.v0, tri.v1, tri.v2, tri.normal) else { continue }
            // Reflect velocity off triangle surface
            let vDotN = simd_dot(vel, tri.normal)
            if vDotN < 0 {
                // Particle moving into the surface — reflect
                let refl = vel - 2 * vDotN * tri.normal
                let damp = mode.params.damp
                pts[i].vx = refl.x * damp; pts[i].vy = refl.y * damp; pts[i].vz = refl.z * damp
                // Push particle out of surface
                let pushDist = h - sdist + 0.01
                if pushDist > 0 {
                    pts[i].x += tri.normal.x * pushDist
                    pts[i].y += tri.normal.y * pushDist
                    pts[i].z += tri.normal.z * pushDist
                }
                // Thermal exchange: particle absorbs heat from component
                // Find which component this triangle belongs to
                // (approximate: check which nodeName the triangle's centroid is closest to)
                break
            }
        }
    }

    private func pointInTriangle(_ p: SIMD3<Float>,
                                  _ v0: SIMD3<Float>, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>,
                                  _ n: SIMD3<Float>) -> Bool {
        let e0=v1-v0, e1=v2-v1, e2=v0-v2
        let c0=p-v0, c1=p-v1, c2=p-v2
        return simd_dot(n,simd_cross(e0,c0)) >= 0 &&
               simd_dot(n,simd_cross(e1,c1)) >= 0 &&
               simd_dot(n,simd_cross(e2,c2)) >= 0
    }

    // MARK: — SPH step (Müller 2003 / SebLague port)
    nonisolated func stepSPH() async {
        await MainActor.run {
            guard isRunning, !pts.isEmpty else { return }
            let h = smoothingH
            let p = mode.params
            if h != hCached { rebuildKernels(h) }
            let dt: Float = 1.0
            let g = gravityScale * 0.25

            // ① Predict
            for i in 0..<pts.count {
                pts[i].vy -= g * dt
                pts[i].px = pts[i].x + pts[i].vx*dt*0.5
                pts[i].py = pts[i].y + pts[i].vy*dt*0.5
                pts[i].pz = pts[i].z + pts[i].vz*dt*0.5
            }

            // ② Hash
            buildGrid()

            // ③ Density
            var sumRho: Float=0, sumT: Float=0, maxP: Float=0
            for i in 0..<pts.count {
                var dens=sp2(0,h)+sp3(0,h), nDens=sp3(0,h)
                let nb=neighbors(pts[i].px,pts[i].py,pts[i].pz)
                for j in nb {
                    let dx=pts[i].px-pts[j].px, dy=pts[i].py-pts[j].py, dz=pts[i].pz-pts[j].pz
                    let d2=dx*dx+dy*dy+dz*dz; guard d2<h*h else { continue }
                    let d=sqrt(d2); dens+=sp2(d,h); nDens+=sp3(d,h)
                }
                pts[i].dens=dens; pts[i].nDens=nDens
                pts[i].press=(dens-p.rho)*p.pm; pts[i].nPress=nDens*p.npm
                // Thermal: density increases with pressure, raises temp slightly
                let pthermal = max(0, pts[i].press) * 0.0001
                pts[i].tempK = envTempK + pthermal
                pts[i].pressure = max(0, pts[i].press) * 10  // Pa (approximate)
                sumRho+=dens; sumT+=pts[i].tempK
                maxP = max(maxP, pts[i].pressure)
            }

            // ④ Pressure forces
            for i in 0..<pts.count {
                var fx:Float=0, fy:Float=0, fz:Float=0
                let nb=neighbors(pts[i].px,pts[i].py,pts[i].pz)
                for j in nb {
                    guard j != i else { continue }
                    let dx=pts[i].px-pts[j].px, dy=pts[i].py-pts[j].py, dz=pts[i].pz-pts[j].pz
                    let d2=dx*dx+dy*dy+dz*dz; guard d2<h*h && d2>1e-6 else { continue }
                    let dist=sqrt(d2), invD=1/dist
                    let nx=dx*invD, ny=dy*invD, nz=dz*invD
                    let sP=(pts[i].press+pts[j].press)*0.5
                    let snP=(pts[i].nPress+pts[j].nPress)*0.5
                    let rhoj=max(0.001,pts[j].dens)
                    let fmag=sP*dsp2(dist,h)*0.0016/rhoj+snP*dsp3(dist,h)*0.0006/rhoj
                    fx+=nx*fmag; fy+=ny*fmag; fz+=nz*fmag
                }
                pts[i].vx+=fx*dt; pts[i].vy+=fy*dt; pts[i].vz+=fz*dt
            }

            // ⑤ Viscosity (Müller Eq.14)
            for i in 0..<pts.count {
                var dvx:Float=0, dvy:Float=0, dvz:Float=0
                let nb=neighbors(pts[i].px,pts[i].py,pts[i].pz)
                for j in nb {
                    guard j != i else { continue }
                    let dx=pts[i].px-pts[j].px, dy=pts[i].py-pts[j].py, dz=pts[i].pz-pts[j].pz
                    let d2=dx*dx+dy*dy+dz*dz; guard d2<h*h else { continue }
                    let w=p6(d2,h)*p.visc*0.00028
                    dvx+=(pts[j].vx-pts[i].vx)*w
                    dvy+=(pts[j].vy-pts[i].vy)*w
                    dvz+=(pts[j].vz-pts[i].vz)*w
                }
                pts[i].vx+=dvx*dt; pts[i].vy+=dvy*dt; pts[i].vz+=dvz*dt
            }

            // ⑥ Integrate + AABB + mesh collision
            let damp=p.damp; var totalKE:Float=0, totalSpd:Float=0
            var inCount:Float=0, outCount:Float=0
            let inletSpec  = componentSpecs.first(where:{$0.isInlet})
            let outletSpec = componentSpecs.first(where:{$0.isOutlet})

            for i in 0..<pts.count {
                let spd=sqrt(pts[i].vx*pts[i].vx+pts[i].vy*pts[i].vy+pts[i].vz*pts[i].vz)
                if spd>VMAX { let inv=VMAX/spd; pts[i].vx*=inv;pts[i].vy*=inv;pts[i].vz*=inv }
                pts[i].spd=spd; totalSpd+=spd; totalKE+=0.5*spd*spd
                pts[i].x+=pts[i].vx*dt; pts[i].y+=pts[i].vy*dt; pts[i].z+=pts[i].vz*dt

                // AABB bounds
                if pts[i].x<0{pts[i].x=0;pts[i].vx=abs(pts[i].vx)*damp}
                if pts[i].x>W{pts[i].x=W;pts[i].vx = -abs(pts[i].vx)*damp}
                if pts[i].y<0{pts[i].y=0;pts[i].vy=abs(pts[i].vy)*damp}
                if pts[i].y>H{pts[i].y=H;pts[i].vy = -abs(pts[i].vy)*damp}
                if pts[i].z<0{pts[i].z=0;pts[i].vz=abs(pts[i].vz)*damp}
                if pts[i].z>D{pts[i].z=D;pts[i].vz = -abs(pts[i].vz)*damp}

                // Mesh collision
                resolveTriangleCollision(i)

                // Inlet re-inject (Stream mode: respawn at inlet when reaching outlet)
                if scenePreset == .stream, let inSpec = inletSpec {
                    if pts[i].x > W*0.9 {  // reached outlet end
                        pts[i].x = W*0.05+Float.random(in:0...smoothingH)
                        pts[i].y = H/2+Float.random(in:-smoothingH*0.5...smoothingH*0.5)
                        pts[i].z = D/2+Float.random(in:-smoothingH*0.5...smoothingH*0.5)
                        pts[i].vx = Float(inSpec.inletFlowRate)*12
                        pts[i].vy = 0; pts[i].vz = 0
                        outCount += 1
                    }
                    inCount += pts[i].x < W*0.15 ? 1 : 0
                }
            }

            // Update thermal colormap on scene meshes
            if scene != nil { updateThermalColormap(sumT: sumT, maxP: maxP) }

            // Update per-component measurements
            updateComponentMeasurements(maxP: maxP)

            // Upload to SceneKit
            uploadParticleCloud()

            let n = pts.count; let avgSpd = n>0 ? totalSpd/Float(n) : 0
            let avgRho = n>0 ? sumRho/Float(n) : 0; let avgT = n>0 ? sumT/Float(n) : envTempK
            let L: Float = pow(W*H*D, 1.0/3.0)*SCALE*0.01
            let mu = max(1e-6, p.visc*0.001)
            let Re = (avgRho*avgSpd*L)/mu
            measure = ArcFluidMeasure(
                avgDensity:avgRho, avgSpeed:avgSpd, avgTempK:avgT,
                reynoldsNum:Re, regime:Re<2300 ? "Laminar":Re<4000 ? "Transitional":"Turbulent",
                particleCount:n, inletFlow:inCount, outletFlow:outCount,
                totalKE:totalKE, maxPressurePa:maxP)
        }
    }

    // MARK: — Thermal colormap on 3D model surface
    private func updateThermalColormap(sumT: Float, maxP: Float) {
        guard let scene else { return }
        // Sample max temperature near each mesh node
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let nm = node.name, node.geometry != nil,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud" else { return }
            let worldPos = node.worldPosition
            // Find max temp/pressure of particles near this node
            var nearMaxT: Float = self.envTempK; var nearMaxP: Float = 0
            let searchR: Float = self.smoothingH * 4
            for p in self.pts {
                let dx = p.x*self.SCALE - worldPos.x
                let dy = p.y*self.SCALE - worldPos.y
                let dz = p.z*self.SCALE - worldPos.z
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
            let r = smoothingH * 3
            for p in pts {
                let dx=p.x*SCALE-wpos.x, dy=p.y*SCALE-wpos.y, dz=p.z*SCALE-wpos.z
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
        let offX=W*SCALE/2, offY=H*SCALE/2-22, offZ=D*SCALE/2
        var rawPos=[Float](); rawPos.reserveCapacity(n*3)
        var rawCol=[Float](); rawCol.reserveCapacity(n*4)
        for p in pts {
            rawPos += [p.x*SCALE-offX, p.y*SCALE-offY, p.z*SCALE-offZ]
            // Color: CPK base tinted toward thermal
            let heat = min(1, max(0,(p.tempK-envTempK)/max(1,2000-envTempK)))
            let hc = thermalColor(heat)
            rawCol += [p.r*(1-heat*0.6)+hc.x*heat*0.6,
                       p.g*(1-heat*0.6)+hc.y*heat*0.6,
                       p.b*(1-heat*0.6)+hc.z*heat*0.6, 0.92]
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
        elem.pointSize=4; elem.minimumPointScreenSpaceRadius=1; elem.maximumPointScreenSpaceRadius=10
        let geo=SCNGeometry(sources:[posSource,colSource], elements:[elem])
        let mat=SCNMaterial(); mat.lightingModel = .constant
        geo.firstMaterial=mat
        cloudNode.geometry=geo
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

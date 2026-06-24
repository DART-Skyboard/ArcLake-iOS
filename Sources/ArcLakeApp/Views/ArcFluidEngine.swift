import Foundation
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcFluidEngine — iOS Swift port of the ArcLake SPH fluid simulation.
//
// Physics kernel mathematics from:
//   • Müller, Charypar & Gross — "Particle-Based Fluid Simulation for
//     Interactive Applications", SCA 2003
//     https://matthias-research.github.io/pages/publications/sca03.pdf
//   • Sebastian Lague — Fluid-Sim (MIT License)
//     https://github.com/SebLague/Fluid-Sim
//   • SPH Tutorial — physics-simulation.org
//     https://sph-tutorial.physics-simulation.org/pdf/SPH_Tutorial.pdf
//   • Clavet, Beaudoin & Poulin — Particle-based Viscoelastic Fluid
//
// Integrated into ArcLake iOS by Justin / DART-Skyboard · Radical Deepscale LLC
// ═══════════════════════════════════════════════════════════════════

// MARK: — Fluid mode
public enum ArcFluidMode: String, CaseIterable, Identifiable {
    case liquid   = "Liquid"
    case gas      = "Gas"
    case viscous  = "Viscous"
    case granular = "Granular"
    public var id: String { rawValue }

    /// SPH parameter presets for each mode
    var params: ArcFluidParams {
        switch self {
        case .liquid:   return ArcFluidParams(rho:650, pm:220, npm:5.0, visc:0.055, damp:0.72, grav:1.0)
        case .gas:      return ArcFluidParams(rho:120, pm:80,  npm:1.2, visc:0.008, damp:0.55, grav:0.15)
        case .viscous:  return ArcFluidParams(rho:900, pm:340, npm:8.0, visc:0.35,  damp:0.85, grav:1.0)
        case .granular: return ArcFluidParams(rho:800, pm:280, npm:6.5, visc:0.18,  damp:0.90, grav:1.0)
        }
    }
}

public struct ArcFluidParams {
    var rho:  Float   // rest density
    var pm:   Float   // pressure multiplier
    var npm:  Float   // near-pressure multiplier
    var visc: Float   // viscosity coefficient
    var damp: Float   // boundary damping
    var grav: Float   // gravity scale
}

// MARK: — Scene preset
public enum ArcFluidScene: String, CaseIterable, Identifiable {
    case dam = "Dam", wave = "Wave", drop = "Drop", orbital = "Orbital", stream = "Stream"
    public var id: String { rawValue }
}

// MARK: — Particle
struct SPHParticle {
    var x, y, z:       Float
    var vx, vy, vz:    Float
    var px, py, pz:    Float  // predicted position
    var dens, nDens:   Float
    var press, nPress: Float
    var r, g, b:       Float  // CPK color
    var spd:           Float
    var elemIdx:       Int    // index into element array

    init(x:Float,y:Float,z:Float,vx:Float=0,vy:Float=0,vz:Float=0,
         r:Float=1,g:Float=1,b:Float=1, elemIdx:Int=0) {
        self.x=x; self.y=y; self.z=z
        self.vx=vx; self.vy=vy; self.vz=vz
        self.px=x; self.py=y; self.pz=z
        self.dens=0; self.nDens=0; self.press=0; self.nPress=0
        self.r=r; self.g=g; self.b=b; self.spd=0; self.elemIdx=elemIdx
    }
}

// MARK: — Arc Edge fluid measurement
public struct ArcFluidMeasure {
    public var avgDensity:    Float = 0
    public var avgSpeed:      Float = 0
    public var reynoldsNum:   Float = 0
    public var regime:        String = "—"
    public var particleCount: Int   = 0
    public var inletFlow:     Float = 0
    public var outletFlow:    Float = 0
    public var totalKE:       Float = 0
}

// MARK: — Main engine
@MainActor
public final class ArcFluidEngine: ObservableObject {
    public static let shared = ArcFluidEngine()

    @Published public var isRunning   = false
    @Published public var mode        = ArcFluidMode.liquid
    @Published public var scenePreset = ArcFluidScene.dam
    @Published public var particleCount: Int = 600
    @Published public var gravityScale: Float = 1.0
    @Published public var smoothingH:   Float = 30.0
    @Published public var measure = ArcFluidMeasure()

    // SPH domain (scene units)
    let W: Float = 400, H: Float = 300, D: Float = 300
    let SCALE: Float = 0.8
    let VMAX:  Float = 30.0

    // Particles
    private var pts: [SPHParticle] = []

    // Kernel constants
    private var kSp2: Float = 0
    private var kSp3: Float = 0
    private var kSp2g: Float = 0
    private var kSp3g: Float = 0
    private var kP6:  Float = 0
    private var hCached: Float = -1

    // Spatial hash
    private var cells: [[Int]] = []
    private var cgx: Float = 0, cgy: Float = 0, cgz: Float = 0
    private var cgW: Int = 0, cgH: Int = 0, cgD: Int = 0
    private var cellSize: Float = 0

    // Three.js scene ref (for SceneKit)
    public weak var scene: SCNScene? = nil
    private var pointsNode: SCNNode? = nil
    private var geom: SCNGeometry? = nil
    private var positions: [SCNVector3] = []
    private var colors: [SIMD4<Float>] = []

    // Inlet/outlet zones set from mesh selector
    public var inletZone:  SIMD3<Float>? = nil
    public var outletZone: SIMD3<Float>? = nil
    public var inletRadius:  Float = 40
    public var outletRadius: Float = 40

    // Background simulation thread
    private var simTask: Task<Void,Never>? = nil

    // MARK: — CPK Element Colors
    private let elemColors: [String: SIMD3<Float>] = [
        "H":  [1,1,1],       "He": [0.85,1,1],
        "Li": [0.8,0.5,1],   "Be": [0.76,1,0],
        "B":  [1,0.71,0.71], "C":  [0.56,0.56,0.56],
        "N":  [0.19,0.31,0.97],"O": [1,0.05,0.05],
        "F":  [0.56,0.82,0.31],"Ne":[0.7,0.89,0.96],
        "Na": [0.67,0.36,0.95],"Mg":[0.54,1,0],
        "Si": [0.94,0.78,0.63],"P": [1,0.5,0],
        "S":  [1,1,0.19],    "Cl": [0.12,0.94,0.12],
        "K":  [0.56,0.25,0.83],"Ca":[0.24,1,0],
        "Fe": [0.88,0.4,0.2], "Cu": [0.78,0.5,0.2],
        "Au": [1,0.82,0.14],  "Ag": [0.75,0.75,0.75],
    ]

    func colorFor(_ sym: String) -> SIMD3<Float> {
        if let c = elemColors[sym] { return c }
        var h: UInt32 = 0
        for ch in sym.unicodeScalars { h = h &* 31 &+ ch.value }
        let hue = Float(h & 0xffff) / 65535.0 * 360
        return hsvToRgb(hue, 0.85, 0.85)
    }

    private func hsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let c = v*s, x = c*(1-abs(fmod(h/60,2)-1)), m = v-c
        var r:Float=0,g:Float=0,b:Float=0
        switch Int(h/60) {
        case 0: r=c;g=x;b=0; case 1: r=x;g=c;b=0; case 2: r=0;g=c;b=x
        case 3: r=0;g=x;b=c; case 4: r=x;g=0;b=c; default: r=c;g=0;b=x
        }
        return SIMD3<Float>(r+m,g+m,b+m)
    }

    // MARK: — Kernel functions (Müller 2003 / SebLague port)
    private func recomputeKernels(_ h: Float) {
        let PI = Float.pi
        let h5 = pow(h,5), h6 = pow(h,6), h9 = pow(h,9)
        kSp2  = 15 / (2*PI*h5)
        kSp3  = 15 / (  PI*h6)
        kSp2g = 15 / (  PI*h5)
        kSp3g = 45 / (  PI*h6)
        kP6   = 315 / (64*PI*h9)
        hCached = h
    }
    private func sp2(_ d: Float, _ h: Float) -> Float  {
        guard d < h else { return 0 }; let v = h-d; return v*v*kSp2 }
    private func sp3(_ d: Float, _ h: Float) -> Float  {
        guard d < h else { return 0 }; let v = h-d; return v*v*v*kSp3 }
    private func dsp2(_ d: Float, _ h: Float) -> Float {
        guard d <= h else { return 0 }; return -(h-d)*kSp2g }
    private func dsp3(_ d: Float, _ h: Float) -> Float {
        guard d <= h else { return 0 }; return -(h-d)*(h-d)*kSp3g }
    private func p6(_ d2: Float, _ h: Float) -> Float  {
        let v = h*h-d2; guard v > 0 else { return 0 }; return v*v*v*kP6 }

    // MARK: — Start / Stop
    public func start(in scene: SCNScene, elementSymbols: [String] = ["O","H","H"]) {
        guard !isRunning else { return }
        self.scene = scene
        isRunning = true
        let syms = elementSymbols.isEmpty ? ["H"] : elementSymbols
        spawnParticles(syms)
        buildSceneKitGeometry(scene)
        simTask = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                await self?.stepSPH()
                await self?.uploadToSceneKit()
                try? await Task.sleep(nanoseconds: 16_666_667)  // ~60fps
            }
        }
    }

    public func stop() {
        simTask?.cancel(); simTask = nil
        isRunning = false
        pointsNode?.removeFromParentNode(); pointsNode = nil
    }

    public func setScene(_ preset: ArcFluidScene) {
        scenePreset = preset
        let syms = pts.isEmpty ? ["H"] : []
        if !pts.isEmpty { reshapeParticles(preset) }
    }

    // MARK: — Particle spawn
    private func spawnParticles(_ syms: [String]) {
        let p = mode.params
        let n = particleCount
        let side = Int(ceil(pow(Double(n), 1.0/3.0)))
        let sp = min(smoothingH * 0.6, (W*0.38)/Float(side), (H*0.88)/Float(side), (D*0.9)/Float(side))
        let x0: Float = W*0.04, y0: Float = H*0.06, z0: Float = (D - Float(side)*sp)/2
        pts.removeAll(keepingCapacity: true)
        var k = 0
        outer: for d in 0..<side {
            for row in 0..<side {
                for col in 0..<side {
                    guard k < n else { break outer }
                    let ai = k % syms.count
                    let col3 = colorFor(syms[ai])
                    pts.append(SPHParticle(
                        x: x0 + Float(col)*sp + Float.random(in: -0.5...0.5),
                        y: y0 + Float(row)*sp + Float.random(in: -0.5...0.5),
                        z: z0 + Float(d)*sp   + Float.random(in: -0.5...0.5),
                        vx: 8, vy: 0, vz: 0,
                        r: col3.x, g: col3.y, b: col3.z, elemIdx: ai))
                    k += 1
                }
            }
        }
    }

    private func reshapeParticles(_ preset: ArcFluidScene) {
        let n = pts.count
        let h = smoothingH
        switch preset {
        case .dam:
            let side = Int(ceil(pow(Double(n), 1.0/3.0)))
            let sp = min(h*0.6, (W*0.38)/Float(side), (H*0.88)/Float(side), (D*0.9)/Float(side))
            var k = 0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k < n else { break outer }
                pts[k].x = W*0.04+Float(c)*sp+Float.random(in: -0.5...0.5)
                pts[k].y = H*0.06+Float(r)*sp+Float.random(in: -0.5...0.5)
                pts[k].z = (D-Float(side)*sp)/2+Float(d)*sp+Float.random(in: -0.5...0.5)
                pts[k].vx = 8; pts[k].vy = 0; pts[k].vz = 0; k += 1
            }}}
        case .wave:
            let side = Int(ceil(pow(Double(n), 1.0/3.0))); var k = 0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k < n else { break outer }
                let x = Float(c)*h*0.62 + (W-Float(side)*h*0.62)/2
                let y = Float(r)*h*0.62*0.5 + H*0.06
                let z = Float(d)*h*0.62 + (D-Float(side)*h*0.62)/2
                pts[k].x=x+Float.random(in: -0.5...0.5); pts[k].y=y; pts[k].z=z+Float.random(in: -0.5...0.5)
                pts[k].vx = exp(-(x/W)*5.5)*14; pts[k].vy=0; pts[k].vz=0; k += 1
            }}}
        case .drop:
            let pool = Int(Float(n)*0.72), dropN = n - pool
            let side = Int(ceil(pow(Double(pool), 1.0/3.0))); var k = 0
            outer: for d in 0..<side { for r in 0..<side { for c in 0..<side {
                guard k < pool else { break outer }
                pts[k].x=Float(c)*h*0.62+(W-Float(side)*h*0.62)/2+Float.random(in: -0.5...0.5)
                pts[k].y=Float(r)*h*0.62*0.3+H*0.06; pts[k].z=Float(d)*h*0.62+(D-Float(side)*h*0.62)/2+Float.random(in: -0.5...0.5)
                pts[k].vx=0;pts[k].vy=0;pts[k].vz=0; k += 1
            }}}
            let ds = Int(ceil(pow(Double(dropN),1.0/3.0)))
            let dx0=(W-Float(ds)*h*0.62)/2, dz0=(D-Float(ds)*h*0.62)/2; var dk=0
            outer2: for d in 0..<ds { for r in 0..<ds { for c in 0..<ds {
                guard dk < dropN, k < n else { break outer2 }
                pts[k].x=dx0+Float(c)*h*0.62; pts[k].y=H*0.54+Float(r)*h*0.62
                pts[k].z=dz0+Float(d)*h*0.62; pts[k].vx=0;pts[k].vy = -10;pts[k].vz=0
                k += 1; dk += 1
            }}}
        case .orbital:
            for i in 0..<n {
                let theta = Float.random(in: 0...2*Float.pi)
                let phi   = acos(Float.random(in: -1...1))
                let r     = W*(0.15 + Float.random(in: 0...0.25))
                pts[i].x = W/2 + r*sin(phi)*cos(theta)
                pts[i].y = H/2 + r*sin(phi)*sin(theta)*0.3
                pts[i].z = D/2 + r*cos(phi)
                let orbV  = sqrt(max(0, 40/max(1,r)*1200))
                pts[i].vx = -sin(theta)*orbV; pts[i].vy=0; pts[i].vz=cos(theta)*orbV
            }
        case .stream:
            // Continuous stream through inlet zone (if defined)
            for i in 0..<n {
                let inlet = inletZone ?? SIMD3<Float>(W*0.05, H/2, D/2)
                pts[i].x = inlet.x + Float.random(in: -inletRadius*0.3...inletRadius*0.3)
                pts[i].y = inlet.y + Float.random(in: -inletRadius*0.3...inletRadius*0.3)
                pts[i].z = inlet.z + Float.random(in: -inletRadius*0.3...inletRadius*0.3)
                pts[i].vx = 12; pts[i].vy=0; pts[i].vz=0
            }
        }
    }

    // MARK: — Spatial hash
    private func buildGrid() {
        let h = smoothingH; let n = pts.count; guard n > 0 else { return }
        var mx:Float = .infinity, my:Float = .infinity, mz:Float = .infinity
        var Mx:Float = -.infinity, My:Float = -.infinity, Mz:Float = -.infinity
        for p in pts {
            mx=min(mx,p.px); my=min(my,p.py); mz=min(mz,p.pz)
            Mx=max(Mx,p.px); My=max(My,p.py); Mz=max(Mz,p.pz)
        }
        cgx=mx-h; cgy=my-h; cgz=mz-h; cellSize=h
        cgW=max(1,Int(ceil((Mx-mx+2*h)/h))+1)
        cgH=max(1,Int(ceil((My-my+2*h)/h))+1)
        cgD=max(1,Int(ceil((Mz-mz+2*h)/h))+1)
        let tot = cgW*cgH*cgD
        if cells.count != tot { cells = Array(repeating:[], count:tot) }
        else { for i in 0..<tot { cells[i].removeAll(keepingCapacity:true) } }
        for i in 0..<n {
            let cx=Int((pts[i].px-cgx)/cellSize), cy=Int((pts[i].py-cgy)/cellSize)
            let cz=Int((pts[i].pz-cgz)/cellSize)
            let idx = cx + cy*cgW + cz*cgW*cgH
            if idx >= 0 && idx < tot { cells[idx].append(i) }
        }
    }

    private func neighbors(_ px:Float,_ py:Float,_ pz:Float) -> [Int] {
        let cx=Int((px-cgx)/cellSize), cy=Int((py-cgy)/cellSize), cz=Int((pz-cgz)/cellSize)
        var result: [Int] = []
        for oz in -1...1 { let nz=cz+oz; guard nz>=0 && nz<cgD else { continue }
            for oy in -1...1 { let ny=cy+oy; guard ny>=0 && ny<cgH else { continue }
                for ox in -1...1 { let nx=cx+ox; guard nx>=0 && nx<cgW else { continue }
                    let idx = nx + ny*cgW + nz*cgW*cgH
                    result.append(contentsOf: cells[idx]) }}}
        return result
    }

    // MARK: — SPH step (matches arclake.html _cfdSPHStep exactly)
    nonisolated func stepSPH() async {
        await MainActor.run {
            guard isRunning, !pts.isEmpty else { return }
            let h = smoothingH
            let params = mode.params
            if h != hCached { recomputeKernels(h) }
            let dt: Float = 1.0
            let g = params.grav * gravityScale * 0.25

            // ① Predict
            for i in 0..<pts.count {
                pts[i].vy -= g * dt
                pts[i].px = pts[i].x + pts[i].vx * dt * 0.5
                pts[i].py = pts[i].y + pts[i].vy * dt * 0.5
                pts[i].pz = pts[i].z + pts[i].vz * dt * 0.5
            }

            // ② Build spatial hash
            buildGrid()

            // ③ Density
            var sumRho: Float = 0
            for i in 0..<pts.count {
                var dens  = sp2(0, h) + sp3(0, h)
                var nDens = sp3(0, h)
                let nb = neighbors(pts[i].px, pts[i].py, pts[i].pz)
                for j in nb {
                    let dx=pts[i].px-pts[j].px, dy=pts[i].py-pts[j].py, dz=pts[i].pz-pts[j].pz
                    let d2=dx*dx+dy*dy+dz*dz; guard d2<h*h else { continue }
                    let d=sqrt(d2); dens+=sp2(d,h); nDens+=sp3(d,h)
                }
                pts[i].dens = dens; pts[i].nDens = nDens
                pts[i].press  = (dens - params.rho) * params.pm
                pts[i].nPress = nDens * params.npm
                sumRho += dens
            }

            // ④ Pressure forces
            for i in 0..<pts.count {
                var fx:Float=0, fy:Float=0, fz:Float=0
                let nb = neighbors(pts[i].px, pts[i].py, pts[i].pz)
                for j in nb {
                    guard j != i else { continue }
                    let dx=pts[i].px-pts[j].px, dy=pts[i].py-pts[j].py, dz=pts[i].pz-pts[j].pz
                    let d2=dx*dx+dy*dy+dz*dz; guard d2<h*h && d2>1e-6 else { continue }
                    let dist=sqrt(d2), invD=1/dist
                    let nx=dx*invD, ny=dy*invD, nz=dz*invD
                    let sP=(pts[i].press+pts[j].press)*0.5
                    let snP=(pts[i].nPress+pts[j].nPress)*0.5
                    let rhoj=max(0.001, pts[j].dens)
                    let fmag = sP*dsp2(dist,h)*0.0016/rhoj + snP*dsp3(dist,h)*0.0006/rhoj
                    fx+=nx*fmag; fy+=ny*fmag; fz+=nz*fmag
                }
                pts[i].vx+=fx*dt; pts[i].vy+=fy*dt; pts[i].vz+=fz*dt
            }

            // ⑤ Viscosity (Müller 2003 Eq.14)
            for i in 0..<pts.count {
                var dvx:Float=0, dvy:Float=0, dvz:Float=0
                let nb = neighbors(pts[i].px, pts[i].py, pts[i].pz)
                for j in nb {
                    guard j != i else { continue }
                    let dx=pts[i].px-pts[j].px, dy=pts[i].py-pts[j].py, dz=pts[i].pz-pts[j].pz
                    let d2=dx*dx+dy*dy+dz*dz; guard d2<h*h else { continue }
                    let w = p6(d2, h) * params.visc * 0.00028
                    dvx += (pts[j].vx-pts[i].vx)*w
                    dvy += (pts[j].vy-pts[i].vy)*w
                    dvz += (pts[j].vz-pts[i].vz)*w
                }
                pts[i].vx+=dvx*dt; pts[i].vy+=dvy*dt; pts[i].vz+=dvz*dt
            }

            // ⑥ Integrate + AABB boundary (Lague ResolveCollisions)
            let damp = params.damp
            var totalKE: Float = 0; var totalSpd: Float = 0
            var inletCount: Int = 0; var outletCount: Int = 0
            for i in 0..<pts.count {
                let spd=sqrt(pts[i].vx*pts[i].vx+pts[i].vy*pts[i].vy+pts[i].vz*pts[i].vz)
                if spd > VMAX { let inv=VMAX/spd; pts[i].vx*=inv; pts[i].vy*=inv; pts[i].vz*=inv }
                pts[i].spd = spd; totalSpd += spd; totalKE += 0.5*spd*spd
                pts[i].x+=pts[i].vx*dt; pts[i].y+=pts[i].vy*dt; pts[i].z+=pts[i].vz*dt
                // Boundary
                if pts[i].x<0 { pts[i].x=0; pts[i].vx=abs(pts[i].vx)*damp }
                if pts[i].x>W { pts[i].x=W; pts[i].vx = -abs(pts[i].vx)*damp }
                if pts[i].y<0 { pts[i].y=0; pts[i].vy=abs(pts[i].vy)*damp }
                if pts[i].y>H { pts[i].y=H; pts[i].vy = -abs(pts[i].vy)*damp }
                if pts[i].z<0 { pts[i].z=0; pts[i].vz=abs(pts[i].vz)*damp }
                if pts[i].z>D { pts[i].z=D; pts[i].vz = -abs(pts[i].vz)*damp }
                // Inlet/outlet flow measurement (Arc Edge measurement)
                if let iz = inletZone {
                    let dx=pts[i].x-iz.x, dy=pts[i].y-iz.y, dz=pts[i].z-iz.z
                    if sqrt(dx*dx+dy*dy+dz*dz) < inletRadius { inletCount += 1 }
                }
                if let oz = outletZone {
                    let dx=pts[i].x-oz.x, dy=pts[i].y-oz.y, dz=pts[i].z-oz.z
                    if sqrt(dx*dx+dy*dy+dz*dz) < outletRadius { outletCount += 1 }
                }
            }
            let n = pts.count
            let avgSpd = n > 0 ? totalSpd / Float(n) : 0
            let avgRho = n > 0 ? sumRho / Float(n) : 0
            // Reynolds number: Re = ρ·v·L / μ  (L = domain char length)
            let L: Float = pow(W*H*D, 1.0/3.0) * SCALE * 0.01   // meters
            let mu = max(1e-6, params.visc * 0.001)
            let Re = (avgRho * avgSpd * L) / mu
            measure = ArcFluidMeasure(
                avgDensity: avgRho, avgSpeed: avgSpd, reynoldsNum: Re,
                regime: Re < 2300 ? "Laminar" : Re < 4000 ? "Transitional" : "Turbulent",
                particleCount: n, inletFlow: Float(inletCount), outletFlow: Float(outletCount),
                totalKE: totalKE)
        }
    }

    // MARK: — SceneKit geometry (instanced point cloud)
    private func buildSceneKitGeometry(_ scene: SCNScene) {
        pointsNode?.removeFromParentNode()
        let n = pts.count
        positions = Array(repeating: SCNVector3Zero, count: n)
        colors    = Array(repeating: SIMD4<Float>(1,1,1,1), count: n)
        // Build geometry sources
        updatePositionArray()
        let posSource = SCNGeometrySource(
            data: Data(bytes: positions, count: n * MemoryLayout<SCNVector3>.stride),
            semantic: .vertex, vectorCount: n, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.stride)
        let colData: [Float] = colors.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        let colSource = SCNGeometrySource(
            data: Data(bytes: colData, count: colData.count * MemoryLayout<Float>.size),
            semantic: .color, vectorCount: n, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: 4 * MemoryLayout<Float>.size)
        let indices = Array(0..<n).map { UInt32($0) }
        let elem = SCNGeometryElement(indices: indices, primitiveType: .point)
        elem.pointSize = 4
        elem.minimumPointScreenSpaceRadius = 1
        elem.maximumPointScreenSpaceRadius = 8
        let geo = SCNGeometry(sources: [posSource, colSource], elements: [elem])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.transparencyMode = .default
        geo.firstMaterial = mat
        geom = geo
        let node = SCNNode(geometry: geo)
        node.name = "arcFluidCloud"
        scene.rootNode.addChildNode(node)
        pointsNode = node
    }

    // Upload particle positions to SceneKit geometry each tick
    nonisolated func uploadToSceneKit() async {
        await MainActor.run {
            guard isRunning, !pts.isEmpty, let scene else { return }
            if pointsNode == nil { buildSceneKitGeometry(scene) }
            // Rebuild geometry with current positions + colors
            let n = pts.count
            let offX = W * SCALE / 2, offY = H * SCALE / 2 - 22, offZ = D * SCALE / 2
            var rawPos = [Float](); rawPos.reserveCapacity(n*3)
            var rawCol = [Float](); rawCol.reserveCapacity(n*4)
            for p in pts {
                rawPos.append(p.x*SCALE - offX)
                rawPos.append(p.y*SCALE - offY)
                rawPos.append(p.z*SCALE - offZ)
                rawCol.append(p.r); rawCol.append(p.g); rawCol.append(p.b); rawCol.append(0.92)
            }
            let posSource = SCNGeometrySource(
                data: Data(bytes: rawPos, count: rawPos.count * MemoryLayout<Float>.size),
                semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0, dataStride: 3 * MemoryLayout<Float>.size)
            let colSource = SCNGeometrySource(
                data: Data(bytes: rawCol, count: rawCol.count * MemoryLayout<Float>.size),
                semantic: .color, vectorCount: n, usesFloatComponents: true,
                componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0, dataStride: 4 * MemoryLayout<Float>.size)
            let indices = (0..<n).map { UInt32($0) }
            let elem = SCNGeometryElement(indices: indices, primitiveType: .point)
            elem.pointSize = 4
            elem.minimumPointScreenSpaceRadius = 1
            elem.maximumPointScreenSpaceRadius = 8
            let geo = SCNGeometry(sources: [posSource, colSource], elements: [elem])
            geo.firstMaterial = geom?.firstMaterial
            pointsNode?.geometry = geo
            geom = geo
        }
    }

    private func updatePositionArray() {
        let offX = W*SCALE/2, offY = H*SCALE/2 - 22, offZ = D*SCALE/2
        for i in 0..<pts.count {
            positions[i] = SCNVector3(pts[i].x*SCALE - offX,
                                      pts[i].y*SCALE - offY,
                                      pts[i].z*SCALE - offZ)
            colors[i] = SIMD4<Float>(pts[i].r, pts[i].g, pts[i].b, 0.92)
        }
    }
}

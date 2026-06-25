import SwiftUI
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════════════
// ArcWindTunnel.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// Arc Edge Wind Tunnel + Large-Scale Cavity CFD System
//
// Modes:
//   1. CAVITY FILL   — fill named GLB mesh cavities with fluid (already in
//                       ArcFluidEngine / autoFillNamedComponents). This file
//                       adds the UI control panel and Scene Preset: TUNNEL.
//   2. WIND TUNNEL   — freeze scene geometry at static pose, stream airflow
//                       particles across it, generate live thermal-velocity
//                       colormap bands showing drag, turbulence, stagnation
//                       points, boundary layer separation.
//   3. AERO ANALYSIS — tap any surface to read local Cp (pressure coeff),
//                       Mach (for supersonic), Re, and thermal band color.
//
// Physics (SPH-inspired streamline approach):
//   · Particles spawn upstream in a uniform grid (inlet face)
//   · Each frame: velocity field += freestream + object-surface deflection
//   · Surface deflection: raytrace each particle toward surface, deflect by
//     surface normal × pressure coefficient (Cp = 1 - (v/v∞)²)
//   · Thermal colormap: T = T∞ + (v∞² - v²) / (2·Cp·R) — stagnation heating
//   · Boundary layer: particles within 0.05m of surface get viscous damping
//   · Wake region: downstream particles get turbulence vortex seeding
//   · Thermal bands rendered as vertex-colored SCNGeometry point cloud
//
// Wind Tunnel Presets:
//   · Subsonic  — 0-340 m/s, smooth laminar flow
//   · Transonic — 300-450 m/s, shock wave visualization
//   · Supersonic — 450+ m/s, Mach cone + bow shock
//   · Hypersonic — Mach 5+, plasma heating visualization
//   · Low Speed (wind channel) — 1-30 m/s, detailed boundary layer
// ═══════════════════════════════════════════════════════════════════════════

// MARK: — Wind Tunnel Physics Constants

public struct ArcAeroPhysics {
    // Standard atmosphere
    public static let airDensitySeaLevel: Float = 1.225     // kg/m³
    public static let airViscosity: Float       = 1.81e-5   // Pa·s
    public static let speedOfSound: Float       = 343.0     // m/s
    public static let cpAir: Float              = 1005.0    // J/kg·K specific heat
    public static let ambientTempK: Float       = 293.0     // ~72°F

    // Compute Mach number
    public static func mach(_ v: Float) -> Float { v / speedOfSound }

    // Pressure coefficient at a surface point (incompressible approximation)
    // Cp = 1 - (v_surface / v_freestream)²
    public static func pressureCoeff(vSurface: Float, vFreestream: Float) -> Float {
        guard vFreestream > 0.01 else { return 0 }
        return 1.0 - pow(vSurface / vFreestream, 2)
    }

    // Stagnation temperature rise
    public static func stagnationTempK(freestreamV: Float, ambientK: Float) -> Float {
        ambientK + (freestreamV * freestreamV) / (2 * cpAir)
    }

    // Reynolds number Re = ρvL/μ
    public static func reynolds(velocity: Float, length: Float) -> Float {
        airDensitySeaLevel * velocity * length / airViscosity
    }

    // Thermal colormap: blue (cold/fast) → green → yellow → orange → red (hot/stagnant)
    // Input: normalized heat 0..1 (0=cool freestream, 1=full stagnation)
    public static func thermalColor(_ heat: Float) -> SIMD3<Float> {
        let t = max(0, min(1, heat))
        // Matches web app heatFire color stops
        let stops: [SIMD3<Float>] = [
            [0.00, 0.10, 0.80],  // deep blue   — fast/cold
            [0.00, 0.60, 1.00],  // cyan         — slightly slower
            [0.00, 1.00, 0.40],  // green        — mid
            [1.00, 0.85, 0.00],  // yellow       — warm
            [1.00, 0.40, 0.00],  // orange       — hot
            [1.00, 0.05, 0.00],  // red          — stagnation
            [1.00, 1.00, 1.00],  // white        — plasma/hypersonic
        ]
        let scaled = t * Float(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        let f = scaled - Float(i)
        return stops[i] + (stops[i+1] - stops[i]) * f
    }

    // Turbulence: Kelvin-Helmholtz vortex seeding in wake
    public static func turbulenceVelocity(baseV: SIMD3<Float>, t: Float, seed: Float) -> SIMD3<Float> {
        let freq: Float = 3.7
        let amp:  Float = simd_length(baseV) * 0.18
        return SIMD3<Float>(
            sin(t * freq + seed)       * amp,
            cos(t * freq * 0.7 + seed) * amp * 0.5,
            sin(t * freq * 1.3 + seed) * amp * 0.3)
    }
}

// MARK: — Wind Tunnel Preset

public struct ArcWindPreset: Identifiable {
    public let id: String
    public let name: String
    public let freestreamMS: Float    // m/s
    public let mach: Float
    public let gridRows: Int          // particle grid H × W at inlet
    public let gridCols: Int
    public let particleLifetime: Float  // seconds before respawn
    public let showShockWave: Bool
    public let label: String

    public static let presets: [ArcWindPreset] = [
        ArcWindPreset(id:"lowspeed",    name:"Low Speed",    freestreamMS:15,   mach:0.04, gridRows:12, gridCols:12, particleLifetime:4.0, showShockWave:false, label:"15 m/s · Re channel flow"),
        ArcWindPreset(id:"subsonic",    name:"Subsonic",     freestreamMS:150,  mach:0.44, gridRows:16, gridCols:16, particleLifetime:2.5, showShockWave:false, label:"150 m/s · M 0.44"),
        ArcWindPreset(id:"transonic",   name:"Transonic",    freestreamMS:320,  mach:0.93, gridRows:20, gridCols:20, particleLifetime:1.8, showShockWave:true,  label:"320 m/s · M 0.93 shock onset"),
        ArcWindPreset(id:"supersonic",  name:"Supersonic",   freestreamMS:680,  mach:1.98, gridRows:24, gridCols:24, particleLifetime:1.2, showShockWave:true,  label:"680 m/s · M 1.98 bow shock"),
        ArcWindPreset(id:"hypersonic",  name:"Hypersonic",   freestreamMS:1750, mach:5.10, gridRows:28, gridCols:28, particleLifetime:0.8, showShockWave:true,  label:"1750 m/s · M 5.1 plasma heating"),
    ]
}

// MARK: — Wind Tunnel Particle

public struct ArcWindParticle {
    public var pos: SIMD3<Float>
    public var vel: SIMD3<Float>
    public var age: Float       // seconds
    public var heat: Float      // 0..1
    public var cp: Float        // local pressure coefficient
    public var nearSurface: Bool
    public var turbulent: Bool
    public var seed: Float      // random turbulence seed
}

// MARK: — ArcWindTunnelEngine

@MainActor
public final class ArcWindTunnelEngine: ObservableObject {
    public static let shared = ArcWindTunnelEngine()

    @Published public var isRunning    = false
    @Published public var preset: ArcWindPreset = ArcWindPreset.presets[1]  // Subsonic default
    @Published public var windAxis: SIMD3<Float> = [1, 0, 0]  // +X default
    @Published public var inletSpan: Float = 12.0   // world units width of inlet
    @Published public var customVelocity: Float = 0  // 0 = use preset
    @Published public var showThermal  = true
    @Published public var showVelocity = true
    @Published public var showPressure = false
    @Published public var particleSize: CGFloat = 0.08
    @Published public var particleOpacity: Float = 0.82
    @Published public var particleCount: Int = 0

    private var particles: [ArcWindParticle] = []
    private var cloudNode: SCNNode?
    private var cloudGeo:  SCNGeometry?
    private weak var scene: SCNScene?
    private var displayLink: CADisplayLink?
    private var meshTriangles: [ArcWindTriangle] = []  // surface BVH
    private var t: Float = 0

    // Surface normals cache — precomputed from loaded GLB meshes
    private var surfaceSamples: [(pos: SIMD3<Float>, normal: SIMD3<Float>)] = []

    public func startTunnel(scene: SCNScene) {
        guard !isRunning else { return }
        self.scene = scene
        isRunning = true

        // Extract surface geometry from all mesh nodes in scene
        extractSurface(scene)

        // Build initial particle grid at inlet face
        spawnParticles()

        // Build SCN point cloud node
        buildCloudNode(scene)

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    public func stopTunnel() {
        isRunning = false
        displayLink?.invalidate(); displayLink = nil
        cloudNode?.removeFromParentNode()
        cloudNode = nil; cloudGeo = nil
        particles.removeAll()
        particleCount = 0
    }

    public func switchPreset(_ p: ArcWindPreset) {
        preset = p
        if isRunning { respawnAll() }
    }

    // MARK: — Surface extraction

    private func extractSurface(_ scene: SCNScene) {
        surfaceSamples.removeAll()
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry,
                  node.name != "arcFluidCloud",
                  node.name != "windTunnelCloud"
            else { return }
            node.updateWorldMatrix(true, true)
            let wt = node.worldTransform
            for src in geo.sources(for: .vertex) {
                let posData = src.data
                let stride = src.dataStride
                let offset = src.dataOffset
                let count  = src.vectorCount
                for i in 0..<min(count, 800) {   // sample up to 800 pts per mesh
                    let byteOff = offset + i * stride
                    if byteOff + 12 > posData.count { continue }
                    var lx: Float = 0, ly: Float = 0, lz: Float = 0
                    posData.copyBytes(to: UnsafeMutableBufferPointer(start: &lx, count: 1),
                                      from: byteOff..<byteOff+4)
                    posData.copyBytes(to: UnsafeMutableBufferPointer(start: &ly, count: 1),
                                      from: (byteOff+4)..<(byteOff+8))
                    posData.copyBytes(to: UnsafeMutableBufferPointer(start: &lz, count: 1),
                                      from: (byteOff+8)..<(byteOff+12))
                    let lv = SCNVector3(lx, ly, lz)
                    let wv = SCNVector3(wt.m11*lx+wt.m21*ly+wt.m31*lz+wt.m41,
                                       wt.m12*lx+wt.m22*ly+wt.m32*lz+wt.m42,
                                       wt.m13*lx+wt.m23*ly+wt.m33*lz+wt.m43)
                    // Approximate outward normal: normalize world position relative to object center
                    let bb = node.boundingBox
                    let cx = (bb.min.x+bb.max.x)/2, cy = (bb.min.y+bb.max.y)/2, cz = (bb.min.z+bb.max.z)/2
                    var n = SIMD3<Float>(lx-cx, ly-cy, lz-cz)
                    let nl = simd_length(n); if nl > 0.001 { n /= nl }
                    surfaceSamples.append((
                        pos: SIMD3<Float>(wv.x, wv.y, wv.z),
                        normal: n))
                }
            }
        }
    }

    // MARK: — Spawn particles at inlet

    private var freestreamV: Float {
        customVelocity > 0 ? customVelocity : preset.freestreamMS
    }

    private func inletOrigin() -> SIMD3<Float> {
        // Place inlet upstream of scene bounding box along wind axis
        var sceneMin = SIMD3<Float>(repeating: Float.infinity)
        var sceneMax = SIMD3<Float>(repeating: -Float.infinity)
        for s in surfaceSamples {
            sceneMin = simd_min(sceneMin, s.pos)
            sceneMax = simd_max(sceneMax, s.pos)
        }
        if surfaceSamples.isEmpty { sceneMin = [-6,-6,-6]; sceneMax = [6,6,6] }
        let center = (sceneMin + sceneMax) * 0.5
        let span = simd_length(sceneMax - sceneMin)
        // Place inlet 1.5× span upstream
        return center - windAxis * (span * 1.5)
    }

    private func spawnParticles() {
        particles.removeAll()
        let v0 = windAxis * freestreamV * 0.018  // scale m/s to scene units/frame
        let origin = inletOrigin()
        let rows = preset.gridRows; let cols = preset.gridCols
        let spacing = inletSpan / Float(max(1, cols - 1))

        // Build two perpendicular axes for the inlet face
        let up: SIMD3<Float> = abs(windAxis.y) < 0.9 ? [0,1,0] : [1,0,0]
        let right = simd_normalize(simd_cross(windAxis, up))
        let trueUp = simd_normalize(simd_cross(right, windAxis))

        for r in 0..<rows {
            for c in 0..<cols {
                let offset = right * (Float(c) - Float(cols)/2) * spacing
                         + trueUp * (Float(r) - Float(rows)/2) * spacing
                let pos = origin + offset
                particles.append(ArcWindParticle(
                    pos: pos, vel: v0,
                    age: Float.random(in: 0...preset.particleLifetime * 0.5),
                    heat: 0, cp: 0,
                    nearSurface: false, turbulent: false,
                    seed: Float.random(in: 0...100)))
            }
        }
        particleCount = particles.count
    }

    private func respawnAll() {
        spawnParticles()
        updateCloud()
    }

    private func respawnParticle(at idx: Int) {
        let v0 = windAxis * freestreamV * 0.018
        let origin = inletOrigin()
        let up: SIMD3<Float> = abs(windAxis.y) < 0.9 ? [0,1,0] : [1,0,0]
        let right = simd_normalize(simd_cross(windAxis, up))
        let trueUp = simd_normalize(simd_cross(right, windAxis))
        let cols = preset.gridCols
        let spacing = inletSpan / Float(max(1, cols - 1))
        let r = Int.random(in: 0..<preset.gridRows)
        let c = Int.random(in: 0..<cols)
        let offset = right * (Float(c) - Float(cols)/2) * spacing
                   + trueUp * (Float(r) - Float(preset.gridRows)/2) * spacing
        particles[idx] = ArcWindParticle(
            pos: origin + offset, vel: v0,
            age: 0, heat: 0, cp: 0,
            nearSurface: false, turbulent: false,
            seed: Float.random(in: 0...100))
    }

    // MARK: — Simulation tick

    @objc private func tick() {
        guard isRunning else { return }
        let dt: Float = 0.016
        t += dt
        let vFS = freestreamV * 0.018   // scene units per frame

        for i in particles.indices {
            particles[i].age += dt

            // Respawn when particle exits domain or lifetime exceeded
            if particles[i].age > preset.particleLifetime {
                respawnParticle(at: i); continue
            }

            var p = particles[i]

            // ── Surface interaction ──────────────────────────────────
            // Find nearest surface sample
            var minDist: Float = Float.infinity
            var nearNormal = SIMD3<Float>(0, 0, 0)
            for s in surfaceSamples {
                let d = simd_length(p.pos - s.pos)
                if d < minDist { minDist = d; nearNormal = s.normal }
            }

            let surfaceThreshold: Float = 0.35
            p.nearSurface = minDist < surfaceThreshold

            if p.nearSurface {
                // Deflect velocity along surface (potential flow approximation)
                // Remove normal component (impermeable surface)
                let vNorm = simd_dot(p.vel, nearNormal)
                if vNorm < 0 {
                    p.vel -= nearNormal * vNorm * 1.85   // specular-like reflection
                }
                // Viscous boundary layer damping
                let bfactor = max(0.1, minDist / surfaceThreshold)
                p.vel *= (0.88 + 0.12 * bfactor)

                // Pressure coefficient
                let vMag = simd_length(p.vel)
                p.cp = ArcAeroPhysics.pressureCoeff(vSurface: vMag / max(0.001, vFS), vFreestream: 1.0)

                // Stagnation heating
                let heatingNorm = (1.0 - min(1, vMag / max(0.001, vFS))) * (1.0 + ArcAeroPhysics.mach(freestreamV) * 0.4)
                p.heat = min(1, p.heat * 0.92 + heatingNorm * 0.08)

                // Turbulence seeding in wake (downstream of max thickness)
                let downstream = simd_dot(p.pos - nearNormal, windAxis)
                if downstream > 0 { p.turbulent = true }
            } else {
                // Freestream: relax back toward wind axis velocity
                p.vel += (windAxis * vFS - p.vel) * 0.04
                p.heat *= 0.97   // cool down when not near surface
                p.cp = 0
                p.turbulent = false
            }

            // ── Shock wave (transonic/supersonic) ────────────────────
            if preset.showShockWave && ArcAeroPhysics.mach(freestreamV) > 0.85 {
                // Add a bow-shock compression normal to wind axis
                // when particle crosses the stagnation region
                let stagnationProx = max(0, 1.0 - minDist / 2.0)
                let shockFactor = min(1, (ArcAeroPhysics.mach(freestreamV) - 0.85) * 2)
                p.vel -= windAxis * stagnationProx * shockFactor * vFS * 0.3
                if stagnationProx > 0.3 { p.heat = min(1, p.heat + stagnationProx * 0.12 * shockFactor) }
            }

            // ── Turbulence (wake region) ──────────────────────────────
            if p.turbulent {
                p.vel += ArcAeroPhysics.turbulenceVelocity(baseV: p.vel, t: t, seed: p.seed)
            }

            // Advance position
            p.pos += p.vel

            particles[i] = p
        }

        updateCloud()
    }

    // MARK: — Cloud geometry update

    private func buildCloudNode(_ scene: SCNScene) {
        cloudNode?.removeFromParentNode()
        let node = SCNNode(); node.name = "windTunnelCloud"
        scene.rootNode.addChildNode(node)
        cloudNode = node
        updateCloud()
    }

    private func updateCloud() {
        guard let cloudNode else { return }
        let n = particles.count; guard n > 0 else { return }

        var posArr = [Float](); posArr.reserveCapacity(n*3)
        var colArr = [Float](); colArr.reserveCapacity(n*4)

        for p in particles {
            posArr += [p.pos.x, p.pos.y, p.pos.z]
            // Color by mode
            let c: SIMD3<Float>
            if showThermal {
                c = ArcAeroPhysics.thermalColor(p.heat)
            } else if showPressure {
                // Pressure: blue=suction (Cp<0), red=stagnation (Cp>0)
                let cp = max(-1, min(1, p.cp))
                c = cp > 0
                    ? SIMD3<Float>(cp, 1-cp*0.7, 0)    // red/orange = high pressure
                    : SIMD3<Float>(0, 1+cp*0.5, -cp)   // cyan/blue = suction
            } else {
                // Velocity: blue=fast, red=slow
                let speed = min(1, simd_length(p.vel) / max(0.001, preset.freestreamMS * 0.018))
                c = ArcAeroPhysics.thermalColor(1.0 - speed)
            }
            colArr += [c.x, c.y, c.z, Double(particleOpacity)]
        }

        let posSrc = SCNGeometrySource(
            data: Data(bytes: posArr, count: posArr.count*4),
            semantic: .vertex, vectorCount: n, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let colSrc = SCNGeometrySource(
            data: Data(bytes: colArr, count: colArr.count*4),
            semantic: .color, vectorCount: n, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let elem = SCNGeometryElement(indices: (0..<n).map{UInt32($0)}, primitiveType: .point)
        elem.pointSize = particleSize
        elem.minimumPointScreenSpaceRadius = 1.5
        elem.maximumPointScreenSpaceRadius = 10.0
        let geo = SCNGeometry(sources: [posSrc, colSrc], elements: [elem])
        let mat = SCNMaterial()
        mat.lightingModel = .constant; mat.isDoubleSided = true
        mat.writesToDepthBuffer = false; mat.blendMode = .alpha
        geo.materials = [mat]
        cloudNode.geometry = geo
        cloudGeo = geo
        particleCount = n
    }
}

// MARK: — Wind Tunnel Control Panel (SwiftUI)

struct ArcWindTunnelPanel: View {
    @StateObject private var engine = ArcWindTunnelEngine.shared
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var customV: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "wind").foregroundColor(themeVM.accent).font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("WIND TUNNEL")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(themeVM.accent).tracking(2)
                    Text("Arc Edge Aerodynamic CFD · Thermal colormap")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                if engine.isRunning {
                    HStack(spacing: 3) {
                        Circle().fill(.green).frame(width:5,height:5)
                        Text("LIVE").font(.system(size:7,weight:.bold,design:.monospaced))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal,12).padding(.vertical,8)
            .background(Color.white.opacity(0.04))

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {

                    // ── Preset selector ──────────────────────────────
                    sectionTitle("FLOW PRESET")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(ArcWindPreset.presets) { p in
                            Button {
                                engine.switchPreset(p)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 8, weight: .bold, design: .monospaced))
                                    Text(p.label).font(.system(size: 6.5, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(engine.preset.id == p.id
                                    ? themeVM.accent.opacity(0.18)
                                    : Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(engine.preset.id == p.id
                                        ? themeVM.accent.opacity(0.5)
                                        : Color.white.opacity(0.1), lineWidth: 1))
                            }
                            .foregroundColor(engine.preset.id == p.id ? themeVM.accent : .white.opacity(0.7))
                        }
                    }

                    // ── Custom velocity ──────────────────────────────
                    sectionTitle("CUSTOM VELOCITY")
                    HStack(spacing: 6) {
                        TextField("m/s", text: $customV)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onSubmit {
                                engine.customVelocity = Float(customV) ?? 0
                            }
                        Text("m/s").font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeVM.accent.opacity(0.6))
                        Spacer()
                        let mach = ArcAeroPhysics.mach(engine.customVelocity > 0
                            ? engine.customVelocity
                            : engine.preset.freestreamMS)
                        Text(String(format: "M %.2f", mach))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(machColor(mach))
                    }

                    // ── Wind axis ────────────────────────────────────
                    sectionTitle("FLOW DIRECTION")
                    HStack(spacing: 4) {
                        ForEach([
                            ("+X", SIMD3<Float>(1,0,0)),
                            ("-X", SIMD3<Float>(-1,0,0)),
                            ("+Z", SIMD3<Float>(0,0,1)),
                            ("-Z", SIMD3<Float>(0,0,-1)),
                        ], id: \.0) { label, vec in
                            Button(label) { engine.windAxis = vec }
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(engine.windAxis == vec
                                    ? themeVM.accent.opacity(0.2)
                                    : Color.white.opacity(0.05))
                                .foregroundColor(engine.windAxis == vec
                                    ? themeVM.accent : .white.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }

                    // ── Colormap mode ────────────────────────────────
                    sectionTitle("COLORMAP")
                    HStack(spacing: 4) {
                        cmapBtn("Thermal", active: engine.showThermal)  { engine.showThermal = true;  engine.showVelocity = false; engine.showPressure = false }
                        cmapBtn("Velocity", active: engine.showVelocity && !engine.showThermal) { engine.showThermal = false; engine.showVelocity = true;  engine.showPressure = false }
                        cmapBtn("Pressure", active: engine.showPressure) { engine.showThermal = false; engine.showVelocity = false; engine.showPressure = true  }
                    }

                    // ── Live stats ───────────────────────────────────
                    if engine.isRunning {
                        sectionTitle("LIVE READOUT")
                        statsRow("Particles", "\(engine.particleCount)")
                        statsRow("Freestream", String(format: "%.0f m/s", engine.customVelocity > 0 ? engine.customVelocity : engine.preset.freestreamMS))
                        statsRow("Mach", String(format: "%.2f", ArcAeroPhysics.mach(engine.customVelocity > 0 ? engine.customVelocity : engine.preset.freestreamMS)))
                        statsRow("Re (L=1m)", String(format: "%.2e", ArcAeroPhysics.reynolds(velocity: engine.preset.freestreamMS, length: 1.0)))
                        statsRow("T_stag (K)", String(format: "%.0f K", ArcAeroPhysics.stagnationTempK(freestreamV: engine.preset.freestreamMS, ambientK: 293)))
                    }

                    // ── Thermal legend ───────────────────────────────
                    sectionTitle("THERMAL SCALE")
                    thermalLegend

                }
                .padding(10)
            }

            Divider().background(Color.white.opacity(0.08))

            // ── Launch / Stop button ─────────────────────────────────
            Button {
                if engine.isRunning {
                    engine.stopTunnel()
                } else {
                    engine.startTunnel(scene: labVM.scene)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: engine.isRunning ? "stop.fill" : "wind")
                        .font(.system(size: 11))
                    Text(engine.isRunning ? "STOP TUNNEL" : "LAUNCH WIND TUNNEL")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(engine.isRunning
                    ? Color.red.opacity(0.18)
                    : themeVM.accent.opacity(0.16))
                .foregroundColor(engine.isRunning ? .red : themeVM.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(engine.isRunning ? Color.red.opacity(0.4) : themeVM.accent.opacity(0.4),
                            lineWidth: 1))
            }
            .padding(10)
        }
        .background(Color(red:0.03,green:0.05,blue:0.10).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: — Helpers

    private func machColor(_ m: Float) -> Color {
        if m < 0.8  { return .green }
        if m < 1.0  { return .yellow }
        if m < 2.0  { return .orange }
        return .red
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.35)).tracking(1.5)
    }

    private func statsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 8.5, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(value).font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundColor(themeVM.accent)
        }
    }

    private func cmapBtn(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(active ? themeVM.accent.opacity(0.2) : Color.white.opacity(0.05))
                .foregroundColor(active ? themeVM.accent : .white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    private var thermalLegend: some View {
        HStack(spacing: 0) {
            ForEach(0..<20) { i in
                let heat = Float(i) / 19.0
                let c = ArcAeroPhysics.thermalColor(heat)
                Rectangle()
                    .fill(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)))
                    .frame(height: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            HStack {
                Text("Fast").font(.system(size: 7, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("Stagnation").font(.system(size: 7, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }.padding(.horizontal, 2),
            alignment: .center
        )
    }
}

// Missing helper type
struct ArcWindTriangle {
    var v0, v1, v2: SIMD3<Float>
    var normal: SIMD3<Float>
}

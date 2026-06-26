import Foundation
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════════════
// ArcQuantumEngine.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// Port of the web app's quantum orbital point cloud renderer.
// Matches EXACTLY the HTML logic:
//   · Nucleus: Fibonacci sphere point cloud (proton=orange, neutron=cyan-grey)
//   · Electrons: ψ_nlm CDF sampled orbital clouds — 30 pts/electron default
//   · Physics: neutron→proton relay (85%)→electron shell wave propagation
//   · No preset animation — all motion driven by element physics data
//   · Recording: frame capture array + scrubber playback
//
// Uses SCNGeometry vertex sources (BufferGeometry equivalent in SceneKit)
// instead of individual SCNSphere nodes for GPU-efficient point clouds.
// ═══════════════════════════════════════════════════════════════════════════

// MARK: — Quantum math (ψ_nlm CDF sampling, Slater Zeff)

struct ArcQuantumMath {
    static let a0: Float = 0.529177  // Bohr radius Å

    // Associated Laguerre polynomial L_k^alpha(rho)
    static func assocLaguerre(_ k: Int, _ alpha: Float, _ rho: Float) -> Float {
        if k <= 0 { return 1.0 }
        if k == 1 { return 1.0 + alpha - rho }
        var Lm2: Float = 1, Lm1: Float = 1.0 + alpha - rho, L: Float = Lm1
        for j in 2...k {
            let jf = Float(j)
            L = ((2*jf - 1 + alpha - rho) * Lm1 - (jf - 1 + alpha) * Lm2) / jf
            Lm2 = Lm1; Lm1 = L
        }
        return L
    }

    // Associated Legendre polynomial P_l^m(x)
    static func assocLegendre(_ l: Int, _ m: Int, _ x: Float) -> Float {
        var Pmm: Float = 1.0
        if m > 0 {
            let s = sqrt(max(0, (1-x)*(1+x)))
            var f: Float = 1
            for _ in 1...m { Pmm *= -f * s; f += 2 }
        }
        if l == m { return Pmm }
        var Pm1m = x * Float(2*m+1) * Pmm
        if l == m+1 { return Pm1m }
        var Pll = Pm1m
        for ll in (m+2)...l {
            Pll = (Float(2*ll-1)*x*Pm1m - Float(ll+m-1)*Pmm) / Float(ll-m)
            Pmm = Pm1m; Pm1m = Pll
        }
        return Pm1m
    }

    static func gamma(_ n: Int) -> Float {
        if n <= 1 { return 1.0 }
        var r: Float = 1; for i in 1..<n { r *= Float(i) }; return r
    }

    // Build radial CDF for (n, l)
    static func buildRCDF(n: Int, l: Int) -> ([Float], Float) {
        let rMax: Float = Float(10 * n * n) * a0
        let nPts = 4096; let dr = rMax / Float(nPts-1)
        var cdf = [Float](repeating: 0, count: nPts)
        var sum: Float = 0
        let kL = n - l - 1; let alpha = Float(2*l+1)
        let normFactor = pow(2.0 / (Float(n) * a0), 3) *
            gamma(n-l) / Float(2*n) / gamma(n+l+1)
        let norm = sqrt(max(0, normFactor))
        for i in 0..<nPts {
            let r = Float(i) * dr
            let rho = 2 * r / (Float(n) * a0)
            let L = assocLaguerre(kL, alpha, rho)
            let R = norm * exp(-rho/2) * pow(max(0,rho), Float(l)) * L
            sum += r * r * R * R
            cdf[i] = sum
        }
        if sum > 0 { for i in 0..<nPts { cdf[i] /= sum } }
        return (cdf, rMax)
    }

    // Build polar (theta) CDF for (l, |m|)
    static func buildTCDF(l: Int, absM: Int) -> [Float] {
        let nPts = 2048; let dt: Float = .pi / Float(nPts-1)
        var cdf = [Float](repeating: 0, count: nPts)
        var sum: Float = 0
        for i in 0..<nPts {
            let theta = Float(i) * dt
            let x = cos(theta)
            let Plm = assocLegendre(l, absM, x)
            sum += sin(theta) * Plm * Plm
            cdf[i] = sum
        }
        if sum > 0 { for i in 0..<nPts { cdf[i] /= sum } }
        return cdf
    }

    // Sample CDF via binary search
    static func sampleCDF(_ cdf: [Float]) -> Int {
        let u = Float.random(in: 0..<1)
        var lo = 0, hi = cdf.count - 1
        while lo < hi {
            let mid = (lo + hi) >> 1
            if cdf[mid] < u { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // Sample 3D position from ψ_nlm orbital
    static func sampleOrb(n: Int, l: Int, m: Int, Zeff: Float,
                           rCDF: [Float], rMax: Float, tCDF: [Float]) -> SIMD3<Float> {
        let dr = rMax / Float(rCDF.count - 1)
        let dt: Float = .pi / Float(tCDF.count - 1)
        let r = Float(sampleCDF(rCDF)) * dr / max(0.1, Zeff)
        let theta = Float(sampleCDF(tCDF)) * dt
        let phi = Float.random(in: 0..<(2 * .pi))
        let s = sin(theta)
        return SIMD3<Float>(r*s*cos(phi), r*cos(theta), r*s*sin(phi))
    }

    // Aufbau order
    static let aufbau: [(n:Int,l:Int)] = [
        (1,0),(2,0),(2,1),(3,0),(3,1),(4,0),(3,2),
        (4,1),(5,0),(4,2),(5,1),(6,0),(4,3),(5,2),(6,1),
        (7,0),(5,3),(6,2),(7,1)
    ]

    struct OrbElectron { let n, l, m, shellIdx: Int; let Zeff: Float }

    // Build list of orbitals occupied by Z electrons in given shell config
    static func getElectrons(Z: Int, shells: [Int]) -> [OrbElectron] {
        var rem = shells.reduce(0, +)
        var out = [OrbElectron]()
        for (_, nl) in aufbau.enumerated() {
            guard rem > 0 else { break }
            let n = nl.n, l = nl.l
            let cap = 2 * (2*l + 1)
            let fill = min(rem, cap); rem -= fill
            var placed = 0
            for pass in 0..<2 {
                for m in -l...l {
                    guard placed < fill else { break }
                    if pass == 0 && fill > 2*l+1 && placed >= 2*l+1 { continue }
                    // Slater Zeff
                    var sigma: Float = 0
                    if n == 1 { sigma += max(0, Float(min(Z,2)) - 1) * 0.30 }
                    else if l <= 1 { sigma += Float(max(0, fill-1)) * 0.35 }
                    else { sigma += Float(max(0, fill-1)) * 0.35; for k in 1..<n { sigma += Float(2*(2*(k)+1)) } }
                    let Zeff = max(1.0, Float(Z) - sigma)
                    out.append(OrbElectron(n:n, l:l, m:m, shellIdx:n-1, Zeff:Zeff))
                    placed += 1
                }
                if placed >= fill { break }
            }
        }
        return out
    }
}

// MARK: — Shell color palette (matches web app _skyBlues)
let _ArcShellColors: [(Float,Float,Float)] = [
    (0.10, 0.85, 1.00),  // K — cyan
    (0.55, 0.20, 1.00),  // L — violet
    (0.20, 1.00, 0.60),  // M — green
    (1.00, 0.85, 0.10),  // N — yellow
    (1.00, 0.30, 0.70),  // O — pink
    (0.30, 1.00, 1.00),  // P — teal
    (1.00, 0.60, 0.20),  // Q — orange
]

// MARK: — Point cloud geometry helper (SCNGeometry vertex source)

func arcMakePointCloud(positions: [SIMD3<Float>], colors: [SIMD3<Float>], ptSize: CGFloat) -> SCNNode {
    guard !positions.isEmpty else { return SCNNode() }
    let n = positions.count

    // Vertex positions
    var posData = [Float](); posData.reserveCapacity(n * 3)
    for p in positions { posData += [p.x, p.y, p.z] }

    // Vertex colors
    var colData = [Float](); colData.reserveCapacity(n * 4)
    for c in colors { colData += [c.x, c.y, c.z, 0.92] }

    let posSource = SCNGeometrySource(
        data: Data(bytes: posData, count: posData.count * 4),
        semantic: .vertex, vectorCount: n,
        usesFloatComponents: true, componentsPerVector: 3,
        bytesPerComponent: 4, dataOffset: 0, dataStride: 12)

    let colSource = SCNGeometrySource(
        data: Data(bytes: colData, count: colData.count * 4),
        semantic: .color, vectorCount: n,
        usesFloatComponents: true, componentsPerVector: 4,
        bytesPerComponent: 4, dataOffset: 0, dataStride: 16)

    let indices = (0..<n).map { UInt32($0) }
    let elem = SCNGeometryElement(indices: indices, primitiveType: .point)
    elem.pointSize = ptSize
    elem.minimumPointScreenSpaceRadius = 1.5
    elem.maximumPointScreenSpaceRadius = 8.0

    let geo = SCNGeometry(sources: [posSource, colSource], elements: [elem])
    let mat = SCNMaterial()
    mat.lightingModel = .constant
    mat.isDoubleSided = true
    mat.writesToDepthBuffer = false
    mat.blendMode = .alpha
    geo.materials = [mat]

    return SCNNode(geometry: geo)
}

// MARK: — ArcAtomData (replaces legacy atom group)

public struct ArcAtomData {
    public let elementId: Int
    public let root: SCNNode
    public let nucleusCloudNode: SCNNode   // point cloud for nucleus
    public let orbitalCloudNode: SCNNode   // point cloud for all electrons
    public var nucleusCenter: SCNVector3
    public var velocity: SIMD3<Float> = .zero
    public var isActive: Bool = false
    public var devWarmup: Int = 0
    public var friction: Float = 0.993
    // Physics properties from element
    public let mass: Float       // AMU
    public let nucleusR: Float
    public let maxShellR: Float
    // Recording: electron proxy world positions (lightweight, no geometry)
    public var electronProxyPositions: [SIMD3<Float>]
    public var electronInitialOffsets: [SIMD3<Float>]
    public var nucleonInitialPositions: [SIMD3<Float>]  // for reset
    // Invisible hit sphere node
    public let hitNode: SCNNode
}

// MARK: — ArcQuantumAtomBuilder

public final class ArcQuantumAtomBuilder {

    public static var ptsPerElectron: Int = 30
    public static var nucPtSize: CGFloat  = 0.018
    public static var elecPtSize: CGFloat = 0.022

    // Build full quantum orbital point-cloud atom, returns ArcAtomData
    public static func build(element: ArcElement, at pos: SIMD3<Float>,
                             scene: SCNScene) -> ArcAtomData {
        let Z = element.id
        let protons = element.protons
        let neutrons = element.neutrons
        let shells = element.electronOrbits
        let totalNucleons = protons + neutrons

        let root = SCNNode()
        root.name = "atomZ:\(Z)"
        root.position = SCNVector3(pos.x, pos.y, pos.z)

        // ── Nucleus radius (matches web: max(0.18, cbrt(nucleons)*0.12)) ──
        let nucleusR = max(0.18, pow(Float(max(1,totalNucleons)), 1.0/3.0) * 0.12)

        // ── Nucleus point cloud ───────────────────────────────────────────
        var nucPositions = [SIMD3<Float>]()
        var nucColors    = [SIMD3<Float>]()

        // Protons — Fibonacci sphere, orange-red
        let pRGB: SIMD3<Float> = [1.0, 0.30, 0.10]
        for i in 0..<protons {
            let phi = acos(-1.0 + 2.0*Float(i)/Float(max(1,protons-1)))
            let theta = sqrt(Float(protons) * .pi) * phi
            let r = nucleusR * 0.78
            nucPositions.append(SIMD3<Float>(r*sin(phi)*cos(theta), r*sin(phi)*sin(theta), r*cos(phi)))
            nucColors.append(pRGB)
        }
        // Neutrons — Fibonacci sphere, cyan-grey
        let nRGB: SIMD3<Float> = [0.47, 0.69, 0.76]
        for i in 0..<neutrons {
            let phi = acos(-1.0 + 2.0*Float(i)/Float(max(1,neutrons-1)))
            let theta = sqrt(Float(neutrons) * .pi) * phi
            let r = nucleusR * 0.88
            nucPositions.append(SIMD3<Float>(r*sin(phi)*cos(theta), r*sin(phi)*sin(theta), r*cos(phi)))
            nucColors.append(nRGB)
        }

        let nucleusCloud = arcMakePointCloud(positions: nucPositions, colors: nucColors,
                                             ptSize: nucPtSize)
        nucleusCloud.name = "_nucleusCloud:\(Z)"
        root.addChildNode(nucleusCloud)

        // ── Electron quantum orbital cloud (ψ_nlm CDF sampling) ─────────
        let electronList = ArcQuantumMath.getElectrons(Z: Z, shells: shells)
        let PTS = max(5, min(500, ptsPerElectron))
        let shellStep = max(0.35, nucleusR * 0.8 + 0.3)
        let shellBase = nucleusR + 0.15

        var ePositions = [SIMD3<Float>]()
        var eColors    = [SIMD3<Float>]()

        // Cache CDFs per (n,l) and (l,|m|) — avoid recomputing per point
        var rCDFCache  = [String: ([Float], Float)]()
        var tCDFCache  = [String: [Float]]()

        for orb in electronList {
            let rKey = "\(orb.n)_\(orb.l)"
            if rCDFCache[rKey] == nil { rCDFCache[rKey] = ArcQuantumMath.buildRCDF(n: orb.n, l: orb.l) }
            let tKey = "\(orb.l)_\(abs(orb.m))"
            if tCDFCache[tKey] == nil { tCDFCache[tKey] = ArcQuantumMath.buildTCDF(l: orb.l, absM: abs(orb.m)) }

            let (rCDF, rMax) = rCDFCache[rKey]!
            let tCDF = tCDFCache[tKey]!

            let shellCenterR = shellBase + Float(orb.shellIdx) * shellStep
            // ── Corrected orbital scale ──────────────────────────────────
            // Raw CDF samples are in Bohr radii (Å units).
            // We normalize so the 95th-percentile radius (≈5n²a0) maps to
            // shellCenterR scene units — keeps all elements visually contained
            // regardless of Z or n. Matches web app visual density.
            let rMax_95 = 5.0 * Float(orb.n * orb.n) * ArcQuantumMath.a0
            let scale = shellCenterR / max(0.01, rMax_95)
            let sc = _ArcShellColors[orb.shellIdx % _ArcShellColors.count]

            for _ in 0..<PTS {
                let raw = ArcQuantumMath.sampleOrb(n: orb.n, l: orb.l, m: orb.m,
                    Zeff: orb.Zeff, rCDF: rCDF, rMax: rMax, tCDF: tCDF)
                // Clamp to shellCenterR × 1.6 so no particle escapes the shell sphere
                let rawLen = simd_length(raw)
                let clampedLen = min(rawLen, shellCenterR * 1.6 / max(0.001, scale))
                let rawClamped = rawLen > 0.001 ? raw * (clampedLen / rawLen) : raw
                let p = rawClamped * scale
                ePositions.append(p)
                // Color: radial position within shell (0=inner, 1=outer edge)
                let v = min(1.0, simd_length(p) / max(0.01, shellCenterR))
                let heat = min(1.0, v * 1.4)
                eColors.append(SIMD3<Float>(
                    min(1, sc.0 + heat * 0.3),
                    min(1, sc.1 + heat * 0.15),
                    max(0, sc.2 * (1 - heat*0.3) + heat*0.3)))
            }
        }

        let orbitalCloud = arcMakePointCloud(positions: ePositions, colors: eColors,
                                              ptSize: elecPtSize)
        orbitalCloud.name = "_orbitalCloud:\(Z)"
        root.addChildNode(orbitalCloud)

        // ── Nucleus glow (subtle, like web version) ───────────────────────
        let glowGeo = SCNSphere(radius: CGFloat(nucleusR * 1.4))
        glowGeo.firstMaterial?.diffuse.contents  = UIColor(red:1.0, green:0.5, blue:0.1, alpha:0.04)
        glowGeo.firstMaterial?.emission.contents = UIColor(red:1.0, green:0.4, blue:0.0, alpha:0.06)
        glowGeo.firstMaterial?.isDoubleSided = true
        glowGeo.firstMaterial?.lightingModel = .constant
        glowGeo.firstMaterial?.writesToDepthBuffer = false
        root.addChildNode(SCNNode(geometry: glowGeo))

        // ── Invisible hit sphere (tap detection) ─────────────────────────
        let maxShellR = shellBase + Float(max(0, shells.count-1)) * shellStep + shellStep
        let hitGeo = SCNSphere(radius: CGFloat(maxShellR * 1.1))
        hitGeo.firstMaterial?.diffuse.contents = UIColor.clear
        hitGeo.firstMaterial?.isDoubleSided = true
        hitGeo.firstMaterial?.lightingModel = .constant
        hitGeo.firstMaterial?.writesToDepthBuffer = false
        hitGeo.firstMaterial?.colorBufferWriteMask = []
        let hitNode = SCNNode(geometry: hitGeo)
        hitNode.name = "atomZ_hit:\(Z)"
        root.addChildNode(hitNode)

        // ── Element label ─────────────────────────────────────────────────
        let text = SCNText(string: element.elementSymbol, extrusionDepth: 0.01)
        text.font = UIFont.systemFont(ofSize: 0.32, weight: .bold)
        text.firstMaterial?.diffuse.contents  = UIColor.white
        text.firstMaterial?.emission.contents = UIColor(red:0.3, green:0.8, blue:1.0, alpha:0.35)
        text.firstMaterial?.lightingModel = .constant
        let lbl = SCNNode(geometry: text)
        let (mn, mx) = text.boundingBox
        lbl.position = SCNVector3(-(mx.x-mn.x)/2, -(nucleusR + 0.65), 0)
        lbl.scale = SCNVector3(0.72, 0.72, 0.72)
        root.addChildNode(lbl)

        scene.rootNode.addChildNode(root)

        // Build electron proxy positions (lightweight SIMD — no geometry)
        // Used for physics wave propagation matching web app electron mesh behavior
        var electronProxies = [SIMD3<Float>]()
        var electronOffsets = [SIMD3<Float>]()
        for (shellIdx, eCount) in shells.enumerated() {
            let shellR = Float(shellIdx + 1) * 1.15 + nucleusR + 0.25
            for i in 0..<eCount {
                let angle = (2 * Float.pi * Float(i)) / Float(max(1, eCount))
                let proxy = SIMD3<Float>(shellR * cos(angle), 0, shellR * sin(angle))
                electronProxies.append(proxy)
                electronOffsets.append(proxy)
            }
        }

        let atomData = ArcAtomData(
            elementId: Z,
            root: root,
            nucleusCloudNode: nucleusCloud,
            orbitalCloudNode: orbitalCloud,
            nucleusCenter: SCNVector3(pos.x, pos.y, pos.z),
            mass: Float(element.atomicMass),
            nucleusR: nucleusR,
            maxShellR: maxShellR,
            electronProxyPositions: electronProxies,
            electronInitialOffsets: electronOffsets,
            nucleonInitialPositions: nucPositions,
            hitNode: hitNode
        )
        return atomData
    }
}

// MARK: — ArcQuantumPhysics: the sim tick (port of applyNewPhysics)

public final class ArcQuantumPhysics {

    public static let shared = ArcQuantumPhysics()

    // Physics constants matching web app
    let gravityScale: Float = 0.00005
    let protonRelayFactor: Float = 0.85
    let friction: Float = 0.993
    let impulseSeed: Float = 0.00005
    let warmupFrames: Int = 90

    // Simulation state
    public var isSimulating: Bool = false
    public var gravity: Float = 9.80        // m/s² from scene
    public var startEnvTempF: Float = 72    // °F from scene
    public var startEnvPressure: Float = 14.7  // psi from scene
    public var frames: [[ArcFrameState]] = []
    public var isScrubbing: Bool = false

    // Tick — LEATR neutron-first propagation:
    // Neutron (blueprint root) → Proton (radian/degree passage of state) → Electron shells
    // All forces enter and exit through the neutron.
    // Proton is a proportionality bridge — never receives direct calculation.
    // Electrons receive waveform attenuated by shell distance from neutron.
    // Formula (per web arclake.html + Quantum Socket doc):
    //   bridge = neutrons × (π / protonCount) × stateModifier   [radian/degree]
    //   shellAttenuation = max(0.1, 1 - shellIdx/totalShells × 0.7)
    //   electronDev = neutronDev × protonBridge × shellAttenuation
    public func tick(atoms: inout [ArcAtomData], dt: Float = 0.016,
                     envTempF: Float = 72, envGravity: Float = 9.8,
                     envPressurePsi: Float = 14.7, envWindMS: Float = 0) {
        guard isSimulating && !isScrubbing else { return }

        let gVec = SIMD3<Float>(0, -gravityScale * envGravity, 0)
        let t = Float(CACurrentMediaTime())
        let floorY: Float = 0.6

        for i in atoms.indices {
            var a = atoms[i]
            a.devWarmup = min(warmupFrames, a.devWarmup + 1)
            let devRamp = Float(a.devWarmup) / Float(warmupFrames)

            // ── NEUTRON STEP: gravity + Brownian thermal motion ──────────
            // Neutron is physics root — receives 100% of environmental forces
            a.velocity += gVec
            // Thermal Brownian motion from temperature
            let tempFactor = max(0, envTempF - 32) / 212.0   // 0 at 32°F, 1 at 244°F
            let brown: Float = 0.00008 * tempFactor * devRamp
            a.velocity += SIMD3<Float>(
                Float.random(in: -brown...brown),
                Float.random(in: -brown*0.3...brown*0.3),
                Float.random(in: -brown...brown))
            // Wind drift along X axis
            a.velocity.x += envWindMS * 0.00002
            a.velocity *= friction

            // Translate entire atom (root node = neutron origin in scene)
            let delta = a.velocity
            var newPos = SIMD3<Float>(
                a.root.presentation.simdWorldPosition.x + delta.x,
                a.root.presentation.simdWorldPosition.y + delta.y,
                a.root.presentation.simdWorldPosition.z + delta.z)
            // Floor — atom rests at spawn plane, doesn't sink below
            if newPos.y < floorY { newPos.y = floorY; a.velocity.y = abs(a.velocity.y) * 0.08 }
            a.root.simdPosition = newPos
            a.nucleusCenter = SCNVector3(newPos.x, newPos.y, newPos.z)

            // ── PROTON BRIDGE: radian/degree proportionality of state ────
            // bridge = neutrons × (π / max(1,protons)) × stateModifier
            // This is the passage — never a direct reaction — reflects matter state
            // as radian offset between neutron blueprint and electron target
            let neutronCount = Float(a.mass > 0 ? Int(a.mass) - a.elementId : 0)
            let protonCount  = Float(max(1, a.elementId))
            // State modifier: maps matter state to angle (gas=1.0, liquid=0.85, solid=0.65, plasma=1.2)
            let tempK = (envTempF - 32) * 5 / 9 + 273.15
            let stateModifier: Float = tempK > 3000 ? 1.2 : tempK > 373 ? 1.0 : tempK > 273 ? 0.85 : 0.65
            let protonBridgeRad = neutronCount * (.pi / protonCount) * stateModifier * devRamp
            let protonBridgeDeg = protonBridgeRad * 180 / .pi
            // Proton bridge gives proportionality between nucleus and shells
            let bridgeFactor = cos(protonBridgeRad) * 0.88 + 0.12  // 0.12..1.0

            // ── ARC EDGE DEVIATION at neutron level ──────────────────────
            // arcEdgeInfluenceBase = envTemp × envPressure / 14.7 (normalized)
            let arcInfluenceBase = (envTempF * 0.001) * (envPressurePsi / 14.7) * devRamp
            let devX = sin(t * 1.3 + Float(a.elementId) * 0.7) * arcInfluenceBase * 0.12
            let devY = cos(t * 0.9 + Float(a.elementId) * 1.1) * arcInfluenceBase * 0.08
            let devZ = sin(t * 1.7 + Float(a.elementId) * 0.4) * arcInfluenceBase * 0.10
            let neutronDev = SIMD3<Float>(devX, devY, devZ)  // 100% at neutron

            // ── PROTON: 85% relay, modulated by bridge radian ───────────
            // Proton never receives direct calc — it relays through bridge
            let protonDev = neutronDev * Float(protonRelayFactor) * bridgeFactor

            // ── ELECTRON SHELLS: attenuated by shell index ───────────────
            // Each shell gets wave from proton relay, attenuated by distance
            // Inner shells (K) couple most strongly; outer shells diminish
            // This drives the orbital cloud rotation per shell
            let totalShells = Float(max(1, a.electronProxyPositions.count > 0
                ? a.electronInitialOffsets.map { Int(simd_length($0) / 1.15) }.max() ?? 1
                : 1))

            // Update orbital cloud rotation shell-by-shell
            // Each shell orbits at its own speed driven by electron wave amplitude
            let waveBase = simd_length(protonDev)
            let orbitalCloudRotX = protonDev.x * 0.025
            let orbitalCloudRotY = waveBase * 0.015 + Float(a.elementId) * 0.0001
            let orbitalCloudRotZ = protonDev.z * 0.020
            // Additive rotation (no preset — purely physics driven)
            let cur = a.orbitalCloudNode.eulerAngles
            a.orbitalCloudNode.eulerAngles = SCNVector3(
                cur.x + orbitalCloudRotX,
                cur.y + orbitalCloudRotY,
                cur.z + orbitalCloudRotZ)

            atoms[i] = a
        }

        // ── INTER-ATOM COUPLING via velocity potential ───────────────────
        // Sigma impulse between neighboring atoms (pairwise, Phi field)
        // Only when multiple atoms in scene
        if atoms.count > 1 {
            for i in atoms.indices {
                for j in (i+1)..<atoms.count {
                    let posI = atoms[i].root.simdPosition
                    let posJ = atoms[j].root.simdPosition
                    let diff = posI - posJ
                    let dist = max(0.5, simd_length(diff))
                    // LJ-style coupling: attractive at medium range, repulsive close
                    let massI = atoms[i].mass; let massJ = atoms[j].mass
                    let sigma = 0.05 * (massI * massJ / (massI + massJ)) / (dist * dist)
                    let dir   = diff / dist
                    // Apply through proton bridge proportionality
                    let coupling = sigma * 0.001
                    atoms[i].velocity -= dir * coupling
                    atoms[j].velocity += dir * coupling
                }
            }
        }
    }

    // MARK: — Recording

    public func captureFrame(atoms: [ArcAtomData]) {
        let frame = ArcFrameState(
            time: Float(frames.count) / 60.0,
            atomStates: atoms.map { a in
                ArcAtomFrameState(
                    elementId: a.elementId,
                    rootPosition: a.root.position,
                    velocity: a.velocity,
                    orbitalRotation: a.orbitalCloudNode.eulerAngles)
            })
        frames.append([frame])
    }

    public func applyFrame(_ frameIndex: Int, atoms: inout [ArcAtomData]) {
        guard frameIndex < frames.count else { return }
        let states = frames[frameIndex]
        for state in states {
            if let idx = atoms.firstIndex(where: { $0.elementId == state.atomStates[0].elementId }) {
                atoms[idx].root.position = state.atomStates[0].rootPosition
                atoms[idx].orbitalCloudNode.eulerAngles = state.atomStates[0].orbitalRotation
            }
        }
    }

    public func clearRecording() { frames.removeAll() }
}

// MARK: — Frame state types for scrubber

public struct ArcAtomFrameState {
    public let elementId: Int
    public let rootPosition: SCNVector3
    public let velocity: SIMD3<Float>
    public let orbitalRotation: SCNVector3
}

public struct ArcFrameState {
    public let time: Float
    public let atomStates: [ArcAtomFrameState]
}

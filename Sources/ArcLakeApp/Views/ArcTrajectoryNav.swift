import SwiftUI
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════════════
// ArcTrajectoryNav.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// Horizons Trajectory Navigation System
// Links JPL Horizons real-time ephemeris to Mantis HUD flight controls.
//
// Features:
//   · Link button on both DRONE and CHEMISTRY HUD tabs → activates trajectory mode
//   · When linked: vehicle auto-navigates toward selected target body
//   · Scrubber at top of 3D viewport: center=real-time, left=past, right=faster future
//   · Speed multiplier: 1× real-time → up to 1000× (for Pluto-class missions)
//   · "RETURN TO NAV" button to re-engage after manual override
//   · Space environment: star field particle cloud, Earth sphere, Moon, target bodies
//   · Scene transitions: lab grid hidden, space background shown when linked
//   · Unlink: restores normal lab scene
//
// Scale: 1 AU = 10 scene units (matches ArcHorizonsEngine)
// Physics: velocity vector from Horizons VX/VY/VZ (AU/day) converted to
//          scene units/frame and applied to vehicle node
// ═══════════════════════════════════════════════════════════════════════════

// MARK: — Trajectory Link State

public enum ArcTrajectorySpeed: String, CaseIterable, Identifiable {
    case realtime  = "1×"
    case x10       = "10×"
    case x100      = "100×"
    case x1000     = "1000×"
    case x10000    = "10000×"
    public var id: String { rawValue }
    public var multiplier: Double {
        switch self {
        case .realtime: return 1
        case .x10:      return 10
        case .x100:     return 100
        case .x1000:    return 1000
        case .x10000:   return 10000
        }
    }
}

// MARK: — ArcTrajectoryEngine

@MainActor
public final class ArcTrajectoryEngine: ObservableObject {
    public static let shared = ArcTrajectoryEngine()

    @Published public var isLinked: Bool = false
    @Published public var isManualOverride: Bool = false  // user grabbed stick
    @Published public var targetBodyId: String = "499"   // Mars default
    @Published public var targetBodyName: String = "Mars"
    @Published public var speed: ArcTrajectorySpeed = .x100
    @Published public var scrubberOffset: Int = 0         // steps from real-time
    @Published public var currentEpoch: String = "NOW"
    @Published public var distanceToTargetAU: Double = 0
    @Published public var approachVelocityKms: Double = 0
    @Published public var missionPhase: String = "IDLE"   // LAUNCH / ASCENT / CRUISE / APPROACH / ORBIT
    @Published public var showSpaceEnv: Bool = false

    // Scene nodes managed by this engine
    private var starFieldNode:  SCNNode?
    private var earthNode:      SCNNode?
    private var moonNode:       SCNNode?
    private var targetNode:     SCNNode?
    private var trajectoryLine: SCNNode?
    private var floorNode:      SCNNode?     // reference to original floor to hide/show
    private weak var scene: SCNScene?
    private weak var vehicleNode: SCNNode?   // the active drone/rocket node
    private var displayLink: CADisplayLink?
    private var frameCount: Int = 0

    // Physics-driven auto-navigation toward target
    private var autoNavVelocity: SIMD3<Float> = .zero

    // MARK: — Link / Unlink

    public func link(scene: SCNScene, vehicleNode: SCNNode, targetId: String) async {
        self.scene = scene
        self.vehicleNode = vehicleNode
        self.targetBodyId = targetId
        let body = ArcCelestialBody.catalog.first(where: { $0.id == targetId })
        self.targetBodyName = body?.name ?? targetId

        // Fetch trajectory data
        await ArcHorizonsEngine.shared.fetchAll(scene: scene)

        // Build space environment
        buildSpaceEnvironment(scene: scene)

        // Hide lab floor grid
        hideLabFloor(scene: scene)

        isLinked = true
        isManualOverride = false
        showSpaceEnv = true
        missionPhase = "LAUNCH"

        // Start nav tick
        displayLink = CADisplayLink(target: self, selector: #selector(navTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    public func unlink() {
        isLinked = false
        isManualOverride = false
        showSpaceEnv = false
        missionPhase = "IDLE"
        displayLink?.invalidate(); displayLink = nil
        removeSpaceEnvironment()
        showLabFloor()
        autoNavVelocity = .zero
        scrubberOffset = 0
    }

    public func returnToNav() {
        isManualOverride = false
        // Re-engage auto-navigation
    }

    public func manualOverride() {
        isManualOverride = true
    }

    // MARK: — Nav Tick (auto-navigation toward target)

    @objc private func navTick() {
        guard isLinked && !isManualOverride else { return }
        guard let vehicle = vehicleNode else { return }

        frameCount += 1

        // Find target body current position from Horizons data
        let horizons = ArcHorizonsEngine.shared
        guard let traj = horizons.trajectories.first(where: { $0.bodyId == targetBodyId }),
              !traj.points.isEmpty else { return }

        // Apply scrubber + speed
        let stepIdx = max(0, min(traj.points.count - 1,
                                  traj.currentIndex + scrubberOffset))
        let pt = traj.points[stepIdx]
        let targetPos = pt.scenePosition

        // Current vehicle position
        let vPos = vehicle.simdPosition
        let diff = targetPos - vPos
        let dist = simd_length(diff)

        // Convert Horizons velocity (AU/day) to scene units per frame
        // 1 AU = 10 units, 1 day = 86400 sec, 60fps
        // At 1× speed: scale = 10 / 86400 / 60 × multiplier
        let auPerUnit: Float = 10.0
        let speedFactor = Float(speed.multiplier)
        let velScale = auPerUnit / 86400 / 60 * speedFactor

        // Horizons velocity for this point
        let hVel = SIMD3<Float>(Float(pt.vx), Float(pt.vz), Float(pt.vy)) * velScale

        // Direction toward target + Horizons velocity blend
        let toTarget = dist > 0.1 ? simd_normalize(diff) * 0.05 * speedFactor : .zero

        // Smooth approach
        autoNavVelocity = autoNavVelocity * 0.92 + (hVel + toTarget) * 0.08
        vehicle.simdPosition += autoNavVelocity

        // Update readouts
        distanceToTargetAU = Double(dist) / 10.0   // scene units → AU
        let velMS = simd_length(autoNavVelocity) * 10.0 / 60.0 * 1.496e11  // AU/frame → m/s
        approachVelocityKms = Double(velMS) / 1000.0

        // Advance scrubber
        if frameCount % max(1, Int(60.0 / speed.multiplier)) == 0 {
            scrubberOffset = min(scrubberOffset + 1, (traj.points.count - 1) - traj.currentIndex)
            horizons.updateScrubPosition()
            currentEpoch = horizons.currentEpoch
        }

        // Mission phase
        let altKm = distanceToTargetAU * 1.496e8   // AU → km
        if altKm > 1000000 { missionPhase = "CRUISE" }
        else if altKm > 100000 { missionPhase = "APPROACH" }
        else if altKm > 1000 { missionPhase = "ORBITAL INS" }
        else { missionPhase = "APPROACH" }

        // Update target node position
        targetNode?.simdPosition = targetPos

        // Point vehicle toward target
        if dist > 0.5 {
            let dir = simd_normalize(diff)
            let angle = acos(max(-1, min(1, simd_dot(dir, SIMD3<Float>(0, 1, 0)))))
            let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), dir))
            if simd_length(axis) > 0.001 {
                let targetQuat = simd_quatf(angle: angle, axis: axis)
                vehicle.simdOrientation = simd_slerp(vehicle.simdOrientation, targetQuat, 0.03)
            }
        }
    }

    // MARK: — Space Environment

    private func buildSpaceEnvironment(_ scene: SCNScene) {
        // Star field — 2000 randomly placed points in a large sphere
        let starGeo = SCNGeometry()
        var positions = [SIMD3<Float>]()
        var colors = [SIMD3<Float>]()
        let starRadius: Float = 800
        let rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            var r = SystemRandomNumberGenerator()
            let theta = Float.random(in: 0...(.pi * 2), using: &r)
            let phi   = Float.random(in: 0...(.pi),     using: &r)
            let d = starRadius * (0.6 + Float.random(in: 0...0.4, using: &r))
            positions.append(SIMD3<Float>(d*sin(phi)*cos(theta), d*sin(phi)*sin(theta), d*cos(phi)))
            // Vary star color: blue-white, white, yellow-white
            let hue = Float.random(in: 0...1, using: &r)
            let starCol: SIMD3<Float> = hue < 0.3
                ? [0.7, 0.8, 1.0]   // blue-white
                : hue < 0.7
                    ? [1.0, 1.0, 1.0]   // white
                    : [1.0, 0.95, 0.7]  // yellow-white
            colors.append(starCol * (0.6 + Float.random(in: 0...0.4, using: &r)))
        }

        var posArr = [Float](); posArr.reserveCapacity(2000*3)
        var colArr = [Float](); colArr.reserveCapacity(2000*4)
        for p in positions { posArr += [p.x, p.y, p.z] }
        for c in colors    { colArr += [c.x, c.y, c.z, 1.0] }

        let pSrc = SCNGeometrySource(data: Data(bytes: posArr, count: posArr.count*4),
            semantic:.vertex, vectorCount:2000, usesFloatComponents:true,
            componentsPerVector:3, bytesPerComponent:4, dataOffset:0, dataStride:12)
        let cSrc = SCNGeometrySource(data: Data(bytes: colArr, count: colArr.count*4),
            semantic:.color, vectorCount:2000, usesFloatComponents:true,
            componentsPerVector:4, bytesPerComponent:4, dataOffset:0, dataStride:16)
        let elem = SCNGeometryElement(indices:(0..<2000).map{UInt32($0)}, primitiveType:.point)
        elem.pointSize = 1.5; elem.minimumPointScreenSpaceRadius = 0.5
        elem.maximumPointScreenSpaceRadius = 3.0
        let starGeometry = SCNGeometry(sources:[pSrc,cSrc], elements:[elem])
        let mat = SCNMaterial()
        mat.lightingModel = .constant; mat.isDoubleSided = true
        mat.writesToDepthBuffer = false; mat.blendMode = .alpha
        starGeometry.materials = [mat]
        let sNode = SCNNode(geometry: starGeometry); sNode.name = "al_starfield"
        scene.rootNode.addChildNode(sNode)
        starFieldNode = sNode

        // Earth — blue sphere at origin (starting position scale)
        let earthGeo = SCNSphere(radius: 2.5)
        earthGeo.firstMaterial?.diffuse.contents  = UIColor(red:0.1, green:0.35, blue:0.7, alpha:1)
        earthGeo.firstMaterial?.emission.contents = UIColor(red:0.0, green:0.15, blue:0.4, alpha:0.4)
        earthGeo.firstMaterial?.lightingModel = .constant
        let eNode = SCNNode(geometry: earthGeo); eNode.name = "al_earth"
        eNode.simdPosition = SIMD3<Float>(0, -5, 0)  // below launch point
        scene.rootNode.addChildNode(eNode)
        earthNode = eNode

        // Moon — grey sphere, offset from Earth
        let moonGeo = SCNSphere(radius: 0.68)
        moonGeo.firstMaterial?.diffuse.contents  = UIColor(red:0.55, green:0.55, blue:0.58, alpha:1)
        moonGeo.firstMaterial?.lightingModel = .constant
        let mNode = SCNNode(geometry: moonGeo); mNode.name = "al_moon"
        mNode.simdPosition = SIMD3<Float>(9.7, 0, 0)  // ~0.97 AU in miniature
        scene.rootNode.addChildNode(mNode)
        moonNode = mNode

        // Target body placeholder — colored sphere, will move to Horizons position
        let body = ArcCelestialBody.catalog.first(where: { $0.id == targetBodyId })
        let tGeo = SCNSphere(radius: 0.5)
        tGeo.firstMaterial?.diffuse.contents  = body?.color ?? .red
        tGeo.firstMaterial?.emission.contents = (body?.color ?? .red).withAlphaComponent(0.5)
        tGeo.firstMaterial?.lightingModel = .constant
        // Pulse glow
        let pulse = CABasicAnimation(keyPath: "geometry.firstMaterial.emission.contents")
        pulse.fromValue = (body?.color ?? .red).withAlphaComponent(0.2)
        pulse.toValue   = (body?.color ?? .red).withAlphaComponent(0.8)
        pulse.duration  = 1.5; pulse.autoreverses = true; pulse.repeatCount = .infinity
        let tNode = SCNNode(geometry: tGeo); tNode.name = "al_target_\(targetBodyId)"
        tNode.addAnimation(pulse, forKey: "pulse")
        scene.rootNode.addChildNode(tNode)
        targetNode = tNode

        // Target label
        let lbl = SCNText(string: body?.name ?? targetBodyId, extrusionDepth: 0.01)
        lbl.font = UIFont.systemFont(ofSize: 0.5, weight: .bold)
        lbl.firstMaterial?.diffuse.contents  = UIColor.white
        lbl.firstMaterial?.emission.contents = UIColor.white.withAlphaComponent(0.6)
        lbl.firstMaterial?.lightingModel = .constant
        let lblNode = SCNNode(geometry: lbl)
        lblNode.position = SCNVector3(0.7, 0.6, 0); lblNode.scale = SCNVector3(0.6, 0.6, 0.6)
        tNode.addChildNode(lblNode)

        // Set scene background to deep space
        scene.background.contents = UIColor(red:0.01, green:0.01, blue:0.04, alpha:1)
        // Ambient light boost for space
        scene.lightingEnvironment.intensity = 0.3
    }

    private func removeSpaceEnvironment() {
        [starFieldNode, earthNode, moonNode, targetNode, trajectoryLine].forEach {
            $0?.removeFromParentNode()
        }
        starFieldNode = nil; earthNode = nil; moonNode = nil
        targetNode = nil; trajectoryLine = nil
        // Restore scene background
        scene?.background.contents = UIColor(red:0.04, green:0.06, blue:0.12, alpha:1)
        scene?.lightingEnvironment.intensity = 1.0
    }

    private func hideLabFloor(_ scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "floorNode" || node.name == "gridFloor" ||
               node.name?.contains("floor") == true || node.name?.contains("grid") == true {
                node.isHidden = true
                floorNode = node
            }
        }
    }

    private func showLabFloor() {
        floorNode?.isHidden = false
    }
}

// MARK: — Trajectory Scrubber Overlay (shown at top of 3D scene when linked)

struct ArcTrajectoryScrubberOverlay: View {
    @StateObject private var engine = ArcTrajectoryEngine.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var sliderVal: Double = 50

    var body: some View {
        VStack(spacing: 0) {
            if engine.isLinked {
                VStack(spacing: 4) {
                    // Top info bar
                    HStack(spacing: 8) {
                        // Mission phase badge
                        Text(engine.missionPhase)
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(phaseColor)
                            .clipShape(Capsule())

                        // Target
                        HStack(spacing: 3) {
                            Image(systemName: "scope").font(.system(size: 8))
                            Text(engine.targetBodyName)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(themeVM.accent)

                        Spacer()

                        // Distance
                        Text(engine.distanceToTargetAU < 0.01
                             ? String(format: "%.0f km", engine.distanceToTargetAU * 1.496e8)
                             : String(format: "%.4f AU", engine.distanceToTargetAU))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))

                        // Manual override indicator
                        if engine.isManualOverride {
                            Text("MANUAL")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.yellow.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }

                    // Scrubber + speed
                    HStack(spacing: 6) {
                        Text("PAST").font(.system(size: 6.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))

                        // Timeline scrubber
                        Slider(value: $sliderVal, in: 0...100)
                            .tint(themeVM.accent)
                            .onChange(of: sliderVal) { val in
                                // Map 0-100 → -50...+50 steps
                                engine.scrubberOffset = Int(val - 50)
                                ArcHorizonsEngine.shared.updateScrubPosition()
                            }

                        Text("FUTURE").font(.system(size: 6.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))

                        // Speed selector
                        Menu {
                            ForEach(ArcTrajectorySpeed.allCases) { spd in
                                Button(spd.rawValue) { engine.speed = spd }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(engine.speed.rawValue)
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 6))
                            }
                            .foregroundColor(themeVM.accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(themeVM.accent.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        // NOW button
                        Button("NOW") {
                            sliderVal = 50; engine.scrubberOffset = 0
                            ArcHorizonsEngine.shared.updateScrubPosition()
                        }
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                    }

                    // Epoch + velocity readout
                    HStack {
                        Image(systemName: "clock.fill").font(.system(size: 7))
                            .foregroundColor(themeVM.accent.opacity(0.5))
                        Text(engine.currentEpoch)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                        Text(String(format: "%.2f km/s", engine.approachVelocityKms))
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(themeVM.accent.opacity(0.7))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 8).padding(.top, 4)
            }

            Spacer()
        }
    }

    private var phaseColor: Color {
        switch engine.missionPhase {
        case "LAUNCH":      return .green
        case "ASCENT":      return Color(red:0.3,green:1,blue:0.4)
        case "CRUISE":      return .cyan
        case "APPROACH":    return .orange
        case "ORBITAL INS": return .yellow
        default:            return .gray
        }
    }
}

// MARK: — Body Selector Sheet

struct ArcTargetBodySelector: View {
    @StateObject private var engine = ArcTrajectoryEngine.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss
    let onSelect: (String) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(ArcCelestialBody.catalog, id: \.id) { body in
                    Button {
                        onSelect(body.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(body.symbol).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(body.name)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("ID: \(body.id) · r=\(String(format: "%.0f", body.meanRadiusKm)) km")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            Spacer()
                            if engine.targetBodyId == body.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(themeVM.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(red:0.04,green:0.06,blue:0.12))
            .navigationTitle("Select Target")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

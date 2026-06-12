import SwiftUI
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════
// ArcMantisNav — Mantis Navigation, 1:1 port of MN.html.
// Exact physics: baseGravity 0.00003 · drag 0.98 · baseMaxLift 0.03 ·
// thrustPower 0.01 · yawSpeed 0.1 · liftScalar 1e-6.
// Drone mode: thumbstick (yaw+forward) + thrust slider.
// Chemistry mode: oxidizer/fuel propellant physics + LAUNCH gate.
// Settings retained when toggling modes — all dynamically updatable.
// ═══════════════════════════════════════════════════════════════════

public struct MantisPropellant {
    public var psi: Double = 100, atmPsi: Double = 14.7
    public var dimX: Double = 1, dimY: Double = 1, dimZ: Double = 1
    public var massParts: Double = 10, weightPerPartG: Double = 1
    public var density: Double = 1, valveAngle: Double = 90
    public var maxFlow: Double = 500, tempF: Double = 72
    public var volume: Double { dimX * dimY * dimZ }
    public var totalPressure: Double { psi + atmPsi }
    public var totalWeightLbs: Double {
        (massParts * weightPerPartG * volume) / max(density, 0.0001) / 453.592
    }
}

@MainActor
public final class MantisNavModel: ObservableObject {
    // Mode + activation
    @Published public var isActive = false
    @Published public var chemistryMode = false      // default = drone mode
    // Drone controls
    @Published public var joyX: Double = 0           // −1…1
    @Published public var joyY: Double = 0
    @Published public var thrust: Double = 0         // 0…1
    // Chemistry — MULTIPLE propellant sets (oxidizer+fuel+chamber each),
    // all contributing to the launch force, each assignable to a 3D asset
    public struct PropSet: Identifiable {
        public let id = UUID()
        public var oxidizer = MantisPropellant()
        public var fuel = MantisPropellant(psi: 120, density: 0.8)
        public var depressPsi: Double = 0
        public var depressAtmPsi: Double = 14.7
        public var assetName: String? = nil      // nil = default drone
    }
    @Published public var propSets: [PropSet] = [PropSet()]
    @Published public var oxiFlow: Double = 0        // 0…100 (%)
    @Published public var fuelFlow: Double = 0
    @Published public var isLaunched = false
    // Vehicle: default drone or any imported 3D asset
    @Published public var vehicleAsset: String? = nil   // node-name prefix match
    // Camera modes — MN.html parity (follow = behind+above, asset faces away)
    public enum CamMode: String, CaseIterable {
        case orbit = "Orbit", follow = "Follow", fpv = "FPV",
             top = "Top", front = "Front", back = "Back",
             left = "Left", right = "Right"
    }
    @Published public var cameraMode: CamMode = .follow
    // Environment presets — MN.html envPhysics verbatim (g0 / P0)
    public enum MantisEnv: String, CaseIterable {
        case earth = "🌍 Earth", moon = "🌙 Moon", mars = "🔴 Mars",
             titan = "🟠 Titan", custom = "⚙ Custom"
        var g0: Double? { switch self {
            case .earth: return 9.81; case .moon: return 1.62
            case .mars: return 3.72; case .titan: return 1.35
            case .custom: return nil } }
        var psi: Double? { switch self {
            case .earth: return 14.7; case .moon: return 0.0000001
            case .mars: return 0.092; case .titan: return 21.3
            case .custom: return nil } }
    }
    @Published public var envPreset: MantisEnv = .earth
    @Published public var customG: Double = 9.81
    @Published public var customPsi: Double = 14.7
    public weak var labVM: ArcLabViewModel?
    public var gravityScale: Double {
        (envPreset.g0 ?? customG) / 9.81
    }
    public func applyEnv(_ e: MantisEnv) {
        envPreset = e
        // Sync into the ArcLake physics on the active tab — both ways
        if let g = e.g0 { labVM?.physics.gravity = g; customG = g }
        else { labVM?.physics.gravity = customG }
        if let p = e.psi { labVM?.physics.pressure = p; customPsi = p }
        else { labVM?.physics.pressure = customPsi }
    }
    // HUD readouts
    @Published public var hudForce: Double = 0
    @Published public var hudLift: Double = 0
    @Published public var hudVelH: Double = 0
    @Published public var hudVelV: Double = 0

    // MN.html physics constants — verbatim
    let baseGravity = 0.00003, drag = 0.98, baseMaxLift = 0.03
    let thrustPower = 0.01, yawSpeed = 0.1, liftScalar = 0.000001

    private var velocity = SIMD3<Double>(0, 0, 0)
    private weak var scene: SCNScene?
    private var timer: Timer?
    private var tickCount = 0

    public init() {}

    public func activate(in scene: SCNScene) {
        self.scene = scene
        buildDrone(in: scene)
        velocity = .zero
        isActive = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) {
            [weak self] _ in Task { @MainActor in self?.tick() }
        }
    }

    public func deactivate() {
        isActive = false
        timer?.invalidate(); timer = nil
        scene?.rootNode.childNode(withName: "mantis_drone", recursively: false)?
            .removeFromParentNode()
        joyX = 0; joyY = 0
    }

    // Stylized mantis drone — body + 4 rotor pods, banks with the stick
    private func buildDrone(in scene: SCNScene) {
        scene.rootNode.childNode(withName: "mantis_drone", recursively: false)?
            .removeFromParentNode()
        let root = SCNNode(); root.name = "mantis_drone"
        let mesh = SCNNode(); mesh.name = "mantis_mesh"
        let body = SCNNode(geometry: SCNCapsule(capRadius: 0.35, height: 1.6))
        body.eulerAngles.x = .pi / 2
        body.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.1, green: 0.85, blue: 0.7, alpha: 1)
        body.geometry?.firstMaterial?.emission.contents = UIColor(red: 0, green: 0.35, blue: 0.3, alpha: 1)
        mesh.addChildNode(body)
        for (sx, sz) in [(1.0,1.0),(1.0,-1.0),(-1.0,1.0),(-1.0,-1.0)] {
            let pod = SCNNode(geometry: SCNSphere(radius: 0.18))
            pod.position = SCNVector3(sx * 0.9, 0.1, sz * 0.9)
            pod.geometry?.firstMaterial?.diffuse.contents = UIColor.cyan
            pod.geometry?.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.7)
            mesh.addChildNode(pod)
        }
        root.addChildNode(mesh)
        root.position = SCNVector3(0, 0.5, 6)
        scene.rootNode.addChildNode(root)
    }

    // getPropData → force: potential · density · valveGate · flow%, clamped
    private func propForce(_ p: MantisPropellant, depress: Double, flowPct: Double) -> Double {
        var potential = p.totalPressure
        if depress < p.totalPressure {
            potential += (p.totalPressure - depress)             // pressure differential
        }
        let valveGate = p.valveAngle / 180.0
        return min(potential * p.density * valveGate * (flowPct / 100.0), p.maxFlow)
    }
    // Total force across ALL propellant sets at given throttle %
    func totalChemForce(oxiPct: Double, fuelPct: Double) -> Double {
        propSets.reduce(0) { acc, s in
            let d = s.depressPsi + s.depressAtmPsi
            return acc + propForce(s.oxidizer, depress: d, flowPct: oxiPct)
                       + propForce(s.fuel,     depress: d, flowPct: fuelPct)
        }
    }
    var totalWeightLbs: Double {
        max(propSets.reduce(0) { $0 + $1.oxidizer.totalWeightLbs + $1.fuel.totalWeightLbs }, 0.001)
    }
    // The vehicle node — default drone or selected imported asset
    func vehicleNode(in scene: SCNScene) -> SCNNode? {
        if let name = vehicleAsset,
           let n = scene.rootNode.childNodes.first(where: { $0.name?.contains(name) == true }) {
            return n
        }
        return scene.rootNode.childNode(withName: "mantis_drone", recursively: false)
    }
    // Imported asset names available for assignment
    public func importedAssets() -> [String] {
        guard let scene = scene else { return [] }
        return scene.rootNode.childNodes.compactMap { n in
            guard let nm = n.name,
                  nm.hasPrefix("imported_") || nm.hasPrefix("glb_import_") else { return nil }
            return nm
        }
    }
    // IDLE — drone: thrust = (g·2.2)/maxLift (MN.html line 1414), env-scaled.
    // Chemistry: solve flow% so totalForce·liftScalar == appliedGravity (hover).
    public func engageIdle() {
        let gEff = 0.5 * baseMaxLift * gravityScale
        if chemistryMode {
            let weightFactor = min(3.0, max(0.4, totalWeightLbs / 10.0))
            let needed = (gEff * weightFactor) / liftScalar
            let fullForce = totalChemForce(oxiPct: 100, fuelPct: 100)
            guard fullForce > 0 else { return }
            let pct = min(100, (needed / fullForce) * 100)
            oxiFlow = pct; fuelFlow = pct
            isLaunched = true
        } else {
            // hover thrust — exactly cancels gravity at this preset
            thrust = min(1.0, gEff / baseMaxLift)
        }
    }

    // The MN.html animate() physics — verbatim integration
    private func tick() {
        guard isActive, let scene,
              let drone = vehicleNode(in: scene)
        else { return }

        var lift = 0.0
        // Gravity rebalance: Earth hover sits at 50% throttle —
        // gEff = 0.5·baseMaxLift·gravityScale. Below mid-throttle the craft
        // visibly descends (gravity takes over); above it climbs.
        let g = 0.5 * baseMaxLift * gravityScale
        _ = baseGravity   // MN baseline retained for reference
        if chemistryMode {
            var totalForce = 0.0
            if isLaunched {                                       // LAUNCH gates the burn
                totalForce = totalChemForce(oxiPct: oxiFlow, fuelPct: fuelFlow)
            }
            lift = totalForce * liftScalar
            let weightFactor = min(3.0, max(0.4, totalWeightLbs / 10.0))
            velocity.y -= g * weightFactor                        // appliedGravity
            if tickCount % 6 == 0 { hudForce = totalForce }
        } else {
            lift = thrust * baseMaxLift
            velocity.y -= g
            if tickCount % 6 == 0 { hudForce = thrust * 100 }
        }
        if tickCount % 6 == 0 { hudLift = lift }
        velocity.y += lift

        // yaw: q = qY(−joy.x · yawSpeed) · q
        let qYaw = simd_quatf(angle: Float(-joyX * yawSpeed), axis: SIMD3<Float>(0, 1, 0))
        drone.simdOrientation = simd_normalize(qYaw * drone.simdOrientation)

        // thrustVector = (0,0,−1)·q · (joy.y · thrustPower)
        let fwd = drone.simdOrientation.act(SIMD3<Float>(0, 0, -1))
        let tv = SIMD3<Double>(Double(fwd.x), Double(fwd.y), Double(fwd.z)) * (joyY * thrustPower)
        velocity += tv
        velocity *= drag

        var p = SIMD3<Double>(Double(drone.simdPosition.x),
                              Double(drone.simdPosition.y),
                              Double(drone.simdPosition.z)) + velocity
        if p.y < 0.5 { p.y = 0.5; velocity.y = 0 }                // floor clamp
        drone.simdPosition = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))

        // visual bank: rz = −joy.x·0.5, rx = −joy.y·0.3
        if let mesh = drone.childNode(withName: "mantis_mesh", recursively: false) {
            mesh.eulerAngles.z = Float(-joyX * 0.5)
            mesh.eulerAngles.x = Float(-joyY * 0.3)
        }
        tickCount += 1
        if tickCount % 6 == 0 {   // 5 Hz readouts — keeps SwiftUI re-renders calm
            hudVelH = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
            hudVelV = velocity.y
        }

        // ── Camera modes — attach to the vehicle but ABIDE BY THE SCENE:
        //    horizon always level (world-up), offsets from the drone's YAW
        //    ONLY (never its pitch/roll), exactly like the turntable feel.
        if cameraMode != .orbit,
           let cam = scene.rootNode.childNode(withName: "arcCamera", recursively: false) {
            let dp = drone.simdPosition
            // Yaw-only frame: project drone forward onto the ground plane
            let rawFwd = drone.simdOrientation.act(SIMD3<Float>(0, 0, -1))
            var flatFwd = SIMD3<Float>(rawFwd.x, 0, rawFwd.z)
            if simd_length(flatFwd) < 1e-4 { flatFwd = SIMD3<Float>(0, 0, -1) }
            flatFwd = simd_normalize(flatFwd)
            let flatRight = simd_normalize(simd_cross(flatFwd, SIMD3<Float>(0, 1, 0)))

            func levelLook(from target: SIMD3<Float>, snap: Bool = false) {
                cam.simdPosition = snap ? target
                    : simd_mix(cam.simdPosition, target, SIMD3(repeating: 0.1))
                cam.look(at: SCNVector3(dp.x, dp.y, dp.z),
                         up: SCNVector3(0, 1, 0),
                         localFront: SCNVector3(0, 0, -1))   // world-up: zero roll
            }
            switch cameraMode {
            case .fpv:
                // first-person: at the nose, level gaze along the yaw heading
                cam.simdPosition = dp + flatFwd * 0.6 + SIMD3<Float>(0, 0.25, 0)
                let ahead = cam.simdPosition + flatFwd * 10
                cam.look(at: SCNVector3(ahead.x, ahead.y, ahead.z),
                         up: SCNVector3(0, 1, 0),
                         localFront: SCNVector3(0, 0, -1))
            case .top:   levelLook(from: dp + SIMD3<Float>(0, 20, 0) + flatFwd * 0.01)
            case .front: levelLook(from: dp + flatFwd * 15 + SIMD3<Float>(0, 2, 0))
            case .back:  levelLook(from: dp - flatFwd * 15 + SIMD3<Float>(0, 2, 0))
            case .left:  levelLook(from: dp - flatRight * 15 + SIMD3<Float>(0, 2, 0))
            case .right: levelLook(from: dp + flatRight * 15 + SIMD3<Float>(0, 2, 0))
            case .follow, .orbit:
                // semi-birdseye behind+above off the YAW heading — never rolls
                levelLook(from: dp - flatFwd * 10 + SIMD3<Float>(0, 4, 0))
            }
        }
    }
}

// MARK: — HUD OVERLAY (bottom-centered, semi-transparent — web parity)
struct MantisHUDOverlay: View {
    @ObservedObject var model: MantisNavModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Mode toggle — settings retained on switch
            HStack(spacing: 6) {
                modePill("DRONE", active: !model.chemistryMode) { model.chemistryMode = false }
                modePill("CHEMISTRY", active: model.chemistryMode) { model.chemistryMode = true }
                Spacer()
                Text(String(format: "H:%.2f V:%.2f", model.hudVelH, model.hudVelV))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Button { model.deactivate() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1)).clipShape(Circle())
                }
            }

            // Camera attachment — pills, MN.html upper-right HUD parity
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 8)).foregroundColor(.white.opacity(0.4))
                    ForEach(MantisNavModel.CamMode.allCases, id: \.self) { m in
                        Button { model.cameraMode = m } label: {
                            Text(m.rawValue)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(model.cameraMode == m ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(model.cameraMode == m ? themeVM.accent : Color.white.opacity(0.07))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Environment presets — Earth default; syncs ArcLake physics
            HStack(spacing: 4) {
                ForEach(MantisNavModel.MantisEnv.allCases, id: \.self) { e in
                    Button { model.applyEnv(e) } label: {
                        Text(e.rawValue)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(model.envPreset == e ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(model.envPreset == e ? themeVM.accent : Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }
                if model.envPreset == .custom {
                    TextField("g", value: $model.customG, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.accent).frame(width: 38)
                    TextField("psi", value: $model.customPsi, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.accent).frame(width: 38)
                }
            }

            if model.chemistryMode {
                HStack(alignment: .bottom, spacing: 18) {
                    chemThrottle("OXIDIZER", value: $model.oxiFlow, color: .cyan)
                    VStack(spacing: 6) {
                        Text(String(format: "Force: %.0f", model.hudForce))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                        Text(String(format: "Lift: %.4f", model.hudLift))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Button { model.engageIdle() } label: {
                            Text("IDLE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .frame(width: 110, height: 26)
                                .background(Color.yellow.opacity(0.85))
                                .clipShape(Capsule())
                        }
                        Button { model.isLaunched.toggle() } label: {
                            Text(model.isLaunched ? "ABORT" : "LAUNCH")
                                .font(.custom("Orbitron-Bold", size: 13))
                                .foregroundColor(model.isLaunched ? .white : .black)
                                .frame(width: 110, height: 46)
                                .background(model.isLaunched ? Color.red : Color.green)
                                .clipShape(Capsule())
                                .shadow(color: (model.isLaunched ? Color.red : .green).opacity(0.7), radius: 9)
                        }
                    }
                    chemThrottle("FUEL", value: $model.fuelFlow, color: .orange)
                }
            } else {
                HStack(alignment: .bottom, spacing: 26) {
                    MantisThumbStick(joyX: $model.joyX, joyY: $model.joyY, accent: themeVM.accent)
                    VStack(spacing: 4) {
                        Text(String(format: "Altitude: %.0f%%", model.thrust * 100))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                        droneThrottle
                        Button { model.engageIdle() } label: {
                            Text("IDLE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .frame(width: 120, height: 26)
                                .background(Color.yellow.opacity(0.85))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.02, green: 0.05, blue: 0.09).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(themeVM.accent.opacity(0.25), lineWidth: 0.8))
        .padding(.horizontal, 14).padding(.bottom, 10)
        .frame(maxWidth: 430)
    }

    private func modePill(_ t: String, active: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(active ? .black : .white.opacity(0.55))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? themeVM.accent : Color.white.opacity(0.07))
                .clipShape(Capsule())
        }
    }

    private var droneThrottle: some View {
        VStack(spacing: 3) {
            Slider(value: $model.thrust, in: 0...1).tint(themeVM.accent)
                .frame(width: 150)
            Text("THRUST").font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2)
        }
    }

    private func chemThrottle(_ label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f%%", value.wrappedValue))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Slider(value: value, in: 0...100).tint(color)
                .frame(width: 110)
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 116)
            Text(label).font(.system(size: 8, design: .monospaced))
                .foregroundColor(color.opacity(0.7)).tracking(1.5)
        }
    }
}

// Thumbstick — drag in a 92pt base, normalized −1…1, springs back (web parity)
struct MantisThumbStick: View {
    @Binding var joyX: Double
    @Binding var joyY: Double
    let accent: Color
    @State private var offset = CGSize.zero
    private let r: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.4), lineWidth: 1.5)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .frame(width: r * 2, height: r * 2)
            Circle().fill(accent.opacity(0.85))
                .frame(width: 38, height: 38)
                .shadow(color: accent.opacity(0.7), radius: 6)
                .offset(offset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let d = min(sqrt(v.translation.width * v.translation.width
                                   + v.translation.height * v.translation.height), r)
                    let a = atan2(v.translation.height, v.translation.width)
                    offset = CGSize(width: cos(a) * d, height: sin(a) * d)
                    joyX = Double(offset.width / r)
                    joyY = Double(-offset.height / r)   // up = forward, like the web
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { offset = .zero }
                    joyX = 0; joyY = 0
                }
        )
    }
}

// MARK: — SETTINGS SHEET (chemistry propellant configuration)
struct MantisSettingsSheet: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @ObservedObject var model: MantisNavModel        // direct observation —
    @Environment(\.dismiss) var dismiss              // adds/deletes update live

    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.039, blue: 0.063).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    HStack {
                        Text("MANTIS NAVIGATION")
                            .font(.custom("Orbitron-Bold", size: 13))
                            .foregroundColor(themeVM.accent).tracking(2)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }.padding(.top, 16)

                    // ── VEHICLE — default drone or any imported 3D asset ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VEHICLE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent).tracking(2)
                        Menu {
                            Button("Default Drone") { model.vehicleAsset = nil }
                            ForEach(model.importedAssets(), id: \.self) { a in
                                Button(a) { model.vehicleAsset = a }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "airplane")
                                    .font(.system(size: 10)).foregroundColor(themeVM.accent)
                                Text(model.vehicleAsset ?? "Default Drone")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8)).foregroundColor(.white.opacity(0.35))
                            }
                            .padding(9).background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text("Import GLB/USDZ assets from the toolbar, then pick one here — or fly the built-in drone.")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(12).background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // ── PROPELLANT SETS — oxidizer + fuel + chamber per set,
                    //    all summing into the launch force ──
                    ForEach(model.propSets) { s in
                        setGroup(s.id)
                    }
                    Button {
                        model.propSets.append(MantisNavModel.PropSet())
                    } label: {
                        Label("ADD PROPELLANT SET", systemImage: "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(themeVM.accent.opacity(0.35),
                                        style: StrokeStyle(lineWidth: 1, dash: [5])))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        model.labVM = labVM
                        model.applyEnv(model.envPreset)
                        model.activate(in: labVM.scene)
                        dismiss()
                    } label: {
                        Text("ACTIVATE MANTIS NAVIGATION")
                            .font(.custom("Orbitron-Bold", size: 12))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(themeVM.accent).clipShape(Capsule())
                            .shadow(color: themeVM.accent.opacity(0.6), radius: 8)
                    }
                    Spacer().frame(height: 26)
                }.padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    // Bounds-safe accessors keyed by set id — survives deletion mid-render
    private func setIndex(_ id: UUID) -> Int? {
        model.propSets.firstIndex(where: { $0.id == id })
    }
    private func propBinding(_ id: UUID,
                             _ keyPath: WritableKeyPath<MantisNavModel.PropSet, MantisPropellant>)
        -> Binding<MantisPropellant> {
        Binding(
            get: { setIndex(id).map { model.propSets[$0][keyPath: keyPath] } ?? MantisPropellant() },
            set: { v in if let i = setIndex(id) { model.propSets[i][keyPath: keyPath] = v } })
    }
    private func doubleBinding(_ id: UUID,
                               _ keyPath: WritableKeyPath<MantisNavModel.PropSet, Double>)
        -> Binding<Double> {
        Binding(
            get: { setIndex(id).map { model.propSets[$0][keyPath: keyPath] } ?? 0 },
            set: { v in if let i = setIndex(id) { model.propSets[i][keyPath: keyPath] = v } })
    }

    @ViewBuilder
    private func setGroup(_ sid: UUID) -> some View {
        let i = setIndex(sid) ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SET \(i + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent).tracking(2)
                Spacer()
                // Per-set 3D asset assignment
                Menu {
                    Button("Default Drone") {
                        if let k = setIndex(sid) { model.propSets[k].assetName = nil } }
                    ForEach(model.importedAssets(), id: \.self) { a in
                        Button(a) {
                            if let k = setIndex(sid) { model.propSets[k].assetName = a } }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "cube").font(.system(size: 8))
                        Text((setIndex(sid).map { model.propSets[$0].assetName } ?? nil) ?? "Default Drone")
                            .font(.system(size: 8.5, design: .monospaced)).lineLimit(1)
                    }
                    .foregroundColor(themeVM.accent.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06)).clipShape(Capsule())
                }
                if model.propSets.count > 1 {
                    Button {
                        // remove by id — index-free, crash-free
                        model.propSets.removeAll { $0.id == sid }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
            propCard("OXIDIZER", p: propBinding(sid, \.oxidizer))
            propCard("FUEL",     p: propBinding(sid, \.fuel))
            VStack(alignment: .leading, spacing: 7) {
                Text("PRESSURE CHAMBER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45)).tracking(2)
                numRow("Chamber psi", v: doubleBinding(sid, \.depressPsi))
                numRow("Atm psi",     v: doubleBinding(sid, \.depressAtmPsi))
            }
            .padding(10).background(Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(themeVM.accent.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func propCard(_ title: String, p: Binding<MantisPropellant>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent).tracking(2)
                Spacer()
                Text(String(format: "Vol %.2f · P %.1f · Wt %.4f lbs",
                            p.wrappedValue.volume, p.wrappedValue.totalPressure,
                            p.wrappedValue.totalWeightLbs))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            numRow("psi", v: p.psi); numRow("Atm psi", v: p.atmPsi)
            HStack(spacing: 8) {
                numRow("X", v: p.dimX); numRow("Y", v: p.dimY); numRow("Z", v: p.dimZ)
            }
            numRow("Mass parts", v: p.massParts)
            numRow("Wt/part g", v: p.weightPerPartG)
            numRow("Density", v: p.density)
            numRow("Valve °(0–180)", v: p.valveAngle)
            numRow("Max flow", v: p.maxFlow)
        }
        .padding(12).background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func numRow(_ label: String, v: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
            Spacer()
            TextField("", value: v, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeVM.accent)
                .frame(width: 72)
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

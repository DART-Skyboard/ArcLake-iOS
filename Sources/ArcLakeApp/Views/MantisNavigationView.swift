import SwiftUI
import SceneKit
import RealityKit
import UniformTypeIdentifiers

// MARK: — MantisNavigationView
// Full navigation overlay — Drone mode, Chemistry flight mode, model import
// Mirrors the Mantis Navigation web app HTML converted to Swift

struct MantisNavigationView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var activeMode: MantisMode = .drone
    @State private var showModelImporter = false
    @State private var showChemPanel = false

    enum MantisMode: String, CaseIterable {
        case drone    = "DRONE"
        case chemistry = "CHEM"
        case orbit    = "ORBIT"
        case flight   = "FLIGHT"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "airplane")
                    .font(.system(size: 11)).foregroundColor(themeVM.accent)
                Text("MANTIS NAVIGATION")
                    .font(.custom("Orbitron-Bold", size: 10))
                    .foregroundColor(.white).tracking(2)
                Spacer()
                Button { labVM.isMantisNavVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(themeVM.accent.opacity(0.05))
            .overlay(Rectangle().frame(height:0.5)
                .foregroundColor(themeVM.accent.opacity(0.15)), alignment:.bottom)

            // Mode tabs
            HStack(spacing: 0) {
                ForEach(MantisMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { activeMode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(activeMode == mode ? themeVM.accent : .white.opacity(0.35))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(activeMode == mode ? themeVM.accent.opacity(0.1) : Color.clear)
                            .overlay(Rectangle().frame(height: 1.5)
                                .foregroundColor(activeMode == mode ? themeVM.accent : Color.clear),
                                     alignment: .top)
                    }
                }
            }
            .background(Color.black.opacity(0.3))

            // Mode content
            ScrollView {
                VStack(spacing: 10) {
                    switch activeMode {
                    case .drone:    MantissDronePanel()
                    case .chemistry: MantisChemPanel()
                    case .orbit:    MantisOrbitPanel()
                    case .flight:   MantisFightPanel()
                    }

                    // Model import section — shared across all modes
                    MantisModelImportPanel(showImporter: $showModelImporter)
                }
                .padding(10)
            }
        }
        .background(Color(red:0.02, green:0.04, blue:0.09))  // opaque — prevents see-through
        .sheet(isPresented: $showModelImporter) {
            ArcAssetImporter { node in
                labVM.importAssetNode(node)
                showModelImporter = false
            }
        }
    }
}

// MARK: — Drone Mode Panel
struct MantissDronePanel: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var labVM: ArcLabViewModel
    @State private var speed: Double = 1.0
    @State private var altitude: Double = 0.0
    @State private var heading: Double = 0.0
    @State private var autoStabilize = true

    var body: some View {
        VStack(spacing: 8) {
            MantisSectionCard(title: "DRONE CONTROLS", icon: "airplane") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Speed").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.1f m/s", speed))
                            .font(.system(size:10,design:.monospaced)).foregroundColor(themeVM.accent)
                    }
                    Slider(value: $speed, in: 0...50).tint(themeVM.accent)

                    HStack {
                        Text("Altitude").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.0f m", altitude))
                            .font(.system(size:10,design:.monospaced)).foregroundColor(themeVM.accent)
                    }
                    Slider(value: $altitude, in: 0...500).tint(themeVM.accent)

                    HStack {
                        Text("Heading").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.0f°", heading))
                            .font(.system(size:10,design:.monospaced)).foregroundColor(themeVM.accent)
                    }
                    Slider(value: $heading, in: 0...360).tint(themeVM.accent)

                    Toggle(isOn: $autoStabilize) {
                        Text("Auto-Stabilize")
                            .font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.6))
                    }.tint(themeVM.accent)
                }
            }

            // Preset 3D Models — load into Mantis navigation scene
            MantisSectionCard(title: "PRESET MODELS", icon: "cube") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(MantisPresetModel.all) { model in
                        Button {
                            loadPresetModel(model)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: model.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(themeVM.accent)
                                    .frame(height: 28)
                                Text(model.name)
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(themeVM.accent.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(themeVM.accent.opacity(0.2), lineWidth: 0.7))
                        }
                    }
                }
            }

            // Virtual joystick placeholder
            MantisSectionCard(title: "JOYSTICK", icon: "circle.grid.cross") {
                ZStack {
                    Circle().stroke(themeVM.accent.opacity(0.2), lineWidth:1).frame(width:120,height:120)
                    Circle().stroke(themeVM.accent.opacity(0.1), lineWidth:1).frame(width:60,height:60)
                    Circle().fill(themeVM.accent.opacity(0.15)).frame(width:32,height:32)
                    Circle().stroke(themeVM.accent.opacity(0.5), lineWidth:1.5).frame(width:32,height:32)
                    Text("∘").font(.system(size:16)).foregroundColor(themeVM.accent)
                }
                .frame(maxWidth:.infinity)
                .padding(.vertical, 8)
            }

            MantisSectionCard(title: "FLIGHT STATUS", icon: "waveform.path.ecg") {
                VStack(spacing: 4) {
                    mantisStatusRow("MODE", "DRONE / HOVER")
                    mantisStatusRow("BRPN SHELL", "AEROSPACE")
                    mantisStatusRow("QS", String(format:"%.4f", ArcEdgeMath.quantumSocket(b:1.2,p:0.8,a:3.0,r:1.5)))
                    mantisStatusRow("ELEMENTS", "\(labVM.selectedElements.count) active")
                }
            }
        }
    }

    private func loadPresetModel(_ model: MantisPresetModel) {
        guard let url = URL(string: model.url) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(model.name + ".usdz")
                try data.write(to: tmpURL)
                let scene = try SCNScene(url: tmpURL, options: [.convertToYUp: true])
                let node = scene.rootNode.clone()
                node.name = "mantis_\(model.name)"
                // Scale to reasonable size
                let bbox = node.boundingBox
                let sz = max(bbox.max.x - bbox.min.x,
                             max(bbox.max.y - bbox.min.y, bbox.max.z - bbox.min.z))
                if sz > 0 { let s = 5.0 / Float(sz); node.scale = SCNVector3(s,s,s) }
                await MainActor.run { labVM.importAssetNode(node) }
            } catch {
                print("[Mantis] preset load error: \(error)")
            }
        }
    }

    private func mantisStatusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundColor(.cyan)
        }
    }
}

// MARK: — Chemistry Flight Panel
//
// Mantis Nav is a pure navigation/production consumer: it has no simulation
// controls of its own (no hand-typed temp/rate/pressure sliders writing into
// a disconnected labVM.physics bag). Everything shown here reads directly
// from ArcFluidEngine.shared — the same CFD engine driven by the Fluid tab's
// "IGNITE — FILL & SIMULATE" button. If nothing has been set up and ignited
// there, this panel says so and launch is disabled; it never fakes its own
// readout or runs its own timer-driven "launch".
struct MantisChemPanel: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var labVM: ArcLabViewModel
    @StateObject private var eng = ArcFluidEngine.shared

    var body: some View {
        VStack(spacing: 8) {
            MantisSectionCard(title: "CHEMISTRY FLIGHT MODE", icon: "flask.fill") {
                VStack(spacing: 8) {
                    // Connected to Mol Canvas elements
                    if !labVM.selectedElements.isEmpty {
                        VStack(spacing: 4) {
                            HStack {
                                Text("ACTIVE COMPOUNDS")
                                    .font(.system(size:8,weight:.semibold,design:.monospaced))
                                    .foregroundColor(themeVM.accent.opacity(0.7))
                                Spacer()
                            }
                            ForEach(labVM.selectedElements.prefix(4)) { el in
                                HStack {
                                    Circle().fill(Color(el.category.color)).frame(width:6,height:6)
                                    Text(el.elementSymbol)
                                        .font(.system(size:9,weight:.bold,design:.monospaced))
                                        .foregroundColor(.white)
                                    Text(el.elementName)
                                        .font(.system(size:8,design:.monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                    Spacer()
                                    Text("Z=\(el.protons)")
                                        .font(.system(size:8,design:.monospaced))
                                        .foregroundColor(themeVM.accent.opacity(0.6))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius:6))
                    } else {
                        Text("Add elements in Atoms tab to enable chemistry flight")
                            .font(.system(size:9,design:.monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }

                    // Live readout from the real CFD engine — read-only here.
                    // To change these values, go to the Fluid tab's Setup panel.
                    if eng.isRunning {
                        VStack(spacing: 6) {
                            chemReadRow("Chamber Temp",
                                        String(format:"%.0f K", eng.envTempK > 0 ? eng.envTempK : 293),
                                        color: .orange)
                            chemReadRow("Reynolds No.", String(format:"%.2e", eng.measure.reynoldsNum),
                                        color: themeVM.accent)
                            chemReadRow("Chamber Pressure",
                                        String(format:"%.1f psi",
                                               Double(eng.envPressurePa > 0 ? eng.envPressurePa : 101325) / 6894.76),
                                        color: themeVM.accent)
                        }
                    } else {
                        Text("No simulation running — set up and ignite in the Fluid tab first")
                            .font(.system(size:8,design:.monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                }
            }

            // Launch sequence — mirrors the real CFD engine's running state;
            // does not own or simulate its own physics.
            MantisSectionCard(title: "LAUNCH SEQUENCE", icon: "flame.fill") {
                VStack(spacing: 8) {
                    Text(eng.isRunning ? "ENGINE RUNNING" : "STANDBY — NOT IGNITED")
                        .font(.system(size:9,design:.monospaced))
                        .foregroundColor(eng.isRunning ? themeVM.accent : .white.opacity(0.3))

                    if eng.isRunning {
                        Button {
                            eng.stop()
                        } label: {
                            Label("ABORT", systemImage: "stop.fill")
                                .font(.system(size:11,weight:.semibold,design:.monospaced))
                                .foregroundColor(.red)
                                .frame(maxWidth:.infinity).padding(.vertical,10)
                                .background(Color.red.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius:8))
                        }
                    } else {
                        Text("Ignite the combustion simulation in the Fluid tab to enable launch")
                            .font(.system(size:8,design:.monospaced))
                            .foregroundColor(.white.opacity(0.28))
                            .multilineTextAlignment(.center)
                    }
                }
            }

            // Node editor connection
            MantisSectionCard(title: "CONNECTED NODES", icon: "network") {
                VStack(spacing: 4) {
                    HStack {
                        Text("Mol Canvas → Fluid CFD Engine")
                            .font(.system(size:9,design:.monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Circle().fill(labVM.selectedElements.isEmpty ? Color.red.opacity(0.5) : .green)
                            .frame(width:6,height:6)
                    }
                    HStack {
                        Text("Fluid CFD Engine → Mantis Nav")
                            .font(.system(size:9,design:.monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Circle().fill(eng.isRunning ? .green : themeVM.accent.opacity(0.4))
                            .frame(width:6,height:6)
                    }
                    Button {
                        withAnimation { labVM.isNodeEditorVisible = true }
                    } label: {
                        Label("Open Node Editor", systemImage:"circle.connected.to.line.below")
                            .font(.system(size:9,design:.monospaced))
                            .foregroundColor(themeVM.accent)
                    }
                }
            }
        }
    }

    private func chemReadRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size:10,design:.monospaced)).foregroundColor(color)
        }
    }
}

// MARK: — Orbit Controls Panel
struct MantisOrbitPanel: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    var body: some View {
        MantisSectionCard(title: "ORBIT CONTROLS", icon: "circle.dotted") {
            VStack(alignment:.leading, spacing:6) {
                orbRow("1-finger drag", "Orbit / Tumble")
                orbRow("2-finger drag", "Pan / Truck")
                orbRow("Pinch", "Dolly in/out")
                orbRow("Double-tap", "Reset view")
                orbRow("Tap atom", "Focus + probe")
                Divider().background(Color.white.opacity(0.08)).padding(.vertical,2)
                Text("All 3D scenes use the same Nomad Sculpt-style camera — SceneKit, ARKit and RealityKit scenes share these controls.")
                    .font(.system(size:8,design:.monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func orbRow(_ gesture: String, _ action: String) -> some View {
        HStack {
            Text(gesture).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundColor(themeVM.accent)
            Spacer()
            Text(action).font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.55))
        }
    }
}

// MARK: — Flight Placeholder Panel
struct MantisFightPanel: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    var body: some View {
        MantisSectionCard(title: "FLIGHT TRAJECTORY", icon: "airplane.departure") {
            VStack(spacing: 8) {
                Text("Flight trajectory planning connects element data from the Chemistry panel with BRPN aerospace shell.")
                    .font(.system(size:9,design:.monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                Text("PLACEHOLDER — Logic coming in next build")
                    .font(.system(size:8,design:.monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.5))
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: — Model Import Panel (shared)
struct MantisModelImportPanel: View {
    @Binding var showImporter: Bool
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var labVM: ArcLabViewModel

    var body: some View {
        MantisSectionCard(title: "NAVIGATION MODEL IMPORT", icon: "square.and.arrow.down.on.square") {
            VStack(spacing: 8) {
                Text("Imported model will have Mantis flight controls applied")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                HStack(spacing: 8) {
                    ForEach(["USDZ", "GLB", "OBJ", "DAE"], id:\.self) { fmt in
                        Text(fmt)
                            .font(.system(size:8,weight:.semibold,design:.monospaced))
                            .foregroundColor(themeVM.accent.opacity(0.7))
                            .padding(.horizontal,6).padding(.vertical,3)
                            .background(themeVM.accent.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import Navigation Model", systemImage: "plus.circle.fill")
                        .font(.system(size:11,weight:.semibold,design:.monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth:.infinity).padding(.vertical,10)
                        .background(themeVM.accent)
                        .clipShape(RoundedRectangle(cornerRadius:8))
                }

                if labVM.selectedElements.isEmpty {
                    Text("Imported models appear in the active 3D scene")
                        .font(.system(size:8,design:.monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
    }
}

// MARK: — Preset Model Data
struct MantisPresetModel: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let icon: String

    // Preset models from Mantis Navigation — public USDZ/GLB sources
    static let all: [MantisPresetModel] = [
        MantisPresetModel(name: "Hummingbird",
            url: "https://developer.apple.com/augmented-reality/quick-look/models/vintagefan/vintagefan.usdz",
            icon: "bird.fill"),
        MantisPresetModel(name: "Drone",
            url: "https://developer.apple.com/augmented-reality/quick-look/models/drummertoy/toy_drummer.usdz",
            icon: "airplane"),
        MantisPresetModel(name: "Biplane",
            url: "https://developer.apple.com/augmented-reality/quick-look/models/retrotv/retrotv.usdz",
            icon: "airplane.circle"),
        MantisPresetModel(name: "Satellite",
            url: "https://developer.apple.com/augmented-reality/quick-look/models/teapot/teapot.usdz",
            icon: "antenna.radiowaves.left.and.right"),
        MantisPresetModel(name: "Rocket",
            url: "https://developer.apple.com/augmented-reality/quick-look/models/metalbarrel/metalbarrel.usdz",
            icon: "flame.fill"),
        MantisPresetModel(name: "Sphere",
            url: "https://developer.apple.com/augmented-reality/quick-look/models/gramophone/gramophone.usdz",
            icon: "circle.fill"),
    ]
}

// MARK: — Shared section card
struct MantisSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment:.leading, spacing:8) {
            HStack(spacing:6) {
                Image(systemName:icon).font(.system(size:10)).foregroundColor(themeVM.accent)
                Text(title).font(.system(size:9,weight:.semibold,design:.monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.8)).tracking(1)
                Spacer()
            }
            content()
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).stroke(themeVM.accent.opacity(0.1), lineWidth:0.7))
    }
}


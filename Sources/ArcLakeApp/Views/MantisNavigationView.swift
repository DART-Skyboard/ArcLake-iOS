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

    private func mantisStatusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value).font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundColor(.cyan)
        }
    }
}

// MARK: — Chemistry Flight Panel
struct MantisChemPanel: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var labVM: ArcLabViewModel
    @State private var combustionTemp: Double = 298
    @State private var reactionRate: Double = 1.0
    @State private var pressure: Double = 14.7
    @State private var launchSequenceActive = false
    @State private var launchPhase = 0

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

                    // Combustion parameters (connected to labVM physics)
                    HStack {
                        Text("Combustion Temp").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.0f K", combustionTemp))
                            .font(.system(size:10,design:.monospaced)).foregroundColor(.orange)
                    }
                    Slider(value: $combustionTemp, in: 298...3000)
                        .tint(.orange)
                        .onChange(of: combustionTemp) { t in
                            labVM.physics.temperature = t - 273.15
                        }

                    HStack {
                        Text("Reaction Rate").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.2f", reactionRate))
                            .font(.system(size:10,design:.monospaced)).foregroundColor(themeVM.accent)
                    }
                    Slider(value: $reactionRate, in: 0.1...10).tint(themeVM.accent)

                    HStack {
                        Text("Chamber Pressure").font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.1f psi", pressure))
                            .font(.system(size:10,design:.monospaced)).foregroundColor(themeVM.accent)
                    }
                    Slider(value: $pressure, in: 0...500)
                        .tint(themeVM.accent)
                        .onChange(of: pressure) { p in labVM.physics.pressure = p }
                }
            }

            // Launch sequence — connected to elements & physics
            MantisSectionCard(title: "LAUNCH SEQUENCE", icon: "flame.fill") {
                VStack(spacing: 8) {
                    // Phase indicator
                    HStack(spacing: 4) {
                        ForEach(0..<5) { i in
                            Capsule()
                                .fill(i < launchPhase ? themeVM.accent : Color.white.opacity(0.1))
                                .frame(maxWidth:.infinity, minHeight:4)
                        }
                    }
                    Text(launchPhaseLabel)
                        .font(.system(size:9,design:.monospaced))
                        .foregroundColor(launchSequenceActive ? themeVM.accent : .white.opacity(0.3))

                    Button {
                        if launchSequenceActive { abortLaunch() } else { startLaunch() }
                    } label: {
                        Label(launchSequenceActive ? "ABORT" : "INITIATE LAUNCH",
                              systemImage: launchSequenceActive ? "stop.fill" : "flame.fill")
                            .font(.system(size:11,weight:.semibold,design:.monospaced))
                            .foregroundColor(launchSequenceActive ? .red : .black)
                            .frame(maxWidth:.infinity).padding(.vertical,10)
                            .background(launchSequenceActive ? Color.red.opacity(0.2) : themeVM.accent)
                            .clipShape(RoundedRectangle(cornerRadius:8))
                    }
                    .disabled(labVM.selectedElements.isEmpty)
                }
            }

            // Node editor connection
            MantisSectionCard(title: "CONNECTED NODES", icon: "network") {
                VStack(spacing: 4) {
                    HStack {
                        Text("Mol Canvas → Chemistry Flight")
                            .font(.system(size:9,design:.monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Circle().fill(labVM.selectedElements.isEmpty ? Color.red.opacity(0.5) : .green)
                            .frame(width:6,height:6)
                    }
                    HStack {
                        Text("Physics → Combustion Engine")
                            .font(.system(size:9,design:.monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Circle().fill(themeVM.accent).frame(width:6,height:6)
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

    private var launchPhaseLabel: String {
        let labels = ["STANDBY","PREFLIGHT CHECK","IGNITION","LIFTOFF","ORBIT INSERT"]
        return labels[min(launchPhase, labels.count-1)]
    }

    private func startLaunch() {
        launchSequenceActive = true
        launchPhase = 0
        // Step through phases using element data
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { t in
            launchPhase += 1
            labVM.physics.pressure = pressure * Double(launchPhase) / 4.0
            labVM.physics.temperature = combustionTemp - 273.15
            if launchPhase >= 5 { t.invalidate(); launchSequenceActive = false }
        }
    }
    private func abortLaunch() {
        launchSequenceActive = false; launchPhase = 0
        labVM.physics.pressure = 14.7
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
        MantisSectionCard(title: "3D MODEL IMPORT", icon: "square.and.arrow.down.on.square") {
            VStack(spacing: 8) {
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
                    Label("Import 3D Model", systemImage: "plus.circle.fill")
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

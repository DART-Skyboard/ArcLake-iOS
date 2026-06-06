import SwiftUI
import SceneKit
import UniformTypeIdentifiers

// MARK: — DART Root View
// Premium redesign of Arc Lake DART
// Aesthetic: Deep space / bioluminescent / precision instrument

public struct DARTRootView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var authVM: ArcAuthViewModel
    @State private var showProfile  = false
    @State private var showAppleAccountSheet = false
    @State private var showSupportSheet = false
    @State private var showAR       = false
    @State private var showImporter = false
    @State private var showFeedback = false
    @State private var selectedTab: DARTTab = .scene

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Deep space background
                DARTBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Top chrome ─────────────────────────────────
                    DARTTopBar(showProfile: $showProfile, showAR: $showAR, showImporter: $showImporter, showFeedback: $showFeedback)

                    // ── Scene tab bar ───────────────────────────────
                    DARTSceneTabBar()

                    // ── Main viewport ───────────────────────────────
                    ZStack {
                        ArcSceneView()
                            .frame(height: geo.size.height * 0.44)

                        // CFD badge
                        if labVM.isCFDActive {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    DARTCFDBadge()
                                        .padding(.trailing, 16)
                                        .padding(.bottom, 12)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.leading, 80)
                                }
                            }
                        }

                        // AtomInfoCard moved to top-level ZStack as draggable panel
                    }
                    .frame(height: geo.size.height * 0.44)

                    // ── Sigma HUD strip ─────────────────────────────
                    DARTSigmaStrip()

                    // ── Bottom panel ────────────────────────────────
                    DARTBottomPanel()
                }

                // No dim overlay — each panel has its own close button

                // ── Overlay panels ──────────────────────────────────
                ArcOverlays(geoSize: geo.size)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8),
                               value: labVM.isNodeEditorVisible)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8),
                               value: labVM.isPeriodicTableVisible)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8),
                               value: labVM.isMolCanvasVisible)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8),
                               value: labVM.isMantisNavVisible)

                // AtomInfoCard is now in ArcOverlays — same layer as all panels
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProfile) { ArcProfileSheet() }

        .overlay(alignment: .bottomTrailing) {
            AutumnOverlay()
        }
        .fullScreenCover(isPresented: $showAR) {
            ZStack(alignment: .topTrailing) {
                ArcARView()
                    .environmentObject(labVM)
                    .ignoresSafeArea()
                Button {
                    showAR = false
                } label: {
                    Label("Exit AR", systemImage: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundColor(.white)
                }
                .padding(.top, 56).padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
                .environmentObject(themeVM)
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showImporter) {
            ArcAssetImporter { node in
                labVM.importAssetNode(node)
                showImporter = false
            }
        }
    }
}

// MARK: — Background
struct DARTBackground: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.020, blue: 0.042)
            // Radial glow at top center
            RadialGradient(
                colors: [
                    Color(red: 0.0, green: 0.56, blue: 0.78).opacity(0.12),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 400
            )
            // Bottom vignette
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.4)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
}

// MARK: — Top Bar
struct DARTTopBar: View {
    @Binding var showProfile: Bool
    @Binding var showAR: Bool
    @Binding var showImporter: Bool
    @Binding var showFeedback: Bool
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var authVM: ArcAuthViewModel

    var body: some View {
        HStack(spacing: 0) {
            // DART wordmark
            HStack(spacing: 6) {
                // Hummingbird accent mark
                Image(systemName: "bird.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeVM.accent, Color(red:0.4, green:0.9, blue:0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("ArcLake")
                    .font(.custom("Orbitron-Bold", size: 12))
                    .foregroundColor(.white)
                    .tracking(1)
                    .lineLimit(1)
                    .fixedSize()
                Text("v1.45")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.leading, 2)
            }
            .padding(.leading, 16)

            Spacer()

            // Center status cluster
            HStack(spacing: 10) {
                if labVM.isCFDActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red:0.2,green:0.7,blue:1.0))
                            .frame(width: 5, height: 5)
                            .opacity(0.9)
                        Text("CFD")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red:0.2,green:0.7,blue:1.0))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(red:0.2,green:0.7,blue:1.0).opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(red:0.2,green:0.7,blue:1.0).opacity(0.3), lineWidth: 0.5))
                }

                Text("\(labVM.selectedElements.count) atoms")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            // Right controls — scrollable so all buttons always accessible
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Grid master toggle — also toggles axis indicators
                    DARTIconButton(icon: "number",
                        active: labVM.showGrid && (labVM.showGridXZ || labVM.showGridXY || labVM.showGridYZ)) {
                        labVM.showGrid.toggle()
                        if !labVM.showGrid { labVM.showAxisIndicators = false }
                        else               { labVM.showAxisIndicators = true  }
                        labVM.rebuildGrid()
                    }
                    // Axis indicator toggle (X/Y/Z colored arrows)
                    DARTIconButton(icon: "arrow.up.and.down.and.arrow.left.and.right",
                        active: labVM.showAxisIndicators) {
                        labVM.toggleAxisIndicators()
                    }
                    // Per-plane grid toggles — always visible (not conditional)
                    DARTIconButton(icon: "square.split.bottomrightquarter",
                                   active: labVM.showGridXZ) {
                        labVM.toggleGridPlane("xz")
                    }
                    DARTIconButton(icon: "square.split.2x2",
                                   active: labVM.showGridXY) {
                        labVM.toggleGridPlane("xy")
                    }
                    DARTIconButton(icon: "square.split.1x2",
                                   active: labVM.showGridYZ) {
                        labVM.toggleGridPlane("yz")
                    }
                    DARTIconButton(icon: "tablecells",
                                   active: labVM.isPeriodicTableVisible) {
                        withAnimation(.spring()) { labVM.isPeriodicTableVisible.toggle() }
                    }
                    DARTIconButton(icon: "network",
                                   active: labVM.isNodeEditorVisible) {
                        withAnimation(.spring()) { labVM.isNodeEditorVisible.toggle() }
                    }
                    DARTIconButton(icon: "paintpalette", active: themeVM.current != .stealth) {
                        withAnimation(.easeInOut(duration: 0.25)) { themeVM.cycle() }
                    }
                    DARTIconButton(icon: "square.and.arrow.down", active: false) {
                        showImporter = true
                    }
                    DARTIconButton(icon: "arkit", active: showAR) {
                        showAR.toggle()
                    }
                    // Mantis Navigation
                    DARTIconButton(icon: "airplane", active: labVM.isMantisNavVisible) {
                        withAnimation(.spring()) { labVM.isMantisNavVisible.toggle() }
                    }
                    DARTIconButton(icon: "bubble.left.and.bubble.right", active: false) {
                        showFeedback = true
                    }
                    // Avatar
                    Button { showProfile = true } label: {
                        ZStack {
                            Circle()
                                .fill(themeVM.accent.opacity(0.12))
                                .frame(width: 30, height: 30)
                            Circle()
                                .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.8)
                                .frame(width: 30, height: 30)
                            if let avatarURL = authVM.githubAvatarURL {
                                AsyncImage(url: avatarURL) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                            .frame(width: 28, height: 28)
                                            .clipShape(Circle())
                                    } else {
                                        Text(authVM.username.prefix(1).uppercased())
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(themeVM.accent)
                                    }
                                }
                            } else {
                                Text(authVM.username.prefix(1).uppercased())
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeVM.accent)
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
            }
            // Fixed width so it doesn't push wordmark off-screen
            .frame(maxWidth: UIScreen.main.bounds.width * 0.62)
        }
        .frame(height: 48)
        .background(
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle().frame(height: 0.5)
                .foregroundColor(Color(red:0.0,green:0.7,blue:1.0).opacity(0.2)),
            alignment: .bottom
        )
    }
}

// MARK: — Scene Tab Bar
struct DARTSceneTabBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(labVM.sceneTabs_data.indices, id: \.self) { i in
                    DARTSceneTab(index: i)
                }
                // Add tab
                Button { labVM.addSceneTab() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(themeVM.accent.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(themeVM.accent.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .background(Color.black.opacity(0.3))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.06)), alignment: .bottom)
    }
}

struct DARTSceneTab: View {
    let index: Int
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var isActive: Bool { labVM.activeTabIndex == index }
    var isCFD: Bool { index < labVM.sceneTabsCFD.count ? labVM.sceneTabsCFD[index] : false }
    var name: String { index < labVM.sceneTabs_data.count ? labVM.sceneTabs_data[index] : "" }

    var body: some View {
        HStack(spacing: 4) {
            if isCFD {
                Circle()
                    .fill(Color(red:0.2,green:0.7,blue:1.0))
                    .frame(width: 4, height: 4)
            }
            Text(name)
                .font(.system(size: 9, weight: isActive ? .semibold : .regular, design: .monospaced))
                .foregroundColor(isActive ? themeVM.accent : .white.opacity(0.35))
            if labVM.sceneTabs_data.count > 1 {
                Button { labVM.removeSceneTab(index) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 6))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(isActive ? themeVM.accent.opacity(0.1) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(isActive ? themeVM.accent.opacity(0.35) : Color.clear, lineWidth: 0.7))
        .onTapGesture { labVM.switchTab(index) }
    }
}

// MARK: — Sigma HUD Strip
struct DARTSigmaStrip: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    // Shows active scene name so user always knows which tab they're on

    var sigmaVal: Double {
        labVM.physics.tabs[labVM.physics.activeTabIndex].sigmaReadout
    }
    var qsVal: Double {
        ArcEdgeMath.quantumSocket(b: 1.2, p: 0.8, a: 3.0, r: 1.5)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left — active scene name + element count
            HStack(spacing: 12) {
                // Active scene indicator
                HStack(spacing: 4) {
                    Circle().fill(themeVM.accent).frame(width:5, height:5)
                    Text(labVM.activeTabIndex < labVM.sceneTabs_data.count
                         ? labVM.sceneTabs_data[labVM.activeTabIndex].uppercased()
                         : "SCENE 1")
                        .font(.system(size:7, weight:.semibold, design:.monospaced))
                        .foregroundColor(themeVM.accent.opacity(0.8))
                        .tracking(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(themeVM.accent.opacity(0.08))
                .clipShape(Capsule())

                sigmaItem("ATOMS", value: "\(labVM.selectedElements.count)", color: .white.opacity(0.7))
                if let el = labVM.selectedElements.first {
                    sigmaItem("C=√(d×3)²",
                              value: String(format: "%.3f", el.arcEdgeCircumference),
                              color: themeVM.accent)
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Center divider
            Rectangle()
                .fill(themeVM.accent.opacity(0.15))
                .frame(width: 0.5, height: 16)

            Spacer()

            // Right — sigma + QS
            HStack(spacing: 12) {
                sigmaItem("Σ", value: String(format: "%.4f", sigmaVal), color: themeVM.accent)
                sigmaItem("QS", value: String(format: "%.4f", qsVal), color: .purple)
            }
            .padding(.trailing, 14)
        }
        .frame(height: 28)
        .background(Color.black.opacity(0.5))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(themeVM.accent.opacity(0.12)), alignment: .top)
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(themeVM.accent.opacity(0.12)), alignment: .bottom)
    }

    private func sigmaItem(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

// MARK: — Bottom Panel
struct DARTBottomPanel: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            DARTTabSelector()
            // Tab content
            ZStack {
                switch labVM.activeTab {
                case .molecule: DARTMoleculePanel()
                case .physics:  DARTPhysicsPanel()
                case .math:     DARTMathPanel()
                case .arc:      DARTArcPanel()
                case .env:      DARTEnvPanel()
                case .log:      DARTLogPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red:0.012,green:0.018,blue:0.035).opacity(0.95))
    }
}

// MARK: — Tab Selector
struct DARTTabSelector: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    private let tabs: [(ArcTab, String, String)] = [
        (.molecule, "Atoms",   "atom"),
        (.physics,  "Physics", "waveform.path"),
        (.math,     "Math",    "function"),
        (.arc,      "Arc",     "circle.and.line.horizontal"),
        (.env,      "Env",     "cloud.fill"),
        (.log,      "Log",     "list.bullet"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, label, icon in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { labVM.activeTab = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundColor(labVM.activeTab == tab
                                             ? themeVM.accent : .white.opacity(0.3))
                        Text(label)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(labVM.activeTab == tab
                                             ? themeVM.accent : .white.opacity(0.25))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(labVM.activeTab == tab
                                ? themeVM.accent.opacity(0.08) : Color.clear)
                    .overlay(
                        Rectangle().frame(height: 1.5)
                            .foregroundColor(labVM.activeTab == tab
                                             ? themeVM.accent : Color.clear),
                        alignment: .top
                    )
                }
            }
        }
        .background(Color.black.opacity(0.5))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(Color.white.opacity(0.08)), alignment: .bottom)
    }
}

// MARK: — CFD Badge
struct DARTCFDBadge: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        Button { labVM.stopCFD() } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("EXIT CFD")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(red:0.1,green:0.4,blue:0.8).opacity(0.85))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(red:0.2,green:0.6,blue:1.0).opacity(0.4), lineWidth: 0.7))
        }
    }
}

// MARK: — Icon Button
struct DARTIconButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(active ? themeVM.accent : .white.opacity(0.4))
                .frame(width: 30, height: 30)
                .background(active ? themeVM.accent.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: — Shared panel card
struct DARTPanelCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(themeVM.accent)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.8))
                    .tracking(1.5)
                Spacer()
            }
            .padding(.bottom, 2)
            content
        }
        .padding(12)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(themeVM.accent.opacity(0.1), lineWidth: 0.7))
    }
}

// MARK: — enum for tab selection
enum DARTTab { case scene, panel }


// MARK: — Arc Profile Sheet (DART)
struct ArcProfileSheet: View {
    @EnvironmentObject var authVM: ArcAuthViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showApplePicker  = false
    @State private var showGitHubPicker = false
    @State private var showSupport = false

    var body: some View {
        ZStack {
            Color(red:0.024,green:0.039,blue:0.063).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4).padding(.top, 20).padding(.bottom, 24)
                ZStack {
                    Circle().fill(themeVM.accent.opacity(0.12)).frame(width: 72, height: 72)
                    Circle().stroke(themeVM.accent.opacity(0.4), lineWidth: 1.5).frame(width: 72, height: 72)
                    if let avatarURL = authVM.githubAvatarURL {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                                    .frame(width: 68, height: 68)
                                    .clipShape(Circle())
                            case .failure, .empty:
                                Text(authVM.username.prefix(1).uppercased())
                                    .font(.custom("Orbitron-Bold", size: 28))
                                    .foregroundColor(themeVM.accent)
                            @unknown default:
                                Text(authVM.username.prefix(1).uppercased())
                                    .font(.custom("Orbitron-Bold", size: 28))
                                    .foregroundColor(themeVM.accent)
                            }
                        }
                    } else {
                        Text(authVM.username.prefix(1).uppercased())
                            .font(.custom("Orbitron-Bold", size: 28)).foregroundColor(themeVM.accent)
                    }
                }
                Spacer().frame(height: 12)
                Text(authVM.username)
                    .font(.custom("Orbitron-Bold", size: 16)).foregroundColor(.white)
                Text("DART · Autumn-Ash Vault")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35)).padding(.top, 3)

                // ── Music controls ──────────────────────────────
                ArcMusicControls()
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                Spacer().frame(height: 12)
                VStack(spacing: 0) {
                    arcRow("Apple ID",
                           authVM.savedAppleAccounts.isEmpty ? "—"
                               : authVM.savedAppleAccounts.map{$0.displayName}.joined(separator:", "),
                           authVM.savedAppleAccounts.isEmpty ? .white.opacity(0.3) : .green) {
                        showApplePicker = true
                    }
                    Divider().background(Color.white.opacity(0.08))
                    arcRow("GitHub", authVM.githubConnected ? authVM.githubUsername : "Not connected",
                           authVM.githubConnected ? themeVM.accent : .white.opacity(0.3)) { showGitHubPicker = true }
                    Divider().background(Color.white.opacity(0.08))
                    arcRow("Google",
                           authVM.googleConnected ? authVM.googleEmail : "Not connected",
                           authVM.googleConnected ? Color(red:0.26,green:0.52,blue:0.96) : .white.opacity(0.3)) {
                        if authVM.googleConnected { authVM.signOutGoogle() }
                        else { authVM.signInWithGoogle() }
                    }
                    Divider().background(Color.white.opacity(0.08))
                    HStack {
                        Text("Vault").font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("Autumn-Ash/ArcLake ✓").font(.system(size: 13, design: .monospaced)).foregroundColor(themeVM.accent)
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().background(Color.white.opacity(0.08))
                    HStack {
                        Text("Build").font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("1.0.7 (26)").font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }
                .background(Color.white.opacity(0.04)).cornerRadius(12).padding(.horizontal, 20)
                Spacer()
                Button { showSupport = true } label: {
                    HStack(spacing:10) {
                        Image(systemName:"heart.fill").font(.system(size:14)).foregroundColor(.pink)
                        VStack(alignment:.leading, spacing:1) {
                            Text("Support ArcLake").font(.custom("Exo2-SemiBold", size:13)).foregroundColor(.white)
                            Text("$4.99/month · Help keep development active")
                                .font(.system(size:9, design:.monospaced)).foregroundColor(.white.opacity(0.35))
                        }
                        Spacer()
                        Image(systemName:"chevron.right").font(.system(size:10)).foregroundColor(.white.opacity(0.25))
                    }
                    .padding(.horizontal,16).padding(.vertical,12)
                    .background(Color.pink.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:10))
                    .overlay(RoundedRectangle(cornerRadius:10).stroke(Color.pink.opacity(0.2), lineWidth:0.7))
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 12)   // breathing room between Support and Sign Out

                Button { authVM.signOut(); dismiss() } label: {
                    Text("Sign Out").font(.custom("Exo2-SemiBold", size: 15)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.red.opacity(0.1)).cornerRadius(10)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
        .presentationDetents([.fraction(0.58), .large])
        .sheet(isPresented: $showSupport) {
            ArcSupportSheet(accentColor: themeVM.accent, appName: "ArcLake")
        }
        .confirmationDialog("Switch Apple Account", isPresented: $showApplePicker) {
            ForEach(authVM.savedAppleAccounts) { a in Button(a.displayName) { authVM.switchAppleAccount(to: a) } }
            Button("Add New Apple ID") { authVM.signInWithApple() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Switch GitHub Account", isPresented: $showGitHubPicker) {
            ForEach(authVM.savedGitHubAccounts) { a in Button(a.displayName) { authVM.switchGitHubAccount(to: a); dismiss() } }
            Button("Connect New GitHub Account") { Task { await authVM.startGitHubAuth() }; dismiss() }
            if authVM.githubConnected { Button("Disconnect GitHub", role: .destructive) { authVM.disconnectGitHub() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func arcRow(_ label: String, _ value: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Spacer()
                HStack(spacing: 5) {
                    Text(value).font(.system(size: 13, design: .monospaced)).foregroundColor(color)
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundColor(.white.opacity(0.2))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}


// MARK: — ArcMusicControls
// Inline music player: prev | play/pause | stop | next | load library
struct ArcMusicControls: View {
    @StateObject private var audio = ArcAudioPlayerViewModel.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 8) {
            // Track name
            Text(audio.currentTitle)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(themeVM.accent.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 14) {
                // Previous
                musicBtn("backward.end.fill") { audio.prevTrack() }
                // Skip back  (added per markup)
                musicBtn("backward.frame.fill") { audio.prevTrack() }
                // Play / Pause
                musicBtn(audio.isPlaying ? "pause.fill" : "play.fill", accent: true) {
                    audio.playPause()
                }
                // Stop
                musicBtn("stop.fill") { audio.stop() }
                // Next
                musicBtn("forward.end.fill") { audio.nextTrack() }
                // Load music library
                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 14))
                        .foregroundColor(themeVM.accent.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(themeVM.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Library list (if more than one track)
            if audio.library.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(audio.library.enumerated()), id: \.offset) { idx, track in
                            Button {
                                audio.currentIndex = idx
                                audio.stop()
                                audio.playPause()
                            } label: {
                                Text(track.title)
                                    .font(.system(size: 8, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .foregroundColor(idx == audio.currentIndex ? .black : themeVM.accent.opacity(0.7))
                                    .background(idx == audio.currentIndex ? themeVM.accent : themeVM.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(themeVM.accent.opacity(0.12), lineWidth: 0.7))
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "mp3") ?? .audio,
                UTType(filenameExtension: "wav") ?? .audio,
                UTType(filenameExtension: "m4a") ?? .audio,
                UTType(filenameExtension: "aac") ?? .audio,
            ],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let secured = urls.filter { $0.startAccessingSecurityScopedResource() }
                audio.addTracks(from: secured)
            case .failure(let e):
                print("[ArcAudio] file picker error: \(e)")
            }
        }
    }

    @ViewBuilder
    private func musicBtn(_ icon: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: accent ? 16 : 13))
                .foregroundColor(accent ? .black : themeVM.accent.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(accent ? themeVM.accent : themeVM.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}




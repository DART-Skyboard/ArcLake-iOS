import SwiftUI
import SceneKit

// MARK: — DART Root View
// Premium redesign of Arc Lake DART
// Aesthetic: Deep space / bioluminescent / precision instrument

public struct DARTRootView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var authVM: ArcAuthViewModel
    @State private var showProfile = false
    @State private var selectedTab: DARTTab = .scene

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Deep space background
                DARTBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Top chrome ─────────────────────────────────
                    DARTTopBar(showProfile: $showProfile)

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
                                        .padding(.trailing, 12)
                                        .padding(.bottom, 8)
                                }
                            }
                        }
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
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProfile) { ArcProfileSheet() }
        .overlay(alignment: .bottomTrailing) {
            AutumnOverlay()
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

            // Right controls
            HStack(spacing: 4) {
                // Grid toggle
                DARTIconButton(icon: "number", active: labVM.showGrid) {
                    labVM.showGrid.toggle(); labVM.rebuildGrid()
                }
                DARTIconButton(icon: "tablecells",
                               active: labVM.isPeriodicTableVisible) {
                    withAnimation(.spring()) { labVM.isPeriodicTableVisible.toggle() }
                }
                // Node editor
                DARTIconButton(icon: "circle.connected.to.line.below",
                               active: labVM.isNodeEditorVisible) {
                    withAnimation(.spring()) { labVM.isNodeEditorVisible.toggle() }
                }
                // Theme
                DARTIconButton(icon: "paintpalette", active: themeVM.current != .stealth) {
                    withAnimation(.easeInOut(duration: 0.25)) { themeVM.cycle() }
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
                        Text(authVM.username.prefix(1).uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }
                }
            }
            .padding(.trailing, 12)
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
                    .frame(width: 40, height: 4).padding(.top, 12).padding(.bottom, 20)
                ZStack {
                    Circle().fill(themeVM.accent.opacity(0.12)).frame(width: 72, height: 72)
                    Circle().stroke(themeVM.accent.opacity(0.4), lineWidth: 1.5).frame(width: 72, height: 72)
                    Text(authVM.username.prefix(1).uppercased())
                        .font(.custom("Orbitron-Bold", size: 28)).foregroundColor(themeVM.accent)
                }
                Spacer().frame(height: 12)
                Text(authVM.username)
                    .font(.custom("Orbitron-Bold", size: 16)).foregroundColor(.white)
                Text("DART · Autumn-Ash Vault")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35)).padding(.top, 3)
                Spacer().frame(height: 24)
                VStack(spacing: 0) {
                    arcRow("Apple ID", authVM.appleUserId.isEmpty ? "—" : "Connected ✓",
                           authVM.appleUserId.isEmpty ? .white.opacity(0.3) : .green) { showApplePicker = true }
                    Divider().background(Color.white.opacity(0.08))
                    arcRow("GitHub", authVM.githubConnected ? authVM.githubUsername : "Not connected",
                           authVM.githubConnected ? themeVM.accent : .white.opacity(0.3)) { showGitHubPicker = true }
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

                Button { authVM.signOut(); dismiss() } label: {
                    Text("Sign Out").font(.custom("Exo2-SemiBold", size: 15)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.red.opacity(0.1)).cornerRadius(10)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium, .large])
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

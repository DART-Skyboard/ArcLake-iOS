
import SwiftUI
import SceneKit

public struct ArcRootView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var authVM: ArcAuthViewModel
    @State private var showProfile = false

    public var body: some View {
        GeometryReader { geo in
            let vm = labVM
        ZStack {
                themeVM.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Scene tab bar ────────────────────────────────
                    SceneTabBar()

                    // ── 3D Viewport ──────────────────────────────────
                    ArcSceneView()
                        .frame(height: geo.size.height * 0.46)

                    // ── Sidebar ──────────────────────────────────────
                    ArcSidebarView(sidebarCollapsed: .constant(false))
                        .background(Color.black.opacity(0.7))
                }

                // ── Overlays (tap outside to dismiss) ─────────────────
                let showDim = labVM.isPeriodicTableVisible || labVM.isMolCanvasVisible || labVM.isOrbitDeltaVisible || labVM.isNodeEditorVisible
            if showDim {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                labVM.isPeriodicTableVisible = false
                                labVM.isMolCanvasVisible     = false
                                labVM.isOrbitDeltaVisible    = false
                                labVM.isNodeEditorVisible    = false
                            }
                        }
                }

                ArcOverlays(geoSize: geo.size)

                // ── HUD bar ─────────────────────────────────────────
                VStack {
                    ArcHUDBar()
                    Spacer()
                    // CFD exit badge
                    if labVM.isCFDActive {
                        Button {
                            labVM.stopCFD()
                        } label: {
                            Label("Exit CFD", systemImage: "xmark.circle.fill")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.blue.opacity(0.7))
                                .clipShape(Capsule())
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .animation(.spring(response: 0.3), value: labVM.isPeriodicTableVisible)
            .animation(.spring(response: 0.3), value: labVM.isMolCanvasVisible)
            .animation(.spring(response: 0.3), value: labVM.isOrbitDeltaVisible)
            
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProfile) { ArcProfileSheet() }
    }
}

// MARK: — Scene Tab Bar
struct SceneTabBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(labVM.sceneTabs_data.indices, id: \.self) { i in
                    SceneTabPill(index: i)
                }
                Button { labVM.addSceneTab() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundColor(themeVM.accent)
                        .frame(width: 24, height: 24)
                        .background(themeVM.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .background(Color.black.opacity(0.5))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(themeVM.accent.opacity(0.2)), alignment: .bottom)
    }
}

private struct SceneTabPill: View {
    let index: Int
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var isActive: Bool { labVM.activeTabIndex == index }
    var name: String { index < labVM.sceneTabs_data.count ? labVM.sceneTabs_data[index] : "" }
    var isCFD: Bool { index < labVM.sceneTabsCFD.count ? labVM.sceneTabsCFD[index] : false }

    var body: some View {
        HStack(spacing: 4) {
            if isCFD { Circle().fill(Color.blue).frame(width: 5, height: 5) }
            Text(name)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isActive ? themeVM.accent : .white.opacity(0.4))
            if labVM.sceneTabs_data.count > 1 {
                Button { labVM.removeSceneTab(index) } label: {
                    Image(systemName: "xmark").font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isActive ? themeVM.accent.opacity(0.12) : Color.white.opacity(0.04))
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5)
            .stroke(isActive ? themeVM.accent.opacity(0.4) : Color.clear, lineWidth: 0.5))
        .onTapGesture { labVM.switchTab(index) }
    }
}

// MARK: — HUD Bar
struct ArcHUDBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var _gridOn = true

    var body: some View {
        HStack(spacing: 10) {
            Text("Arc Lake")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(themeVM.accent)
            Text("v1.45")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            if labVM.isCFDActive {
                Label("CFD ACTIVE", systemImage: "wind")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15)).clipShape(Capsule())
            }
            Spacer()
            // Grid toggle
            Button {
                let vm = labVM
                vm.showGrid.toggle()
                vm.rebuildGrid()
            } label: {
                Image(systemName: labVM.showGrid ? "grid" : "grid.slash")
                    .font(.caption)
                    .foregroundColor(labVM.showGrid ? themeVM.accent : .white.opacity(0.3))
            }
            // Node editor
            Button {
                withAnimation { labVM.isNodeEditorVisible = !labVM.isNodeEditorVisible }
            } label: {
                Image(systemName: "circle.connected.to.line.below")
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.7))
            }
            // Profile avatar
            Button { /* signal up to ArcRootView via environment — handled via ArcProfileSheet */ } label: {
                ZStack {
                    Circle().fill(themeVM.accent.opacity(0.15)).frame(width: 28, height: 28)
                    Circle().stroke(themeVM.accent.opacity(0.35), lineWidth: 1).frame(width: 28, height: 28)
                }
            }
            // Theme
            Button { withAnimation { themeVM.cycle() } } label: {
                Image(systemName: "paintpalette.fill").foregroundColor(themeVM.accent)
            }
            // Periodic table
            Button {
                withAnimation(.spring()) { labVM.isPeriodicTableVisible.toggle() }
            } label: {
                Image(systemName: "tablecells")
                    .foregroundColor(labVM.isPeriodicTableVisible ? themeVM.accent : .white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}


// MARK: — Arc Profile Sheet
struct ArcProfileSheet: View {
    @EnvironmentObject var authVM: ArcAuthViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showApplePicker  = false
    @State private var showGitHubPicker = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#060a10"), Color(hex: "#0a0e14")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
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
                Text("Arc Lake · Autumn-Ash Vault")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35)).padding(.top, 3)
                Spacer().frame(height: 24)

                VStack(spacing: 0) {
                    let appleValue  = authVM.appleUserId.isEmpty ? "Not signed in" : authVM.username
                    let appleStatus = authVM.appleUserId.isEmpty ? "—" : "Connected ✓"
                    let appleColor: Color = authVM.appleUserId.isEmpty ? .white.opacity(0.3) : .green
                    arcProfileRow("Apple ID", value: appleValue, status: appleStatus, color: appleColor) { showApplePicker = true }
                    Divider().background(Color.white.opacity(0.08))
                    let ghValue  = authVM.githubConnected ? authVM.githubUsername : "Not connected"
                    let ghStatus = authVM.githubConnected ? "Connected ✓" : "Tap to connect"
                    let ghColor: Color = authVM.githubConnected ? themeVM.accent : .white.opacity(0.3)
                    arcProfileRow("GitHub", value: ghValue, status: ghStatus, color: ghColor) { showGitHubPicker = true }
                    Divider().background(Color.white.opacity(0.08))
                    HStack {
                        Text("Vault").font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("Autumn-Ash/ArcLake ✓")
                            .font(.system(size: 13, design: .monospaced)).foregroundColor(themeVM.accent)
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                    Divider().background(Color.white.opacity(0.08))
                    HStack {
                        Text("Build").font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("1.4.5 (25)").font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }
                .background(Color.white.opacity(0.04)).cornerRadius(12).padding(.horizontal, 20)

                Spacer()
                Button { authVM.signOut(); dismiss() } label: {
                    Text("Sign Out").font(.custom("Exo2-SemiBold", size: 15)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color.red.opacity(0.1)).cornerRadius(10)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog("Switch Apple Account", isPresented: $showApplePicker) {
            ForEach(authVM.savedAppleAccounts) { a in
                Button(a.displayName) { authVM.switchAppleAccount(to: a) }
            }
            Button("Add New Apple ID") { authVM.signInWithApple() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Switch GitHub Account", isPresented: $showGitHubPicker) {
            ForEach(authVM.savedGitHubAccounts) { a in
                Button(a.displayName) { authVM.switchGitHubAccount(to: a); dismiss() }
            }
            Button("Connect New GitHub Account") {
                Task { await authVM.startGitHubAuth() }; dismiss()
            }
            if authVM.githubConnected {
                Button("Disconnect GitHub", role: .destructive) { authVM.disconnectGitHub() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func arcProfileRow(_ label: String, value: String, status: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                    Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                }
                Spacer()
                HStack(spacing: 5) {
                    Text(status).font(.system(size: 13, design: .monospaced)).foregroundColor(color)
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundColor(.white.opacity(0.2))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

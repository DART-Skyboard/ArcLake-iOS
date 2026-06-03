
import SwiftUI
import SceneKit

public struct ArcRootView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public var body: some View {
        GeometryReader { geo in
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
                if labVM.isPeriodicTableVisible || labVM.isMolCanvasVisible
                    || labVM.isOrbitDeltaVisible || labVM.isNodeEditorVisible {
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

                if labVM.isPeriodicTableVisible {
                    PeriodicTableView()
                        .frame(width: min(geo.size.width-16, 700),
                               height: min(geo.size.height*0.62, 550))
                        .transition(.move(edge:.bottom).combined(with:.opacity))
                }

                if labVM.isMolCanvasVisible {
                    MolCanvasView()
                        .frame(width: geo.size.width - 16,
                               height: min(geo.size.height * 0.62, 500))
                        .transition(.opacity)
                }

                if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
                    OrbitDeltaNodeView(element: el)
                        .position(x: geo.size.width * 0.5,
                                  y: geo.size.height * 0.45)
                        .transition(.scale.combined(with:.opacity))
                }

                if labVM.isNodeEditorVisible {
                    NodeEditorView()
                        .frame(width: min(geo.size.width - 16, 700),
                               height: min(geo.size.height * 0.8, 600))
                        .transition(.opacity)
                }

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
            .animation(.spring(response: 0.3), value: labVM.isNodeEditorVisible)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: — Scene Tab Bar
struct SceneTabBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(labVM.sceneTabs.indices, id: \.self) { i in
                    Button {
                        labVM.switchTab(i)
                    } label: {
                        HStack(spacing: 4) {
                            if labVM.sceneTabs[i].isCFDMode {
                                Circle().fill(Color.blue).frame(width: 5, height: 5)
                            }
                            Text(labVM.sceneTabs[i].name)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(labVM.activeTabIndex == i ?
                                    themeVM.accent : .white.opacity(0.4))
                            if labVM.sceneTabs.count > 1 {
                                Button {
                                    if labVM.sceneTabs.count > 1 {
                                        labVM.sceneTabs.remove(at: i)
                                        if labVM.activeTabIndex >= labVM.sceneTabs.count {
                                            labVM.activeTabIndex = labVM.sceneTabs.count - 1
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(labVM.activeTabIndex == i ?
                            themeVM.accent.opacity(0.12) : Color.white.opacity(0.04))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(labVM.activeTabIndex == i ?
                                themeVM.accent.opacity(0.4) : Color.clear, lineWidth: 0.5))
                    }
                }
                // Add tab
                Button {
                    labVM.addSceneTab()
                } label: {
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
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(themeVM.accent.opacity(0.2)), alignment: .bottom)
    }
}

// MARK: — HUD Bar
struct ArcHUDBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

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
                    .padding(.horizontal, 5).padding(.vertical: 2)
                    .background(Color.blue.opacity(0.15)).clipShape(Capsule())
            }
            Spacer()
            // Grid toggle
            Button {
                labVM.showGrid.toggle()
                labVM.rebuildGrid()
            } label: {
                Image(systemName: labVM.showGrid ? "grid" : "grid.slash")
                    .font(.caption)
                    .foregroundColor(labVM.showGrid ? themeVM.accent : .white.opacity(0.3))
            }
            // Node editor
            Button {
                withAnimation { labVM.isNodeEditorVisible.toggle() }
            } label: {
                Image(systemName: "circle.connected.to.line.below")
                    .font(.caption)
                    .foregroundColor(labVM.isNodeEditorVisible ? .purple : .white.opacity(0.4))
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


import SwiftUI
import SceneKit

public struct ArcRootView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var sidebarCollapsed = false

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                themeVM.bg.ignoresSafeArea()

                if geo.size.width > 600 {
                    // iPad / landscape
                    HStack(spacing: 0) {
                        ArcSceneView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if !sidebarCollapsed {
                            ArcSidebarView(sidebarCollapsed: $sidebarCollapsed)
                                .frame(width: 320)
                                .background(Color.black.opacity(0.6))
                        } else {
                            Button {
                                withAnimation(.spring()) { sidebarCollapsed = false }
                            } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(themeVM.accent)
                                    .padding(8)
                            }
                        }
                    }
                } else {
                    // iPhone — 3D on top, sidebar below
                    VStack(spacing: 0) {
                        ArcSceneView()
                            .frame(height: geo.size.height * 0.48)
                        ArcSidebarView(sidebarCollapsed: $sidebarCollapsed)
                            .background(Color.black.opacity(0.7))
                    }
                }

                // ── Overlay panels — tap outside to dismiss ──
                if labVM.isPeriodicTableVisible || labVM.isMolCanvasVisible || labVM.isOrbitDeltaVisible {
                    // Dimmed background — tap to dismiss all
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                labVM.isPeriodicTableVisible = false
                                labVM.isMolCanvasVisible     = false
                                labVM.isOrbitDeltaVisible    = false
                            }
                        }
                }

                // Periodic table — constrained overlay
                if labVM.isPeriodicTableVisible {
                    PeriodicTableView()
                        .frame(
                            width:  min(geo.size.width - 16, 700),
                            height: min(geo.size.height * 0.62, 550)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Mol canvas
                if labVM.isMolCanvasVisible {
                    MolCanvasView()
                        .frame(
                            width:  min(geo.size.width - 16, 500),
                            height: min(geo.size.height * 0.58, 480)
                        )
                        .transition(.opacity)
                }

                // Orbit delta probe
                if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
                    OrbitDeltaNodeView(element: el)
                        .transition(.scale.combined(with: .opacity))
                }

                // HUD bar — always on top
                VStack {
                    ArcHUDBar()
                    Spacer()
                }
            }
            .animation(.spring(response: 0.3), value: labVM.isPeriodicTableVisible)
            .animation(.spring(response: 0.3), value: labVM.isMolCanvasVisible)
            .animation(.spring(response: 0.3), value: labVM.isOrbitDeltaVisible)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: — HUD bar
struct ArcHUDBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Arc Lake")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(themeVM.accent)
            Spacer()
            Text("v1.45")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            if labVM.isCFDActive {
                Label("CFD", systemImage: "wind")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15)).clipShape(Capsule())
            }
            Button { withAnimation { themeVM.cycle() } } label: {
                Image(systemName: "paintpalette.fill").foregroundColor(themeVM.accent)
            }
            Button {
                withAnimation(.spring()) { labVM.isPeriodicTableVisible.toggle() }
            } label: {
                Image(systemName: "tablecells")
                    .foregroundColor(labVM.isPeriodicTableVisible ? themeVM.accent : .white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

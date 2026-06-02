
import SwiftUI
import SceneKit

public struct ArcRootView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showPeriodicTable = false
    @State private var sidebarCollapsed = false

    public var body: some View {
        ZStack {
            themeVM.bg.ignoresSafeArea()

            GeometryReader { geo in
                if geo.size.width > 600 {
                    // iPad / landscape: side-by-side
                    HStack(spacing: 0) {
                        // 3D Viewport
                        ArcSceneView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !sidebarCollapsed {
                            // Sidebar
                            ArcSidebarView(sidebarCollapsed: $sidebarCollapsed)
                                .frame(width: 320)
                                .background(Color.black.opacity(0.6))
                        } else {
                            sidebarToggleButton
                        }
                    }
                } else {
                    // iPhone: stacked
                    VStack(spacing: 0) {
                        // 3D Viewport — top 55%
                        ArcSceneView()
                            .frame(height: geo.size.height * 0.55)

                        // Sidebar — bottom 45%
                        ArcSidebarView(sidebarCollapsed: $sidebarCollapsed)
                            .background(Color.black.opacity(0.7))
                    }
                }
            }

            // Floating overlays
            if labVM.isPeriodicTableVisible {
                PeriodicTableView()
                    .transition(.move(edge: .bottom))
            }

            if labVM.isMolCanvasVisible {
                MolCanvasView()
                    .transition(.opacity)
            }

            if labVM.isOrbitDeltaVisible, let target = labVM.probeTarget {
                OrbitDeltaNodeView(element: target)
                    .transition(.scale)
            }

            // Top HUD bar
            VStack {
                ArcHUDBar()
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.spring()) { sidebarCollapsed = false }
        } label: {
            Image(systemName: "chevron.left.circle.fill")
                .font(.title)
                .foregroundColor(themeVM.accent)
                .padding(8)
        }
    }
}

// MARK: — HUD bar
struct ArcHUDBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        HStack(spacing: 12) {
            // App title
            Text("ArcLake")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundColor(themeVM.accent)

            Spacer()

            // Version
            Text("v1.45")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            // CFD indicator
            if labVM.isCFDActive {
                Label("CFD", systemImage: "wind")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Theme button
            Button {
                withAnimation { themeVM.cycle() }
            } label: {
                Image(systemName: "paintpalette.fill")
                    .foregroundColor(themeVM.accent)
            }

            // Periodic Table toggle
            Button {
                withAnimation(.spring()) {
                    labVM.isPeriodicTableVisible.toggle()
                }
            } label: {
                Image(systemName: "tablecells")
                    .foregroundColor(labVM.isPeriodicTableVisible ? themeVM.accent : .white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

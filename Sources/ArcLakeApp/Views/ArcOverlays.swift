import SwiftUI

/// Overlay panels — draggable via top grab bar, no whole-panel gesture conflict
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    // Each panel remembers its drag position independently
    @State private var ptPos    = CGPoint(x: 0, y: 0)   // periodic table
    @State private var mcPos    = CGPoint(x: 0, y: 0)   // mol canvas
    @State private var nodePos  = CGPoint(x: 0, y: 0)   // node editor
    @State private var probePos = CGPoint(x: 0, y: 0)   // probe/orbit delta

    var body: some View {
        ZStack {
            if labVM.isPeriodicTableVisible {
                FloatingPanel(
                    pos: $ptPos, geoSize: geoSize,
                    width: min(geoSize.width - 16, 700),
                    height: min(geoSize.height * 0.62, 550)
                ) {
                    PeriodicTableView()
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if labVM.isMolCanvasVisible {
                FloatingPanel(
                    pos: $mcPos, geoSize: geoSize,
                    width: geoSize.width - 16,
                    height: min(geoSize.height * 0.7, 560)
                ) {
                    MolCanvasView()
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if labVM.isNodeEditorVisible {
                FloatingPanel(
                    pos: $nodePos, geoSize: geoSize,
                    width: min(geoSize.width - 16, 700),
                    height: min(geoSize.height * 0.8, 600)
                ) {
                    NodeEditorView()
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
                FloatingPanel(
                    pos: $probePos, geoSize: geoSize,
                    width: min(geoSize.width - 16, 420),
                    height: 380
                ) {
                    OrbitDeltaNodeView(element: el)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                // Reset position when new probe opens so it appears centered
                .onAppear {
                    probePos = CGPoint(
                        x: geoSize.width * 0.5,
                        y: geoSize.height * 0.40)
                }
            }
        }
    }
}

// MARK: — FloatingPanel
/// A panel that positions itself at `pos` and can be dragged by its grab bar.
/// Uses position() not offset() to avoid the shaking/redraw issue that offset causes
/// when a @State changes rapidly during drag.
struct FloatingPanel<Content: View>: View {
    @Binding var pos: CGPoint
    let geoSize: CGSize
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    // Drag state — track start position of each drag gesture
    @State private var dragStart = CGPoint.zero

    var body: some View {
        VStack(spacing: 0) {
            // ── Grab bar ─────────────────────────────────────────
            HStack {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(Color.white.opacity(0.03))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { val in
                        // Move panel: add delta from drag start
                        pos = CGPoint(
                            x: dragStart.x + val.translation.width,
                            y: dragStart.y + val.translation.height)
                    }
                    .onEnded { _ in
                        // Clamp to screen bounds so panel can't be lost off-screen
                        let hw = width / 2; let hh = height / 2
                        pos = CGPoint(
                            x: min(max(pos.x, hw + 8), geoSize.width  - hw - 8),
                            y: min(max(pos.y, hh + 8), geoSize.height - hh - 8))
                        dragStart = pos
                    }
            )

            // ── Content ──────────────────────────────────────────
            content()
        }
        .frame(width: width, height: height)
        .background(Color(red:0.06, green:0.09, blue:0.15).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color.white.opacity(0.08), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.5), radius: 20)
        .position(pos)  // position() not offset() — no shaking
        .onAppear {
            // Default: center the panel on first appear
            if pos == .zero {
                pos = CGPoint(x: geoSize.width / 2, y: geoSize.height / 2)
                dragStart = pos
            }
        }
    }
}

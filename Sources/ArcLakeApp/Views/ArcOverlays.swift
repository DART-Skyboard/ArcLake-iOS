import SwiftUI

// MARK: — ArcOverlays
// Each panel wraps only in a thin transparent drag shell — NO extra header.
// The content views (PeriodicTableView, MolCanvasView etc) already have
// their own chrome with close buttons and titles. We just make them draggable.
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        ZStack {
            if labVM.isPeriodicTableVisible {
                DragShell(
                    geoSize: geoSize,
                    width:   geoSize.width - 20,
                    height:  min(geoSize.height * 0.65, 580)
                ) {
                    PeriodicTableView()
                }
                .id("pt")
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if labVM.isMolCanvasVisible {
                DragShell(
                    geoSize: geoSize,
                    width:   geoSize.width - 20,
                    height:  min(geoSize.height * 0.72, 600)
                ) {
                    MolCanvasView()
                }
                .id("mc")
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if labVM.isNodeEditorVisible {
                DragShell(
                    geoSize: geoSize,
                    width:   geoSize.width - 20,
                    height:  min(geoSize.height * 0.80, 640)
                ) {
                    NodeEditorView()
                }
                .id("ne")
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
                DragShell(
                    geoSize: geoSize,
                    width:   min(geoSize.width - 20, 420),
                    height:  380
                ) {
                    OrbitDeltaNodeView(element: el)
                }
                .id("probe-\(el.id)")
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onAppear {
                    // Probe appears centered when a new element is tapped
                }
            }
        }
    }
}

// MARK: — DragShell
// A transparent wrapper that makes any content view draggable.
// No extra chrome — content view supplies its own header/close button.
// Drag gesture is registered on the WHOLE panel so any part can drag it.
// The content view's own buttons still work because SwiftUI gesture priority
// gives button taps higher priority than the DragGesture (minimumDistance > 0).
struct DragShell<Content: View>: View {
    let geoSize: CGSize
    let width:   CGFloat
    let height:  CGFloat
    @ViewBuilder let content: () -> Content

    @State private var offset   = CGSize.zero
    @State private var baseOff  = CGSize.zero

    var body: some View {
        content()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.55), radius: 22, y: 6)
            .offset(offset)
            // Drag from anywhere — buttons still work because tap wins over drag
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { val in
                        offset = CGSize(
                            width:  baseOff.width  + val.translation.width,
                            height: baseOff.height + val.translation.height)
                    }
                    .onEnded { _ in
                        // Clamp so panel stays on screen
                        let hw = width / 2;  let hh = height / 2
                        let maxX = geoSize.width  / 2 - hw + 8
                        let maxY = geoSize.height / 2 - hh + 8
                        offset = CGSize(
                            width:  min(max(offset.width,  -maxX), maxX),
                            height: min(max(offset.height, -maxY), maxY))
                        baseOff = offset
                    }
            )
    }
}

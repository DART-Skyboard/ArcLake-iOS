import SwiftUI

/// Overlay panels — all are draggable (matches web app drag behavior)
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    // Drag offsets per panel — each panel remembers where user left it
    @State private var ptOffset   = CGSize.zero
    @State private var mcOffset   = CGSize.zero
    @State private var nodeOffset = CGSize.zero
    @State private var orbitOffset = CGSize.zero

    var body: some View {
        Group {
            periodicTableOverlay
            molCanvasOverlay
            nodeEditorOverlay
            orbitDeltaOverlay
        }
    }

    // MARK: — Periodic Table (draggable)
    @ViewBuilder private var periodicTableOverlay: some View {
        if labVM.isPeriodicTableVisible {
            DraggablePanel(offset: $ptOffset, geoSize: geoSize) {
                PeriodicTableView()
            }
            .frame(width: min(geoSize.width - 16, 700),
                   height: min(geoSize.height * 0.62, 550))
            .offset(ptOffset)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    // MARK: — Mol Canvas (draggable)
    @ViewBuilder private var molCanvasOverlay: some View {
        if labVM.isMolCanvasVisible {
            DraggablePanel(offset: $mcOffset, geoSize: geoSize) {
                MolCanvasView()
            }
            .frame(width: geoSize.width - 16,
                   height: min(geoSize.height * 0.7, 560))
            .offset(mcOffset)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    // MARK: — Node Editor (draggable)
    @ViewBuilder private var nodeEditorOverlay: some View {
        if labVM.isNodeEditorVisible {
            DraggablePanel(offset: $nodeOffset, geoSize: geoSize) {
                NodeEditorView()
            }
            .frame(width: min(geoSize.width - 16, 700),
                   height: min(geoSize.height * 0.8, 600))
            .offset(nodeOffset)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    // MARK: — Orbit Delta (draggable, positioned near atom)
    @ViewBuilder private var orbitDeltaOverlay: some View {
        if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
            DraggablePanel(offset: $orbitOffset, geoSize: geoSize) {
                OrbitDeltaNodeView(element: el)
            }
            .position(x: geoSize.width * 0.5 + orbitOffset.width,
                      y: geoSize.height * 0.42 + orbitOffset.height)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

// MARK: — DraggablePanel wrapper
/// Wraps any content view with a drag handle (grab anywhere in the panel)
/// The panel snaps to stay within screen bounds on gesture end.
struct DraggablePanel<Content: View>: View {
    @Binding var offset: CGSize
    let geoSize: CGSize
    @ViewBuilder let content: () -> Content
    @State private var dragStart = CGSize.zero

    var body: some View {
        content()
            .background(Color(red:0.06, green:0.09, blue:0.15).opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { val in
                        offset = CGSize(
                            width:  dragStart.width + val.translation.width,
                            height: dragStart.height + val.translation.height)
                    }
                    .onEnded { _ in
                        dragStart = offset
                    }
            )
    }
}

import SwiftUI

/// Overlay panels — all are draggable via their header/title area
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    @State private var ptOffset    = CGSize.zero
    @State private var mcOffset    = CGSize.zero
    @State private var nodeOffset  = CGSize.zero
    @State private var orbitOffset = CGSize.zero

    var body: some View {
        Group {
            periodicTableOverlay
            molCanvasOverlay
            nodeEditorOverlay
            orbitDeltaOverlay
        }
    }

    @ViewBuilder private var periodicTableOverlay: some View {
        if labVM.isPeriodicTableVisible {
            PeriodicTableView()
                .frame(width: min(geoSize.width - 16, 700),
                       height: min(geoSize.height * 0.62, 550))
                .offset(ptOffset)
                .overlay(DragHandle(offset: $ptOffset), alignment: .top)
                .background(Color(red:0.06,green:0.09,blue:0.15).opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.5), radius: 20)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder private var molCanvasOverlay: some View {
        if labVM.isMolCanvasVisible {
            MolCanvasView()
                .frame(width: geoSize.width - 16,
                       height: min(geoSize.height * 0.7, 560))
                .offset(mcOffset)
                .overlay(DragHandle(offset: $mcOffset), alignment: .top)
                .background(Color(red:0.06,green:0.09,blue:0.15).opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.5), radius: 20)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder private var nodeEditorOverlay: some View {
        if labVM.isNodeEditorVisible {
            NodeEditorView()
                .frame(width: min(geoSize.width - 16, 700),
                       height: min(geoSize.height * 0.8, 600))
                .offset(nodeOffset)
                .overlay(DragHandle(offset: $nodeOffset), alignment: .top)
                .background(Color(red:0.06,green:0.09,blue:0.15).opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.5), radius: 20)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    @ViewBuilder private var orbitDeltaOverlay: some View {
        if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
            OrbitDeltaNodeView(element: el)
                .offset(orbitOffset)
                .overlay(DragHandle(offset: $orbitOffset), alignment: .top)
                .position(x: geoSize.width * 0.5 + orbitOffset.width,
                          y: geoSize.height * 0.42 + orbitOffset.height)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

// MARK: — Drag Handle
// A thin grab bar at the top of each panel.
// Using a dedicated handle means the rest of the panel content
// passes touches through to the scene below (orbit controls work).
struct DragHandle: View {
    @Binding var offset: CGSize
    @State private var start = CGSize.zero

    var body: some View {
        HStack {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .contentShape(Rectangle()) // full width tappable
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { val in
                    offset = CGSize(
                        width:  start.width  + val.translation.width,
                        height: start.height + val.translation.height)
                }
                .onEnded { _ in start = offset }
        )
        .padding(.top, 6)
    }
}

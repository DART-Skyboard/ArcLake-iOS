
import SwiftUI

/// Extracted overlay views to avoid SwiftUI type-checker timeout
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        Group {
            periodicTableOverlay
            molCanvasOverlay
            orbitDeltaOverlay
            nodeEditorOverlay
        }
    }

    @ViewBuilder private var periodicTableOverlay: some View {
        if labVM.isPeriodicTableVisible {
            PeriodicTableView()
                .frame(width: min(geoSize.width - 16, 700),
                       height: min(geoSize.height * 0.62, 550))
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var molCanvasOverlay: some View {
        if labVM.isMolCanvasVisible {
            MolCanvasView()
                .frame(width: geoSize.width - 16,
                       height: min(geoSize.height * 0.62, 500))
                .transition(.opacity)
        }
    }

    @ViewBuilder private var orbitDeltaOverlay: some View {
        if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
            OrbitDeltaNodeView(element: el)
                .position(x: geoSize.width * 0.5, y: geoSize.height * 0.45)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder private var nodeEditorOverlay: some View {
        if labVM.isNodeEditorVisible {
            NodeEditorView()
                .frame(width: min(geoSize.width - 16, 700),
                       height: min(geoSize.height * 0.8, 600))
                .transition(.opacity)
        }
    }
}

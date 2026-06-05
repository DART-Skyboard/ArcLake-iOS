import SwiftUI

// MARK: — ArcOverlays
// Panels are draggable anywhere (including partially off-screen).
// Tapping any panel brings it to front.
// Reopening a panel always resets it to center.
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    // Z-order tracking — higher = in front
    @State private var zOrder: [String: Int] = [:]
    @State private var zCounter = 0

    // Open-count keys: incrementing resets DragShell @State (position goes back to center)
    @State private var openKeys: [String: Int] = [:]

    private func bringToFront(_ id: String) {
        zCounter += 1
        zOrder[id] = zCounter
    }

    private func openKey(_ id: String) -> Int { openKeys[id] ?? 0 }

    private func recordOpen(_ id: String) {
        openKeys[id] = (openKeys[id] ?? 0) + 1
        bringToFront(id)
    }

    var body: some View {
        ZStack {
            if labVM.isPeriodicTableVisible {
                DragShell(geoSize: geoSize, width: geoSize.width - 20,
                          height: min(geoSize.height * 0.65, 580)) {
                    PeriodicTableView()
                }
                .id("pt-\(openKey("pt"))")          // new id = reset position
                .zIndex(Double(zOrder["pt"] ?? 0))
                .onTapGesture { bringToFront("pt") }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .onAppear { recordOpen("pt") }
            }

            if labVM.isMolCanvasVisible {
                DragShell(geoSize: geoSize, width: geoSize.width - 20,
                          height: min(geoSize.height * 0.72, 600)) {
                    MolCanvasView()
                }
                .id("mc-\(openKey("mc"))")
                .zIndex(Double(zOrder["mc"] ?? 0))
                .onTapGesture { bringToFront("mc") }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .onAppear { recordOpen("mc") }
            }

            if labVM.isNodeEditorVisible {
                DragShell(geoSize: geoSize, width: geoSize.width - 20,
                          height: min(geoSize.height * 0.80, 640)) {
                    NodeEditorView()
                }
                .id("ne-\(openKey("ne"))")
                .zIndex(Double(zOrder["ne"] ?? 0))
                .onTapGesture { bringToFront("ne") }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .onAppear { recordOpen("ne") }
            }

            if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
                DragShell(geoSize: geoSize, width: min(geoSize.width - 20, 420),
                          height: 380) {
                    OrbitDeltaNodeView(element: el)
                }
                .id("probe-\(el.id)-\(openKey("probe"))")
                .zIndex(Double(zOrder["probe"] ?? 0))
                .onTapGesture { bringToFront("probe") }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onAppear { recordOpen("probe") }
            }

            if labVM.isMantisNavVisible {
                DragShell(geoSize: geoSize, width: geoSize.width - 20,
                          height: min(geoSize.height * 0.78, 640)) {
                    MantisNavigationView()
                }
                .id("mantis-\(openKey("mantis"))")
                .zIndex(Double(zOrder["mantis"] ?? 0))
                .onTapGesture { bringToFront("mantis") }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .onAppear { recordOpen("mantis") }
            }
        }
    }
}

// MARK: — DragShell
// Drag freely anywhere — no clamping.
// Position resets to center when .id() changes (on panel reopen).
struct DragShell<Content: View>: View {
    let geoSize: CGSize
    let width:   CGFloat
    let height:  CGFloat
    @ViewBuilder let content: () -> Content

    @GestureState private var dragDelta = CGSize.zero
    @State private var baseOffset = CGSize.zero

    var body: some View {
        content()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.55), radius: 22, y: 6)
            .offset(CGSize(
                width:  baseOffset.width  + dragDelta.width,
                height: baseOffset.height + dragDelta.height))
            .gesture(
                DragGesture(minimumDistance: 6)
                    // GestureState resets automatically on gesture end —
                    // we accumulate into baseOffset only on end.
                    .updating($dragDelta) { val, state, _ in
                        state = val.translation
                    }
                    .onEnded { val in
                        // Free movement — no clamping, panel can be anywhere
                        baseOffset = CGSize(
                            width:  baseOffset.width  + val.translation.width,
                            height: baseOffset.height + val.translation.height)
                    }
            )
    }
}


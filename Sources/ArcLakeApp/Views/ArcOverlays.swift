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
                // OrbitDeltaNodeView is fully self-contained (glass card + own drag).
                // NO DragShell wrapper — it floats free over the entire UI, never clipped.
                OrbitDeltaNodeView(element: el)
                    .id("probe-\(el.id)-\(openKey("probe"))")
                    .zIndex(Double(zOrder["probe"] ?? 999))
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

    // Resizable — like windows on macOS / iPadOS, works with touch too.
    // nil until the user grabs the corner handle; then the live size.
    @State private var userWidth:  CGFloat? = nil
    @State private var userHeight: CGFloat? = nil
    @State private var resizeStart: CGSize? = nil

    private var liveWidth:  CGFloat { userWidth  ?? width }

    var body: some View {
        content()
            // Width is fixed (or user-resized); height wraps content
            // until the user grabs the handle — then it's pinned.
            .frame(width: liveWidth)
            .frame(height: userHeight, alignment: .top)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7))
            // Resize grip — bottom-right corner, drag to resize
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(5)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { val in
                                if resizeStart == nil {
                                    resizeStart = CGSize(width: liveWidth,
                                                         height: userHeight ?? height)
                                }
                                guard let s = resizeStart else { return }
                                userWidth  = max(240, min(geoSize.width,  s.width  + val.translation.width))
                                userHeight = max(180, min(geoSize.height, s.height + val.translation.height))
                            }
                            .onEnded { _ in resizeStart = nil }
                    )
            }
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





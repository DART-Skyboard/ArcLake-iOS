import SwiftUI

// MARK: — ArcOverlays
// Single source of truth for all floating panels.
// Each panel uses sheet-style presentation anchored to screen center,
// draggable by its full header bar.
struct ArcOverlays: View {
    let geoSize: CGSize
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        // Use individual ZStacks so panels don't interfere with each other
        ZStack {
            if labVM.isPeriodicTableVisible {
                ArcFloatingPanel(
                    title:  "Periodic Table",
                    icon:   "tablecells",
                    color:  themeVM.accent,
                    geoSize: geoSize,
                    onClose: { labVM.isPeriodicTableVisible = false }
                ) {
                    PeriodicTableView()
                }
                .frame(width: geoSize.width - 20, height: min(geoSize.height * 0.64, 560))
                .id("pt")
            }

            if labVM.isMolCanvasVisible {
                ArcFloatingPanel(
                    title:  "Mol Canvas",
                    icon:   "scribble",
                    color:  .purple,
                    geoSize: geoSize,
                    onClose: { labVM.isMolCanvasVisible = false }
                ) {
                    MolCanvasView()
                }
                .frame(width: geoSize.width - 20, height: min(geoSize.height * 0.72, 580))
                .id("mc")
            }

            if labVM.isNodeEditorVisible {
                ArcFloatingPanel(
                    title:  "Node Editor",
                    icon:   "circle.connected.to.line.below",
                    color:  .orange,
                    geoSize: geoSize,
                    onClose: { labVM.isNodeEditorVisible = false }
                ) {
                    NodeEditorView()
                }
                .frame(width: geoSize.width - 20, height: min(geoSize.height * 0.78, 620))
                .id("ne")
            }

            if labVM.isOrbitDeltaVisible, let el = labVM.probeTarget {
                ArcFloatingPanel(
                    title:  "\(el.elementSymbol) — \(el.elementName)",
                    icon:   "atom",
                    color:  Color(el.category.color),
                    geoSize: geoSize,
                    onClose: { labVM.isOrbitDeltaVisible = false }
                ) {
                    OrbitDeltaNodeView(element: el)
                }
                .frame(width: min(geoSize.width - 20, 400), height: 360)
                .id("probe-\(el.id)")
            }
        }
    }
}

// MARK: — ArcFloatingPanel
// A single draggable panel.
// Key: offset() NOT position() — offset is relative to SwiftUI layout center,
// which prevents the "panel jumps to 0,0" bug and the shaking.
// Drag moves offset from its last resting place (stored in dragBase).
struct ArcFloatingPanel<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let geoSize: CGSize
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset   = CGSize.zero   // current panel position offset
    @State private var dragBase = CGSize.zero   // offset at gesture start

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag header ──────────────────────────────────────
            HStack(spacing: 8) {
                // Drag indicator
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 32, height: 3)
                    .padding(.leading, 8)

                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1)
                    .lineLimit(1)

                Spacer()

                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.trailing, 10)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08))
            .contentShape(Rectangle())
            // ── Drag gesture on header only ──────────────────────
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { val in
                        offset = CGSize(
                            width:  dragBase.width  + val.translation.width,
                            height: dragBase.height + val.translation.height)
                    }
                    .onEnded { _ in
                        dragBase = offset   // save resting position
                    }
            )

            Divider().background(color.opacity(0.2))

            // ── Panel content ────────────────────────────────────
            content()
        }
        .background(
            Color(red:0.06, green:0.09, blue:0.16)
                .opacity(0.97)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
        .offset(offset)                 // move by drag offset, centered by default
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

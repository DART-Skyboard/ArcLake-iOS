import SwiftUI

// MARK: — Equation Graph Canvas
// Renders labVM.equationNodes / equationConnections directly — this is the
// shared model built for the Algebra Menu redesign, not the generic
// EditorNode/NodeConnection system above. Kept as a separate, additive mode
// (toggled in the header) rather than merged into the existing pan/zoom/
// z-order machinery, so nothing about the existing node system changes.
// Dragging a curve between two sockets here calls
// labVM.connectEquationSockets(...) directly — the same call the Algebra
// Menu's own UI can make — so a connection made here is real graph data
// immediately, visible in both places.
struct EquationGraphCanvas: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    @State private var canvasOffset  = CGSize.zero
    @State private var canvasPanBase = CGSize.zero
    @State private var canvasScale: CGFloat = 1.0
    @State private var pendingSocket: (nodeId: UUID, socketId: UUID, isOutgoing: Bool)? = nil
    @State private var dragPositions: [UUID: CGPoint] = [:]   // live position while dragging a node

    private let nodeWidth: CGFloat = 150
    private let rowHeight: CGFloat = 20
    private let headerHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    let spacing: CGFloat = 28 * canvasScale
                    let ox = canvasOffset.width.truncatingRemainder(dividingBy: spacing)
                    let oy = canvasOffset.height.truncatingRemainder(dividingBy: spacing)
                    for x in stride(from: ox, through: size.width, by: spacing) {
                        for y in stride(from: oy, through: size.height, by: spacing) {
                            ctx.fill(Path(ellipseIn: CGRect(x: x-1, y: y-1, width: 2, height: 2)),
                                     with: .color(.white.opacity(0.06)))
                        }
                    }
                }

                ZStack {
                    ForEach(labVM.equationConnections) { conn in connectionPath(conn) }
                    ForEach(labVM.equationNodes) { node in nodeCard(node) }
                }
                .offset(canvasOffset)
                .scaleEffect(canvasScale)
            }
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { val in
                        canvasOffset = CGSize(width: canvasPanBase.width + val.translation.width,
                                               height: canvasPanBase.height + val.translation.height)
                    }
                    .onEnded { _ in canvasPanBase = canvasOffset }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { val in canvasScale = max(0.3, min(3.0, canvasScale * val)) }
            )
        }
    }

    // MARK: Node card
    @ViewBuilder
    private func nodeCard(_ node: EquationNode) -> some View {
        let pos = dragPositions[node.id] ?? node.position
        let height = headerHeight + CGFloat(max(node.incomingSockets.count, node.outgoingSockets.count)) * rowHeight + 8

        VStack(spacing: 0) {
            HStack {
                Text(node.title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text(node.role.rawValue.prefix(4))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .frame(height: headerHeight)
            .background(themeVM.accent.opacity(0.15))

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(node.incomingSockets) { s in socketRow(s, node: node, isOutgoing: false) }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(node.outgoingSockets) { s in socketRow(s, node: node, isOutgoing: true) }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: nodeWidth, height: height)
        .background(Color(red: 0.06, green: 0.09, blue: 0.14))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(themeVM.accent.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .position(pos)
        .gesture(
            DragGesture()
                .onChanged { val in dragPositions[node.id] = CGPoint(x: pos.x + val.translation.width, y: pos.y + val.translation.height) }
                .onEnded { _ in
                    if let final = dragPositions[node.id],
                       let idx = labVM.equationNodes.firstIndex(where: { $0.id == node.id }) {
                        labVM.equationNodes[idx].position = final
                    }
                    dragPositions[node.id] = nil
                }
        )
    }

    private func socketRow(_ socket: EquationSocket, node: EquationNode, isOutgoing: Bool) -> some View {
        HStack(spacing: 3) {
            if !isOutgoing {
                socketDot(socket, node: node, isOutgoing: false)
                Text(socket.label).font(.system(size: 7, design: .monospaced)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
            } else {
                Text(socket.label).font(.system(size: 7, design: .monospaced)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                socketDot(socket, node: node, isOutgoing: true)
            }
        }
        .frame(height: rowHeight)
    }

    private func socketDot(_ socket: EquationSocket, node: EquationNode, isOutgoing: Bool) -> some View {
        Circle()
            .fill(Color(uiColor: socket.kind.color))
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
            .onTapGesture {
                if let pending = pendingSocket {
                    if pending.isOutgoing != isOutgoing {
                        let from = pending.isOutgoing ? pending : (nodeId: node.id, socketId: socket.id, isOutgoing: true)
                        let to   = pending.isOutgoing ? (nodeId: node.id, socketId: socket.id, isOutgoing: false) : pending
                        labVM.connectEquationSockets(fromNode: from.nodeId, fromSocket: from.socketId,
                                                      toNode: to.nodeId, toSocket: to.socketId,
                                                      isDelta: socket.kind == .delta)
                    }
                    pendingSocket = nil
                } else {
                    pendingSocket = (node.id, socket.id, isOutgoing)
                }
            }
    }

    // MARK: Connection curves — same visual convention as the generic editor
    private func socketWorldPoint(nodeId: UUID, socketId: UUID, isOutgoing: Bool) -> CGPoint? {
        guard let node = labVM.equationNodes.first(where: { $0.id == nodeId }) else { return nil }
        let list = isOutgoing ? node.outgoingSockets : node.incomingSockets
        guard let idx = list.firstIndex(where: { $0.id == socketId }) else { return nil }
        let x = node.position.x + (isOutgoing ? nodeWidth/2 - 6 : -nodeWidth/2 + 6)
        let y = node.position.y - (CGFloat(list.count) * rowHeight)/2 + headerHeight/2 + CGFloat(idx) * rowHeight + rowHeight/2
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func connectionPath(_ conn: EquationConnection) -> some View {
        if let a = socketWorldPoint(nodeId: conn.fromNodeId, socketId: conn.fromSocketId, isOutgoing: true),
           let b = socketWorldPoint(nodeId: conn.toNodeId, socketId: conn.toSocketId, isOutgoing: false) {
            Path { p in
                p.move(to: a)
                let midX = (a.x + b.x) / 2
                p.addCurve(to: b, control1: CGPoint(x: midX, y: a.y), control2: CGPoint(x: midX, y: b.y))
            }
            .stroke(conn.isDelta ? Color.pink.opacity(0.7) : themeVM.accent.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1.5, dash: conn.isDelta ? [4, 3] : []))
        }
    }
}

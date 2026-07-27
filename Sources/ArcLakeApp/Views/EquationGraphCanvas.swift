import SwiftUI

// MARK: — Equation Graph Canvas
// Renders labVM.equationNodes / equationConnections DIRECTLY ALONGSIDE the
// existing generic EditorNode/NodeConnection canvas — not a separate toggled
// mode. Equation nodes built from the Algebra Menu appear in the SAME editor
// as everything else, at the same time, sharing the SAME pan/zoom transform
// (passed in as bindings from NodeEditorView) so the two layers move
// together as one space rather than drifting apart during a pan or pinch.
// Dragging a curve between two sockets here calls
// labVM.connectEquationSockets(...) directly — the same call the Algebra
// Menu's own UI can make — so a connection made here is real graph data
// immediately, visible in both places.
struct EquationGraphCanvas: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    @Binding var canvasOffset: CGSize
    @Binding var canvasScale: CGFloat
    @State private var pendingSocket: (nodeId: UUID, socketId: UUID, isOutgoing: Bool)? = nil
    @State private var dragPositions: [UUID: CGPoint] = [:]   // live position while dragging a node

    private let nodeWidth: CGFloat = 150
    private let rowHeight: CGFloat = 20
    private let headerHeight: CGFloat = 28

    var body: some View {
        // No GeometryReader, no gestures of its own, no background grid —
        // canvasArea already provides all of that. This view is purely the
        // equation nodes + their connections, sharing canvasArea's exact
        // pan/zoom transform via the bindings above so both layers pan and
        // zoom as one.
        ZStack {
            ForEach(labVM.equationConnections) { conn in connectionPath(conn) }
            ForEach(labVM.equationNodes) { node in nodeCard(node) }
        }
        .offset(canvasOffset)
        .scaleEffect(canvasScale)
        .allowsHitTesting(true)
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
                .onChanged { val in
                    // DragGesture reports translation in screen space, but
                    // pos is in content space — must divide by the current
                    // zoom so a screen-space finger movement maps to the
                    // correct content-space distance at any zoom level.
                    dragPositions[node.id] = CGPoint(
                        x: pos.x + val.translation.width / canvasScale,
                        y: pos.y + val.translation.height / canvasScale)
                }
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
        // Use the LIVE drag position while a node is being dragged, not the
        // committed one — otherwise the curve lags behind and only catches
        // up once the drag ends.
        let livePos = dragPositions[nodeId] ?? node.position
        let x = livePos.x + (isOutgoing ? nodeWidth/2 - 6 : -nodeWidth/2 + 6)
        let y = livePos.y - (CGFloat(list.count) * rowHeight)/2 + headerHeight/2 + CGFloat(idx) * rowHeight + rowHeight/2
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

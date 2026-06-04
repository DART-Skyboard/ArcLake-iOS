
import SwiftUI

/// Orbit Delta Node Editor — connects Math, MolCanvas, Physics, CFD
/// Matches web app #orbit-delta-node-editor canvas
struct NodeEditorView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var nodes: [EditorNode] = []
    @State private var connections: [NodeConnection] = []
    @State private var dragOffset = CGSize.zero
    @State private var canvasOffset = CGSize.zero
    @State private var pendingFrom: UUID? = nil

    struct EditorNode: Identifiable {
        let id = UUID()
        var type: NodeType
        var title: String
        var position: CGPoint
        var color: Color
        var ports: [String]

        enum NodeType { case atom, math, physics, molCanvas, cfd, env, sceneTab }
    }

    struct NodeConnection: Identifiable {
        let id = UUID()
        var fromNodeId: UUID; var fromPort: String
        var toNodeId: UUID;   var toPort: String
        var isDelta: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "circle.connected.to.line.below")
                    .foregroundColor(.purple)
                Text("ORBIT DELTA NODE EDITOR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                Spacer()
                // Add node buttons
                Menu {
                    ForEach([("Atom", "atom"), ("Math", "function"),
                             ("Physics", "waveform.path"), ("Mol Canvas", "scribble"),
                             ("CFD", "wind"), ("Env", "cloud"), ("Scene Tab", "cube")],
                            id: \.0) { name, icon in
                        Button { addNode(type: nodeType(name)) } label: {
                            Label(name, systemImage: icon)
                        }
                    }
                } label: {
                    Label("Add Node", systemImage: "plus.circle")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                }
                Button { labVM.isNodeEditorVisible = false } label: {
                    Image(systemName: "xmark").font(.caption).foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.black.opacity(0.5))

            // Canvas
            GeometryReader { geo in
                ZStack {
                    // Grid
                    Canvas { ctx, size in
                        for x in stride(from: CGFloat(0), to: size.width, by: 40) {
                            ctx.stroke(Path { p in p.move(to:CGPoint(x:x,y:0)); p.addLine(to:CGPoint(x:x,y:size.height)) },
                                with:.color(.cyan.opacity(0.05)), lineWidth: 0.5)
                        }
                        for y in stride(from: CGFloat(0), to: size.height, by: 40) {
                            ctx.stroke(Path { p in p.move(to:CGPoint(x:0,y:y)); p.addLine(to:CGPoint(x:size.width,y:y)) },
                                with:.color(.cyan.opacity(0.05)), lineWidth: 0.5)
                        }
                    }

                    // Connections
                    Canvas { ctx, _ in
                        for conn in connections {
                            guard let from = nodes.first(where:{$0.id==conn.fromNodeId}),
                                  let to   = nodes.first(where:{$0.id==conn.toNodeId}) else { continue }
                            let fp = CGPoint(x:from.position.x+canvasOffset.width+70,
                                            y:from.position.y+canvasOffset.height+20)
                            let tp = CGPoint(x:to.position.x+canvasOffset.width,
                                            y:to.position.y+canvasOffset.height+20)
                            let cp1 = CGPoint(x:fp.x+50, y:fp.y)
                            let cp2 = CGPoint(x:tp.x-50, y:tp.y)
                            var p = Path()
                            p.move(to: fp)
                            p.addCurve(to: tp, control1: cp1, control2: cp2)
                            ctx.stroke(p, with:.color(conn.isDelta ? .purple.opacity(0.7) : .cyan.opacity(0.5)),
                                style: StrokeStyle(lineWidth:1.5, dash: conn.isDelta ? [4,2] : []))
                        }
                    }

                    // Nodes
                    ForEach($nodes) { $node in
                        EditorNodeView(node: $node, accent: themeVM.accent,
                            pendingFrom: pendingFrom,
                            onPortTap: { port in handlePortTap(node: node, port: port) })
                            .offset(canvasOffset)
                    }
                }
                .coordinateSpace(name: "nodeCanvas")
                .gesture(DragGesture().onChanged { val in
                    canvasOffset = CGSize(width: dragOffset.width + val.translation.width,
                                         height: dragOffset.height + val.translation.height)
                }.onEnded { _ in dragOffset = canvasOffset })
            }

            // Footer
            HStack(spacing: 8) {
                Button("Clear All") { nodes.removeAll(); connections.removeAll() }
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.red.opacity(0.6))
                Spacer()
                Text("\(nodes.count) nodes · \(connections.count) connections")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3))
                Button("Compute") { labVM.log("Node graph computed: \(connections.count) pipes") }
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(themeVM.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
        }
        .background(Color(red:0.02, green:0.04, blue:0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(themeVM.accent.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .purple.opacity(0.15), radius: 20)
        .onAppear { if nodes.isEmpty { populateFromScene() } }
    }

    private func nodeType(_ name: String) -> EditorNode.NodeType {
        switch name {
        case "Atom": return .atom; case "Math": return .math
        case "Physics": return .physics; case "Mol Canvas": return .molCanvas
        case "CFD": return .cfd; case "Env": return .env; default: return .sceneTab
        }
    }

    private func addNode(type: EditorNode.NodeType) {
        let info = nodeInfo(type)
        let pos = CGPoint(x: Double(nodes.count % 3) * 160 + 40,
                         y: Double(nodes.count / 3) * 120 + 40)
        nodes.append(EditorNode(type: type, title: info.0, position: pos,
                               color: info.1, ports: info.2))
    }

    private func nodeInfo(_ t: EditorNode.NodeType) -> (String, Color, [String]) {
        switch t {
        case .atom:      return ("ATOM", .cyan, ["Protons","Neutrons","Shell K","Shell L","Mass","Arc-C"])
        case .math:      return ("MATH", .green, ["Input A","Input B","Output","Δ Result"])
        case .physics:   return ("PHYSICS", .orange, ["Gravity","Pressure","Temp","Velocity","Viscosity"])
        case .molCanvas: return ("MOL CANVAS", .purple, ["Bond","Atom","Δ In","Δ Out"])
        case .cfd:       return ("CFD", .blue, ["Particles","Density","Flow","Pressure"])
        case .env:       return ("ENV", .teal, ["Temperature","Gravity","Humidity"])
        case .sceneTab:  return ("SCENE TAB", .yellow, ["Atoms","Camera","CFD","Export"])
        }
    }

    private func handlePortTap(node: EditorNode, port: String) {
        if let fromId = pendingFrom {
            if fromId != node.id {
                connections.append(NodeConnection(fromNodeId: fromId, fromPort: "Out",
                    toNodeId: node.id, toPort: port, isDelta: false))
            }
            pendingFrom = nil
        } else {
            pendingFrom = node.id
        }
    }

    private func populateFromScene() {
        // Auto-populate with active scene data
        for el in labVM.selectedElements {
            let idx = nodes.count
            nodes.append(EditorNode(type: .atom, title: el.elementSymbol,
                position: CGPoint(x: Double(idx%3)*160+20, y: Double(idx/3)*140+20),
                color: .cyan, ports: ["Shell K","Shell L","Shell M","Mass","Arc-C"]))
        }
        if !labVM.molAtoms.isEmpty {
            nodes.append(EditorNode(type: .molCanvas, title: "MOL CANVAS",
                position: CGPoint(x: 300, y: 240), color: .purple,
                ports: ["Bond In","Δ In","Atoms","Output"]))
        }
        nodes.append(EditorNode(type: .math, title: "MATH",
            position: CGPoint(x: 160, y: 300), color: .green,
            ports: ["Input A","Input B","Δ","Output"]))
    }
}

struct EditorNodeView: View {
    @Binding var node: NodeEditorView.EditorNode
    let accent: Color
    let pendingFrom: UUID?
    let onPortTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Circle().fill(node.color).frame(width: 7, height: 7)
                Text(node.title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(node.color)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(node.color.opacity(0.12))

            // Ports
            VStack(alignment: .leading, spacing: 2) {
                ForEach(node.ports, id: \.self) { port in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(pendingFrom != nil && pendingFrom != node.id ?
                                accent : node.color.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .onTapGesture { onPortTap(port) }
                        Text(port)
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .frame(width: 120)
        .background(Color(red:0.05, green:0.08, blue:0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(pendingFrom == node.id ? accent : node.color.opacity(0.4), lineWidth: 0.8))
        .shadow(color: node.color.opacity(0.1), radius: 4)
        .position(node.position)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("nodeCanvas"))
                .onChanged { val in
                    // Use startLocation + translation for stable, non-accumulating drag
                    node.position = CGPoint(
                        x: val.startLocation.x + val.translation.width,
                        y: val.startLocation.y + val.translation.height
                    )
                }
        )
    }
}

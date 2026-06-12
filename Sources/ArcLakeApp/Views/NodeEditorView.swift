import SwiftUI

// MARK: — NodeEditorView
// Full node graph editor with:
//   • Group drawer — slides down from header, auto-populated from MolCanvas linkages
//   • Bring-to-front — tapping any node raises its z-index
//   • Pinch-to-zoom canvas
//   • Drag from periodic table adds atom nodes

struct NodeEditorView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    @State private var nodes:       [EditorNode]       = []
    @State private var connections: [NodeConnection]   = []
    // Per-tab node state — each scene tab keeps its own graph
    @State private var tabNodes:       [Int: [EditorNode]]     = [:]
    @State private var tabConnections: [Int: [NodeConnection]] = [:]
    @State private var tabGroups:      [Int: [NodeGroup]]      = [:]
    @State private var shownTab: Int = -1
    @State private var canvasOffset  = CGSize.zero
    @State private var canvasPanBase = CGSize.zero   // tracks pan start so no drift
    @State private var canvasScale: CGFloat = 1.0
    @State private var pendingFrom: UUID? = nil

    // Group drawer
    @State private var showGroupDrawer = false
    @State private var nodeGroups:  [NodeGroup]  = []
    @State private var selectedForGroup: Set<UUID> = []
    @State private var newGroupName = ""
    @State private var editingGroupId: UUID? = nil

    // Z-order
    @State private var zTop: UUID? = nil

    struct EditorNode: Identifiable {
        let id = UUID()
        var type: NodeType
        var title: String
        var position: CGPoint
        var color: Color
        var ports: [String]
        var groupId: UUID? = nil
    }

    struct NodeConnection: Identifiable {
        let id = UUID()
        var fromNodeId: UUID; var fromPort: String
        var toNodeId: UUID;   var toPort: String
        var isDelta: Bool
    }

    struct NodeGroup: Identifiable {
        let id = UUID()
        var name: String
        var nodeIds: [UUID]
        var color: Color = .cyan
    }

    enum NodeType: String, CaseIterable {
        case element = "ELEMENT"
        case formula = "FORMULA"
        case arc     = "ARC"
        case output  = "OUTPUT"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            groupDrawerBanner
            if showGroupDrawer { groupDrawerContent }
            canvasArea
            footer
        }
        .background(Color(red:0.03, green:0.06, blue:0.12))   // opaque — prevents see-through
        .onAppear {
            shownTab = labVM.activeTabIndex
            loadTab(shownTab)
            syncFromSceneAtoms()
            syncFromMolCanvas()
        }
        .onChange(of: labVM.molAtoms.count) { _ in syncFromMolCanvas() }
        // Dynamic per-tab graph: switching scene tabs swaps the node graph,
        // and atoms added to the active scene auto-create element nodes.
        .onChange(of: labVM.activeTabIndex) { newTab in
            saveTab(shownTab)
            shownTab = newTab
            loadTab(newTab)
            syncFromSceneAtoms()
        }
        .onChange(of: labVM.selectedElements.count) { _ in
            syncFromSceneAtoms()
        }
    }

    // ── Per-tab graph persistence ─────────────────────────────────
    private func saveTab(_ idx: Int) {
        guard idx >= 0 else { return }
        tabNodes[idx] = nodes
        tabConnections[idx] = connections
        tabGroups[idx] = nodeGroups
    }
    private func loadTab(_ idx: Int) {
        nodes = tabNodes[idx] ?? []
        connections = tabConnections[idx] ?? []
        nodeGroups = tabGroups[idx] ?? []
        pendingFrom = nil
        selectedForGroup = []
    }

    // Atoms in the ACTIVE scene tab → element nodes (added when atoms add)
    private func syncFromSceneAtoms() {
        for el in labVM.selectedElements {
            let title = "\(el.elementSymbol) (\(el.id))"
            if !nodes.contains(where: { $0.title == title }) {
                nodes.append(EditorNode(
                    type: .element, title: title,
                    position: CGPoint(
                        x: 50 + CGFloat(nodes.count % 5) * 90,
                        y: 50 + CGFloat(nodes.count / 5) * 80),
                    color: Color(el.category.color),
                    ports: ["in","out"]))
            }
        }
        // Remove nodes for atoms no longer in the scene (scene-pattern titles only)
        let valid = Set(labVM.selectedElements.map { "\($0.elementSymbol) (\($0.id))" })
        nodes.removeAll { n in
            n.type == .element && n.title.hasSuffix(")") && n.title.contains(" (")
                && !valid.contains(n.title)
        }
    }

    // MARK: — Header
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.connected.to.line.below")
                .font(.system(size: 11)).foregroundColor(themeVM.accent)
            Text("NODE EDITOR")
                .font(.custom("Orbitron-Bold", size: 11))
                .foregroundColor(.white).tracking(2)
            Spacer()

            // Add node buttons
            ForEach(NodeType.allCases, id: \.self) { nodeType in
                Button { addNode(type: nodeType) } label: {
                    Text("+\(nodeType.rawValue.prefix(3))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(themeVM.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            // Group drawer toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showGroupDrawer.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showGroupDrawer ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                    Text("GROUPS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(showGroupDrawer ? .black : themeVM.accent)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(showGroupDrawer ? themeVM.accent : themeVM.accent.opacity(0.1))
                .clipShape(Capsule())
            }

            Button { labVM.isNodeEditorVisible = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(themeVM.accent.opacity(0.05))
        .overlay(Rectangle().frame(height: 0.5)
            .foregroundColor(themeVM.accent.opacity(0.15)), alignment: .bottom)
    }

    // MARK: — Group Drawer Banner
    private var groupDrawerBanner: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showGroupDrawer.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 28, height: 3)
                Text("\(nodeGroups.count) GROUP\(nodeGroups.count == 1 ? "" : "S")")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Image(systemName: showGroupDrawer ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.white.opacity(0.03))
        }
    }

    // MARK: — Group Drawer Content (slides in/out)
    private var groupDrawerContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    // New group creation
                    HStack(spacing: 8) {
                        TextField("Group name…", text: $newGroupName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            guard !newGroupName.isEmpty, !selectedForGroup.isEmpty else { return }
                            let g = NodeGroup(name: newGroupName,
                                             nodeIds: Array(selectedForGroup))
                            nodeGroups.append(g)
                            // Assign group to nodes
                            for i in nodes.indices where selectedForGroup.contains(nodes[i].id) {
                                nodes[i].groupId = g.id
                            }
                            newGroupName = ""; selectedForGroup.removeAll()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(newGroupName.isEmpty || selectedForGroup.isEmpty
                                    ? .white.opacity(0.2) : themeVM.accent)
                        }
                        .disabled(newGroupName.isEmpty || selectedForGroup.isEmpty)
                    }
                    .padding(.horizontal, 10).padding(.top, 8)

                    if nodes.isEmpty {
                        Text("Add nodes to create groups")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                            .padding(8)
                    }

                    // Node selection chips for grouping
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                        ForEach(nodes) { node in
                            Button {
                                if selectedForGroup.contains(node.id) {
                                    selectedForGroup.remove(node.id)
                                } else {
                                    selectedForGroup.insert(node.id)
                                }
                            } label: {
                                Text(node.title)
                                    .font(.system(size: 9, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(selectedForGroup.contains(node.id)
                                        ? node.color.opacity(0.3)
                                        : Color.white.opacity(0.05))
                                    .foregroundColor(selectedForGroup.contains(node.id)
                                        ? node.color : .white.opacity(0.5))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(
                                        selectedForGroup.contains(node.id)
                                        ? node.color.opacity(0.6)
                                        : Color.clear, lineWidth: 0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 4)

                    // Existing groups
                    ForEach(nodeGroups) { group in
                        HStack(spacing: 8) {
                            Circle().fill(group.color).frame(width: 6, height: 6)
                            // Editable name
                            if editingGroupId == group.id {
                                TextField("", text: Binding(
                                    get: { group.name },
                                    set: { newVal in
                                        if let idx = nodeGroups.firstIndex(where:{$0.id==group.id}) {
                                            nodeGroups[idx].name = newVal
                                        }
                                    }))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white)
                                .onSubmit { editingGroupId = nil }
                            } else {
                                Text(group.name)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .onTapGesture(count: 2) { editingGroupId = group.id }
                            }
                            Text("(\(group.nodeIds.count))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            Button {
                                nodeGroups.removeAll{$0.id==group.id}
                                for i in nodes.indices where nodes[i].groupId == group.id {
                                    nodes[i].groupId = nil
                                }
                            } label: {
                                Image(systemName:"minus.circle")
                                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal, 10)
                    }
                }
            }
            .frame(maxHeight: 200)

            Divider().background(themeVM.accent.opacity(0.1))
        }
        .background(Color(red:0.05,green:0.08,blue:0.14))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: — Canvas
    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                // Background grid dots
                Canvas { ctx, size in
                    let spacing: CGFloat = 28 * canvasScale
                    let ox = canvasOffset.width.truncatingRemainder(dividingBy: spacing)
                    let oy = canvasOffset.height.truncatingRemainder(dividingBy: spacing)
                    for x in stride(from: ox, through: size.width, by: spacing) {
                        for y in stride(from: oy, through: size.height, by: spacing) {
                            ctx.fill(Path(ellipseIn: CGRect(x:x-1,y:y-1,width:2,height:2)),
                                with:.color(.white.opacity(0.06)))
                        }
                    }
                }

                // Connections + nodes share ONE transform group, so link
                // endpoints land exactly on sockets at any pan/zoom.
                ZStack {
                    ForEach(connections) { conn in
                        connectionPath(conn, in: geo.size)
                    }
                    ForEach(sortedNodes) { node in
                        nodeView(node)
                            .zIndex(node.id == zTop ? 100 : 0)
                    }
                }
                .offset(canvasOffset)
                .scaleEffect(canvasScale)
            }
            .clipped()
            // Canvas pan
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { val in
                        // Use startLocation to compute delta from start each frame
                        // so cumulative drift doesn't accelerate movement
                        canvasOffset = CGSize(
                            width:  canvasPanBase.width  + val.translation.width,
                            height: canvasPanBase.height + val.translation.height)
                    }
                    .onEnded { val in
                        canvasPanBase = canvasOffset
                    }
            )
            // Canvas pinch-to-zoom
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        canvasScale = max(0.3, min(3.0, canvasScale * val))
                    }
            )
        }
    }

    // Pre-computed sort so the compiler doesn't choke on inline closure
    private var sortedNodes: [EditorNode] {
        nodes.sorted { a, b in
            if a.id == zTop { return false }
            if b.id == zTop { return true }
            return false
        }
    }

    // Extracted node builder to reduce type-checker burden
    @ViewBuilder
    private func nodeView(_ node: EditorNode) -> some View {
        EditorNodeView(
            node: binding(for: node.id),
            isSelected: selectedForGroup.contains(node.id),
            accent: themeVM.accent,
            onTap: { zTop = node.id },
            onPortTap: { port in
                if let from = pendingFrom {
                    if from != node.id {
                        connections.append(NodeConnection(
                            fromNodeId: from, fromPort: port,
                            toNodeId: node.id, toPort: port,
                            isDelta: false))
                    }
                    pendingFrom = nil
                } else { pendingFrom = node.id }
            },
            canvasScale: canvasScale
        )
    }

    // MARK: — Footer
    private var footer: some View {
        HStack(spacing: 12) {
            Button("Clear All") { nodes.removeAll(); connections.removeAll(); nodeGroups.removeAll() }
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.red.opacity(0.7))

            Button("Reset View") { canvasOffset = .zero; canvasPanBase = .zero; canvasScale = 1.0 }
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))

            Spacer()

            Button("Compute") { labVM.log("Node graph: \(connections.count) connections") }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(themeVM.accent)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().frame(height:0.5)
            .foregroundColor(themeVM.accent.opacity(0.1)), alignment:.top)
    }

    // MARK: — Helpers

    private func addNode(type: NodeType) {
        let colors: [NodeType: Color] = [
            .element: .cyan, .formula: .purple, .arc: .orange, .output: .green
        ]
        let offset = CGFloat(nodes.count) * 20
        nodes.append(EditorNode(
            type: type,
            title: "\(type.rawValue) \(nodes.count+1)",
            position: CGPoint(x: 60 + offset, y: 80 + offset),
            color: colors[type] ?? .white,
            ports: ["in", "out"]))
    }

    // Auto-sync nodes from MolCanvas atom bonds
    private func syncFromMolCanvas() {
        guard !labVM.molAtoms.isEmpty else { return }
        let linked = labVM.molAtoms
        guard !linked.isEmpty else { return }

        let groupName = "Bond Group \(nodeGroups.count + 1)"
        var newNodeIds: [UUID] = []
        for atom in linked {
            if !nodes.contains(where: { $0.title == atom.symbol }) {
                let n = EditorNode(
                    type: .element, title: atom.symbol,
                    position: CGPoint(
                        x: 50 + CGFloat(nodes.count % 5) * 90,
                        y: 50 + CGFloat(nodes.count / 5) * 80),
                    color: Color(atom.color),
                    ports: ["in","out"])
                nodes.append(n)
                newNodeIds.append(n.id)
            }
        }
        if !newNodeIds.isEmpty {
            nodeGroups.append(NodeGroup(name: groupName, nodeIds: newNodeIds))
            for i in nodes.indices where newNodeIds.contains(nodes[i].id) {
                nodes[i].groupId = nodeGroups.last?.id
            }
        }
    }

    // syncFromSceneAtoms removed — use Mol Canvas button in AtomInfoCard instead

    private func binding(for id: UUID) -> Binding<EditorNode> {
        guard let idx = nodes.firstIndex(where: {$0.id == id}) else {
            return .constant(nodes[0])
        }
        return $nodes[idx]
    }

    // Node geometry — EXACT mirror of EditorNodeView's layout constants
    private func nodeRows(_ n: EditorNode) -> Int {
        let inP  = n.ports.filter { $0 == "in"  || $0.hasPrefix("in")  }.count
        let outP = n.ports.filter { $0 == "out" || $0.hasPrefix("out") }.count
        return max(inP, outP, 1)
    }
    private func nodeHeight(_ n: EditorNode) -> CGFloat {
        // header 28 + divider 1 + port rows + vertical padding 8
        28 + 1 + CGFloat(nodeRows(n)) * 20 + 8
    }
    /// Socket centers in canvas space. Nodes are placed with .position()
    /// (CENTER anchor), so convert center → top-left, then add socket offsets
    /// identical to EditorNodeView: x at node edges, y = headerH + row/2.
    private func outSocketPoint(_ n: EditorNode) -> CGPoint {
        CGPoint(x: n.position.x + 50,
                y: n.position.y - nodeHeight(n)/2 + 28 + 10)
    }
    private func inSocketPoint(_ n: EditorNode) -> CGPoint {
        CGPoint(x: n.position.x - 50,
                y: n.position.y - nodeHeight(n)/2 + 28 + 10)
    }

    @ViewBuilder
    private func connectionPath(_ conn: NodeConnection, in size: CGSize) -> some View {
        if let from = nodes.first(where:{$0.id==conn.fromNodeId}),
           let to   = nodes.first(where:{$0.id==conn.toNodeId}) {
            // Drawn INSIDE the same transform group as the nodes —
            // no manual canvasOffset/scale math, perfect socket registration
            let s = outSocketPoint(from)
            let e = inSocketPoint(to)
            let cpX = (s.x + e.x) / 2
            Path { p in
                p.move(to: s)
                p.addCurve(to: e,
                           control1: CGPoint(x: cpX, y: s.y),
                           control2: CGPoint(x: cpX, y: e.y))
            }
            .stroke(Color.cyan.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4,3]))
        }
    }
}

// MARK: — EditorNodeView
struct EditorNodeView: View {
    @Binding var node: NodeEditorView.EditorNode
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void
    let onPortTap: (String) -> Void

    let canvasScale: CGFloat           // passed in so drag compensates for zoom
    @GestureState private var dragDelta = CGSize.zero
    @State private var dragDeltaBase = CGPoint.zero

    // Port y-offset from node top — header is 28pt, each port row is 20pt
    private let headerH: CGFloat = 28
    private let portRowH: CGFloat = 20
    private let nodeWidth: CGFloat = 100
    private let socketR: CGFloat = 6

    private func socketY(portIndex: Int) -> CGFloat {
        headerH + CGFloat(portIndex) * portRowH + portRowH / 2
    }

    var body: some View {
        let inPorts  = node.ports.filter { $0 == "in"  || $0.hasPrefix("in") }
        let outPorts = node.ports.filter { $0 == "out" || $0.hasPrefix("out") }
        let totalRows = max(inPorts.count, outPorts.count)

        ZStack(alignment: .topLeading) {
            // Node body
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 5) {
                    Circle().fill(node.color).frame(width: 6, height: 6)
                    Text(node.title)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white).lineLimit(1)
                    Spacer()
                    Text(node.type.rawValue.prefix(3).uppercased())
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(height: headerH)
                .padding(.horizontal, 10)
                .background(node.color.opacity(0.14))

                Divider().frame(height: 1).background(node.color.opacity(0.2))

                // Port labels row
                VStack(spacing: 0) {
                    ForEach(0..<totalRows, id: \.self) { i in
                        HStack {
                            // In port label
                            if i < inPorts.count {
                                Text(inPorts[i])
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                            // Out port label
                            if i < outPorts.count {
                                Text(outPorts[i])
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: portRowH)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: nodeWidth,
                   height: headerH + 1 + CGFloat(totalRows) * portRowH + 8)
            .background(Color(red:0.07, green:0.1, blue:0.17))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? node.color.opacity(0.8) : node.color.opacity(0.25),
                        lineWidth: isSelected ? 1.5 : 0.8))

            // Left-edge sockets (in ports)
            ForEach(Array(inPorts.enumerated()), id: \.offset) { i, _ in
                Button { onPortTap(inPorts[i]) } label: {
                    Circle()
                        .fill(node.color)
                        .frame(width: socketR*2, height: socketR*2)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                }
                .offset(x: -socketR, y: socketY(portIndex: i) - socketR)
            }

            // Right-edge sockets (out ports)
            ForEach(Array(outPorts.enumerated()), id: \.offset) { i, _ in
                Button { onPortTap(outPorts[i]) } label: {
                    Circle()
                        .fill(node.color)
                        .frame(width: socketR*2, height: socketR*2)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                }
                .offset(x: nodeWidth - socketR, y: socketY(portIndex: i) - socketR)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 8)
        .position(CGPoint(
            x: node.position.x + dragDelta.width,
            y: node.position.y + dragDelta.height))
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragDelta) { val, state, _ in
                    // Compensate translation for canvas scale so node tracks finger 1:1
                    state = CGSize(
                        width:  val.translation.width  / canvasScale,
                        height: val.translation.height / canvasScale)
                }
                .onEnded { val in
                    node.position = CGPoint(
                        x: node.position.x + val.translation.width  / canvasScale,
                        y: node.position.y + val.translation.height / canvasScale)
                    dragDeltaBase = node.position
                }
        )
        .onTapGesture { onTap() }
    }
}






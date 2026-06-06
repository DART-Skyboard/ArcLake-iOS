import SwiftUI
import SceneKit

// MARK: — AutumnOverlay
// Floating wand button — opens Autumn chat sheet
struct AutumnOverlay: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @StateObject private var vm = AutumnViewModel.shared
    @State private var showChat = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    if vm.isListening {
                        HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { i in
                                Capsule()
                                    .fill(themeVM.accent)
                                    .frame(width: 3, height: CGFloat([8,16,12,10][i]))
                            }
                        }
                        .frame(height: 20)
                    }
                    Button { showChat = true } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [themeVM.accent.opacity(0.9), themeVM.accent.opacity(0.5)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 50, height: 50)
                                .shadow(color: themeVM.accent.opacity(0.4), radius: 10)
                            Image(systemName: vm.isListening ? "waveform" : "wand.and.stars")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 88)
            }
        }
        .sheet(isPresented: $showChat) {
            AutumnChatSheet()
                .environmentObject(labVM)
                .environmentObject(themeVM)
        }
    }
}

// MARK: — AutumnChatSheet
struct AutumnChatSheet: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @StateObject private var vm = AutumnViewModel.shared
    @State private var input = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) var dismiss
    @State private var showAshCanvas = false

    var body: some View {
        NavigationView {
            ZStack {
                themeVM.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // ── Drag indicator ──────────────────────────────────
                    ZStack {
                        LinearGradient(
                            colors: [themeVM.accent.opacity(0.12), Color.clear],
                            startPoint: .top, endPoint: .bottom)
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 36, height: 4)
                    }
                    .frame(height: 22)
                    .background(themeVM.bg.opacity(0.98))

                    // ── BRPN World Scene header ─────────────────────────
                    BRPNWorldSceneHeader()
                        .frame(height: 110)

                    // ── Avatar + title strip ────────────────────────────
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [themeVM.accent.opacity(0.3), themeVM.accent.opacity(0.08)],
                                    startPoint:.topLeading, endPoint:.bottomTrailing))
                                .frame(width:38,height:38)
                            Circle().stroke(themeVM.accent.opacity(0.5),lineWidth:1.2)
                                .frame(width:38,height:38)
                            Text("A")
                                .font(.system(size:15,weight:.bold,design:.monospaced))
                                .foregroundColor(themeVM.accent)
                        }
                        VStack(alignment:.leading,spacing:2) {
                            Text("AUTUMN")
                                .font(.custom("Orbitron-Bold",size:13))
                                .foregroundColor(.white).tracking(2)
                            HStack(spacing:4) {
                                Circle().fill(Color(red:0.2,green:1,blue:0.4)).frame(width:5,height:5)
                                Text("LEATR · BRPN · ArcLake")
                                    .font(.system(size:8,design:.monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        Spacer()
                        // Ash Canvas toggle
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showAshCanvas.toggle()
                            }
                        } label: {
                            Image(systemName: "scribble.variable")
                                .font(.system(size: 13))
                                .foregroundColor(showAshCanvas ? .black : themeVM.accent)
                                .frame(width: 28, height: 28)
                                .background(showAshCanvas ? themeVM.accent : themeVM.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Button { dismiss() } label: {
                            Image(systemName:"xmark")
                                .font(.system(size:11,weight:.bold))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width:28,height:28)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius:6))
                        }
                    }
                    .padding(.horizontal,16).padding(.vertical,10)
                    .background(themeVM.bg.opacity(0.97))
                    .overlay(Rectangle().frame(height:0.5)
                        .foregroundColor(themeVM.accent.opacity(0.2)),alignment:.bottom)

                    // ── Ash Canvas drawer (slides down) ─────────────────
                    if showAshCanvas {
                        AshCanvasDrawer(onSendToAutumn: { tool in
                            Task { await vm.send("Using \(tool) on Ash Canvas", labVM: labVM) }
                        })
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ── Messages ────────────────────────────────────────
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing:10) {
                                ForEach(vm.messages) { msg in
                                    AutumnBubble(msg:msg, accent:themeVM.accent).id(msg.id)
                                }
                                if vm.isTyping { AutumnTyping(accent:themeVM.accent) }
                            }.padding(14)
                        }
                        .onChange(of: vm.messages.count) { _ in
                            if let last = vm.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }

                    // ── Input ───────────────────────────────────────────
                    Divider().background(themeVM.accent.opacity(0.12))
                    HStack(spacing:8) {
                        TextField("Ask Autumn...", text: $input, axis: .vertical)
                            .font(.system(size:13,design:.monospaced))
                            .foregroundColor(.white).tint(themeVM.accent)
                            .focused($focused).lineLimit(1...4)
                            .padding(.horizontal,10).padding(.vertical,7)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius:10))
                            .toolbar {
                                ToolbarItemGroup(placement:.keyboard) {
                                    Spacer()
                                    Button("Done") { focused=false }.foregroundColor(themeVM.accent)
                                }
                            }
                        Button {
                            let msg = input.trimmingCharacters(in:.whitespaces)
                            guard !msg.isEmpty else { return }
                            input = ""; focused = false
                            Task { await vm.send(msg, labVM: labVM) }
                        } label: {
                            Image(systemName:"arrow.up.circle.fill")
                                .font(.system(size:26))
                                .foregroundColor(input.isEmpty ? themeVM.accent.opacity(0.3) : themeVM.accent)
                        }.disabled(input.isEmpty)
                    }
                    .padding(.horizontal,12).padding(.vertical,8)
                    .background(themeVM.bg)
                }
            }
            .navigationBarHidden(true)
        }
        // Taller default — avatar fully visible, draggable to full screen
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: — BRPN World Scene Header
// Mini live node globe — shows active BRPN nodes from GAS presence
struct BRPNWorldSceneHeader: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var nodes: [BRPNNodeDot] = []
    @State private var rotation: Double = 0
    @State private var timer: Timer?

    struct BRPNNodeDot: Identifiable {
        let id = UUID()
        var angle: Double
        var elevation: Double
        var size: CGFloat
        var color: Color
        var pulse: Bool = false
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red:0.01,green:0.05,blue:0.12), Color(red:0.02,green:0.08,blue:0.18)],
                startPoint: .top, endPoint: .bottom)

            // Grid lines (icosahedron wireframe approximation)
            Canvas { ctx, size in
                let cx = size.width/2, cy = size.height/2
                let r = min(cx, cy) * 0.8
                // Latitude rings
                for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
                    let yr = r * cos(lat * .pi/180) * 0.4
                    let xr = r * cos(lat * .pi/180)
                    var path = Path()
                    path.addEllipse(in: CGRect(x: cx-xr, y: cy-yr*0.5, width: xr*2, height: yr))
                    ctx.stroke(path, with: .color(Color.cyan.opacity(0.12)), lineWidth: 0.5)
                }
                // Meridian lines
                for lon in stride(from: 0.0, through: 150.0, by: 30.0) {
                    let x = cx + r * cos((lon + rotation) * .pi/180) * 0.85
                    let y = cy + r * sin((lon + rotation) * .pi/180) * 0.35
                    var path = Path()
                    path.move(to: CGPoint(x: cx, y: cy - r * 0.4))
                    path.addQuadCurve(to: CGPoint(x: cx, y: cy + r * 0.4),
                                      control: CGPoint(x: x, y: y))
                    ctx.stroke(path, with: .color(Color.cyan.opacity(0.1)), lineWidth: 0.5)
                }
            }
            .animation(.linear(duration: 0).repeatForever(autoreverses: false), value: rotation)

            // BRPN nodes
            GeometryReader { geo in
                let cx = geo.size.width/2
                let cy = geo.size.height/2
                let r  = min(cx, cy) * 0.72

                ForEach(nodes) { node in
                    let x = cx + r * cos((node.angle + rotation) * .pi/180) * cos(node.elevation * .pi/180)
                    let y = cy + r * sin(node.elevation * .pi/180) * 0.5
                    Circle()
                        .fill(node.color)
                        .frame(width: node.size, height: node.size)
                        .shadow(color: node.color.opacity(0.6), radius: node.pulse ? 6 : 2)
                        .position(x: x, y: y)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                   value: node.pulse)
                }
            }

            // Labels
            VStack {
                Spacer()
                HStack {
                    Text("BRPN WORLD")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundColor(themeVM.accent.opacity(0.5))
                        .tracking(2)
                    Spacer()
                    Text("\(nodes.count) NODES")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .onAppear { setupNodes(); startRotation() }
        .onDisappear { timer?.invalidate() }
    }

    private func setupNodes() {
        // Seed with local node + random active users
        nodes = [
            BRPNNodeDot(angle: 0, elevation: 20, size: 7, color: .cyan, pulse: true),       // local
            BRPNNodeDot(angle: 72, elevation: -10, size: 4, color: .green.opacity(0.8), pulse: false),
            BRPNNodeDot(angle: 144, elevation: 35, size: 4, color: Color(red:0.4,green:0.8,blue:1), pulse: false),
            BRPNNodeDot(angle: 216, elevation: -25, size: 3, color: .purple.opacity(0.7), pulse: false),
            BRPNNodeDot(angle: 288, elevation: 10, size: 5, color: .orange.opacity(0.6), pulse: true),
        ]
        // Fetch live node count from GAS in background
        Task { await fetchLiveNodes() }
    }

    private func fetchLiveNodes() async {
        // Ping GAS presence endpoint for live node data
        let gasURL = "https://script.google.com/macros/s/AKfycbwBRPNLEATRAutumnArcLakeiOS/exec"
        guard let url = URL(string: gasURL) else { return }
        var req = URLRequest(url: url); req.httpMethod = "GET"
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
              let count = json["activeNodes"] as? Int else { return }
        // Add extra nodes up to count
        let extras = max(0, count - nodes.count)
        var newNodes = nodes
        for i in 0..<min(extras, 15) {
            newNodes.append(BRPNNodeDot(
                angle: Double(i) * (360.0 / Double(max(extras,1))),
                elevation: Double.random(in: -40...40),
                size: CGFloat.random(in: 3...5),
                color: [Color.cyan, .green, .purple, .orange].randomElement()!.opacity(0.7),
                pulse: false))
        }
        await MainActor.run { nodes = newNodes }
    }

    private func startRotation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            rotation += 0.3
            if rotation >= 360 { rotation = 0 }
        }
    }
}

// MARK: — Ash Canvas Drawer v3
// Single-tap handler on canvas — hit-tests node rects manually.
// This avoids SwiftUI ZStack gesture interception issues.
struct AshCanvasDrawer: View {
    let onSendToAutumn: (String) -> Void
    @EnvironmentObject var themeVM: ArcThemeViewModel

    private let tools: [(String, String, Color)] = [
        ("M", "M MAZE",     .cyan),
        ("P", "P PUZZLE",   .purple),
        ("E", "E ENVELOPE", .green),
        ("H", "H HAMMER",   .orange),
        ("S", "S STICK",    Color(white:0.85)),
        ("K", "K KNIFE",    .red),
        ("R", "R SCISSORS", .pink),
    ]

    struct AshNode: Identifiable {
        let id = UUID()
        var position: CGPoint
        var tool: String
        var color: Color
        var isSocket: Bool = false
        var socketShell: String = ""
    }
    struct AshLink: Identifiable {
        let id = UUID()
        var fromId: UUID
        var toId: UUID
    }

    // Mode state — mirrors web app _ac object
    @State private var linkMode    = false
    @State private var activeTool: String? = nil
    @State private var nodes:      [AshNode] = []
    @State private var links:      [AshLink] = []
    @State private var pendingLink: UUID? = nil       // glowing source in link mode
    @State private var selectedIds: Set<UUID> = []    // multi-selected nodes
    @State private var selectedLinkIds: Set<UUID> = []

    private let nodeSize: CGFloat = 32
    private let socketX_offset: CGFloat = 22  // from right edge

    // Socket definitions
    private let socketDefs: [(String, Color, String)] = [
        ("GEO",  Color(red:0.3, green:0.9, blue:0.3), "geo"),
        ("MAR",  Color(red:0.2, green:0.6, blue:1.0), "mar"),
        ("AERO", Color(red:0.8, green:0.3, blue:1.0), "aero"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ASH CANVAS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.7)).tracking(2)
                    .padding(.leading, 12)
                Spacer()
                Text(headerHint)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3)).padding(.trailing, 10)
            }
            .padding(.vertical, 5)
            .background(themeVM.accent.opacity(0.05))

            // Toolbar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    toolPill("← SELECT", Color.white,  activeTool == nil && !linkMode) {
                        activeTool = nil; linkMode = false; pendingLink = nil
                    }
                    toolPill("⟷ LINK", Color(red:0.7,green:0.5,blue:1.0), linkMode) {
                        linkMode.toggle(); activeTool = nil; pendingLink = nil
                    }
                    Divider().frame(height: 16).background(Color.white.opacity(0.15))
                    ForEach(tools, id: \.0) { key, label, col in
                        toolPill(label, col, activeTool == key && !linkMode) {
                            if activeTool == key { activeTool = nil }
                            else { activeTool = key; linkMode = false; pendingLink = nil }
                        }
                    }
                    Divider().frame(height: 16).background(Color.white.opacity(0.15))
                    toolPill("→ AUTUMN", themeVM.accent, false) {
                        let t = nodes.filter{!$0.isSocket}.map{$0.tool}.joined(separator:",")
                        onSendToAutumn(t.isEmpty ? "canvas" : t)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .background(Color.white.opacity(0.02))

            // Canvas — ONE gesture handler on the whole canvas
            GeometryReader { geo in
                let sockPositions = socketYPositions(height: geo.size.height,
                                                     x: geo.size.width - socketX_offset)
                ZStack {
                    Color(red:0.025, green:0.05, blue:0.1)

                    // Draw links
                    Canvas { ctx, _ in
                        for lnk in links {
                            guard let p1 = pos(lnk.fromId, sockPositions),
                                  let p2 = pos(lnk.toId,   sockPositions) else { continue }
                            let sel = selectedLinkIds.contains(lnk.id)
                            var path = Path()
                            path.move(to: p1); path.addLine(to: p2)
                            ctx.stroke(path,
                                with: .color(sel ? Color.yellow : Color.cyan.opacity(0.45)),
                                style: StrokeStyle(lineWidth: sel ? 2.5 : 1.2,
                                                   dash: sel ? [] : [4,3]))
                        }
                    }

                    // Draw nodes
                    ForEach(nodes.filter{!$0.isSocket}) { n in
                        nodeChip(n)
                            .position(n.position)
                    }

                    // Draw sockets (right rail)
                    ForEach(Array(socketDefs.enumerated()), id: \.offset) { i, s in
                        socketChip(s.0, s.1, s.2, sockPositions[i])
                    }
                }
                // SINGLE tap handler — hit-tests everything manually
                .contentShape(Rectangle())
                .onTapGesture { tappedAt in
                    handleTap(at: tappedAt,
                              canvasSize: geo.size,
                              sockPositions: sockPositions)
                }
                // Drag handler — only moves nodes in select mode
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { val in
                            guard !linkMode, activeTool == nil else { return }
                            let hit = nodes.firstIndex { n in
                                !n.isSocket &&
                                abs(n.position.x - val.startLocation.x) < nodeSize &&
                                abs(n.position.y - val.startLocation.y) < nodeSize
                            }
                            if let idx = hit {
                                nodes[idx].position = val.location
                            }
                        }
                )
            }
            .frame(height: 148)

            // Footer
            HStack(spacing: 8) {
                Button("DEL") { deleteSelected() }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(hasSelection ? .white : .red.opacity(0.4))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(hasSelection ? Color.red.opacity(0.75) : Color.red.opacity(0.1))
                    .clipShape(Capsule())

                Button("RESET") {
                    nodes=[]; links=[]; selectedIds=[]; selectedLinkIds=[]
                    pendingLink=nil; activeTool=nil; linkMode=false
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.white.opacity(0.06)).clipShape(Capsule())

                Spacer()
                if let _ = pendingLink {
                    Text("TAP TARGET NODE →")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red:0.7,green:0.5,blue:1.0).opacity(0.9))
                } else if hasSelection {
                    Text("\(selectedIds.count+selectedLinkIds.count) SELECTED — DEL to remove")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.white.opacity(0.03))
            .overlay(Rectangle().frame(height:0.5)
                .foregroundColor(themeVM.accent.opacity(0.1)), alignment:.top)
        }
        .background(Color(red:0.025, green:0.05, blue:0.1))
        .overlay(Rectangle().frame(height:0.5)
            .foregroundColor(themeVM.accent.opacity(0.2)), alignment:.bottom)
    }

    // MARK: — Tap handler (replaces per-node onTapGesture)
    private func handleTap(at pt: CGPoint, canvasSize: CGSize, sockPositions: [CGPoint]) {
        // 1. Check tool nodes
        for n in nodes where !n.isSocket {
            if abs(pt.x - n.position.x) < nodeSize && abs(pt.y - n.position.y) < nodeSize {
                handleNodeTap(n.id)
                return
            }
        }
        // 2. Check socket circles
        for (i, s) in socketDefs.enumerated() {
            let sp = sockPositions[i]
            if abs(pt.x - sp.x) < 20 && abs(pt.y - sp.y) < 20 {
                // Ensure socket node exists
                if !nodes.contains(where:{$0.isSocket && $0.socketShell==s.2}) {
                    nodes.append(AshNode(position: sp, tool: s.0,
                                         color: s.1, isSocket: true, socketShell: s.2))
                }
                let sid = nodes.first{$0.isSocket && $0.socketShell==s.2}!.id
                handleNodeTap(sid)
                return
            }
        }
        // 3. Check link lines (within 10pt of midpoint)
        for lnk in links {
            guard let p1 = pos(lnk.fromId, sockPositions),
                  let p2 = pos(lnk.toId,   sockPositions) else { continue }
            if pointNearLine(pt, p1, p2, threshold: 10) {
                if !linkMode {
                    if selectedLinkIds.contains(lnk.id) { selectedLinkIds.remove(lnk.id) }
                    else { selectedLinkIds.insert(lnk.id); selectedIds.removeAll() }
                }
                return
            }
        }
        // 4. Background tap
        if !linkMode {
            selectedIds.removeAll(); selectedLinkIds.removeAll()
        } else if let tool = activeTool {
            // Place node in link+tool? No — ignore, keep separate
            let _ = tool
        } else if activeTool != nil {
            // shouldn't reach here
        } else {
            // Background tap in select mode = place if tool active, else deselect
        }
        if let tool = activeTool, !linkMode {
            let col = tools.first{$0.0==tool}?.2 ?? .white
            nodes.append(AshNode(position: pt, tool: tool, color: col))
        }
    }

    // MARK: — Node tap logic (mirrors web app exactly)
    private func handleNodeTap(_ id: UUID) {
        if linkMode {
            if pendingLink == nil {
                pendingLink = id          // set source, glows yellow
            } else if pendingLink == id {
                pendingLink = nil         // tap same = cancel
            } else {
                links.append(AshLink(fromId: pendingLink!, toId: id))
                pendingLink = id          // chain: last linked node becomes new source
            }
        } else {
            // SELECT mode — toggle
            if selectedIds.contains(id) { selectedIds.remove(id) }
            else { selectedIds.insert(id); selectedLinkIds.removeAll() }
        }
    }

    private func deleteSelected() {
        links.removeAll { selectedLinkIds.contains($0.id) }
        selectedLinkIds.removeAll()
        for nid in selectedIds {
            links.removeAll { $0.fromId==nid || $0.toId==nid }
            nodes.removeAll { $0.id==nid }
        }
        selectedIds.removeAll()
        pendingLink = nil
    }

    // MARK: — Visual chips

    @ViewBuilder
    private func nodeChip(_ n: AshNode) -> some View {
        let isPending  = pendingLink == n.id
        let isSelected = selectedIds.contains(n.id)
        Text(n.tool)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(n.color)
            .frame(width: nodeSize, height: nodeSize)
            .background(n.color.opacity(isSelected ? 0.45 : isPending ? 0.35 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(isPending  ? Color.yellow
                      : isSelected ? n.color
                      : n.color.opacity(0.35),
                        lineWidth: (isPending || isSelected) ? 2.5 : 1))
            .shadow(color: isPending  ? .yellow.opacity(0.7)
                         : isSelected ? n.color.opacity(0.5) : .clear, radius: 8)
    }

    @ViewBuilder
    private func socketChip(_ label: String, _ color: Color, _ shell: String,
                             _ pt: CGPoint) -> some View {
        let sockNode   = nodes.first{$0.isSocket && $0.socketShell==shell}
        let isPending  = sockNode.map{pendingLink==$0.id} ?? false
        let isSelected = sockNode.map{selectedIds.contains($0.id)} ?? false
        VStack(spacing: 2) {
            Circle()
                .fill(color.opacity(isPending ? 1.0 : isSelected ? 0.7 : 0.25))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(color, lineWidth: isPending ? 2.5 : 1.5))
                .shadow(color: (isPending||isSelected) ? color.opacity(0.8) : .clear, radius: 7)
            Text(label)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.85))
        }
        .position(pt)
        // No onTapGesture here — handled by handleTap() above
    }

    // MARK: — Helpers

    private var hasSelection: Bool { !selectedIds.isEmpty || !selectedLinkIds.isEmpty }

    private var headerHint: String {
        if linkMode { return pendingLink != nil ? "LINK — tap target" : "LINK — tap source" }
        if activeTool != nil { return "PLACE — tap canvas" }
        return "SELECT — tap nodes or links"
    }

    private func socketYPositions(height: CGFloat, x: CGFloat) -> [CGPoint] {
        let pad: CGFloat = 20
        let gap = (height - pad*2) / CGFloat(socketDefs.count - 1)
        return socketDefs.indices.map { i in CGPoint(x: x, y: pad + CGFloat(i)*gap) }
    }

    private func pos(_ id: UUID, _ sockPos: [CGPoint]) -> CGPoint? {
        if let n = nodes.first(where:{$0.id==id}) { return n.position }
        return nil
    }

    private func pointNearLine(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint,
                               threshold: CGFloat) -> Bool {
        let ab = CGPoint(x: b.x-a.x, y: b.y-a.y)
        let ap = CGPoint(x: p.x-a.x, y: p.y-a.y)
        let len2 = ab.x*ab.x + ab.y*ab.y
        guard len2 > 0 else { return false }
        let t = max(0, min(1, (ap.x*ab.x + ap.y*ab.y)/len2))
        let nearest = CGPoint(x: a.x+t*ab.x, y: a.y+t*ab.y)
        let dx = p.x-nearest.x; let dy = p.y-nearest.y
        return sqrt(dx*dx+dy*dy) < threshold
    }

    @ViewBuilder
    private func toolPill(_ label: String, _ color: Color, _ active: Bool,
                          action: @escaping()->Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .black : color.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(active ? color : color.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

// MARK: — Message bubble (unchanged)
struct AutumnBubble: View {
    let msg: AutumnMessage
    let accent: Color
    var isAutumn: Bool { msg.role == .autumn }
    var body: some View {
        HStack(alignment:.bottom,spacing:6) {
            if isAutumn {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width:20,height:20)
                    Text("A").font(.system(size:8,weight:.bold,design:.monospaced)).foregroundColor(accent)
                }
            } else { Spacer(minLength:40) }
            Text(msg.text)
                .font(.system(size:12,design:.monospaced)).foregroundColor(.white)
                .padding(.horizontal,10).padding(.vertical,7)
                .background(isAutumn ? accent.opacity(0.1) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius:10))
            if !isAutumn { Spacer(minLength:0) }
        }
        .frame(maxWidth:.infinity, alignment: isAutumn ? .leading : .trailing)
    }
}

struct AutumnTyping: View {
    let accent: Color
    @State private var phase = 0
    let timer = Timer.publish(every:0.4, on:.main, in:.common).autoconnect()
    var body: some View {
        HStack(spacing:4) {
            ForEach(0..<3,id:\.self) { i in
                Circle().fill(accent.opacity(phase==i ? 0.9 : 0.3)).frame(width:5,height:5)
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .onReceive(timer) { _ in phase=(phase+1)%3 }
    }
}



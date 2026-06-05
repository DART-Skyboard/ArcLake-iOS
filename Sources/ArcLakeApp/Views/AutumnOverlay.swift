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

// MARK: — Ash Canvas Drawer
// LEATR natural tools — mirrors the web app Ash Canvas
struct AshCanvasDrawer: View {
    let onSendToAutumn: (String) -> Void
    @EnvironmentObject var themeVM: ArcThemeViewModel

    private let tools: [(String, String)] = [
        ("M", "M MAZE"),
        ("P", "P PUZZLE"),
        ("E", "E ENVELOPE"),
        ("H", "H HAMMER"),
        ("S", "S STICK"),
        ("K", "K KNIFE"),
        ("R", "R SCISSORS"),
    ]
    @State private var activeTool: String? = nil
    @State private var nodes: [AshNode] = []
    @State private var links: [(UUID, UUID)] = []
    @State private var pendingLink: UUID? = nil

    struct AshNode: Identifiable {
        let id = UUID()
        var position: CGPoint
        var tool: String
        var color: Color
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tool header
            HStack(spacing: 0) {
                Text("ASH CANVAS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.7))
                    .tracking(2)
                    .padding(.leading, 12)
                Spacer()
                Text("NATURAL TOOLS — tap to place")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.trailing, 12)
            }
            .padding(.vertical, 6)
            .background(themeVM.accent.opacity(0.05))

            // Tool buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tools, id: \.0) { key, label in
                        Button {
                            activeTool = activeTool == key ? nil : key
                        } label: {
                            Text(label)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(activeTool == key ? .black : themeVM.accent)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(activeTool == key ? themeVM.accent : themeVM.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                    Button("→ SEND TO AUTUMN") {
                        if let tool = activeTool { onSendToAutumn(tool) }
                    }
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(activeTool != nil ? .black : .white.opacity(0.3))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(activeTool != nil ? themeVM.accent : Color.white.opacity(0.05))
                    .clipShape(Capsule())
                    .disabled(activeTool == nil)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }

            // Canvas area
            ZStack {
                Color(red:0.03,green:0.06,blue:0.12)

                // Links
                Canvas { ctx, _ in
                    for (a, b) in links {
                        if let n1 = nodes.first(where:{$0.id==a}),
                           let n2 = nodes.first(where:{$0.id==b}) {
                            var p = Path()
                            p.move(to: n1.position)
                            p.addLine(to: n2.position)
                            ctx.stroke(p, with: .color(Color.cyan.opacity(0.4)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3,2]))
                        }
                    }
                }

                // Nodes
                ForEach(nodes) { node in
                    Text(node.tool)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(node.color)
                        .frame(width: 28, height: 28)
                        .background(node.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(pendingLink == node.id ? node.color : node.color.opacity(0.4), lineWidth: 1))
                        .position(node.position)
                        .onTapGesture {
                            if let from = pendingLink, from != node.id {
                                links.append((from, node.id))
                                pendingLink = nil
                            } else {
                                pendingLink = node.id
                            }
                        }
                }

                // Tap to place
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard let tool = activeTool else { return }
                        let colors: [String: Color] = ["M":.cyan,"P":.purple,"E":.green,
                                                        "H":.orange,"S":.white,"K":.red,"R":.pink]
                        nodes.append(AshNode(position: loc, tool: tool,
                                             color: colors[tool] ?? .white))
                    }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 0))

            // Footer actions
            HStack(spacing: 12) {
                Button("LINK") { /* enable link mode — handled via pendingLink */ }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(pendingLink != nil ? .black : themeVM.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(pendingLink != nil ? themeVM.accent : themeVM.accent.opacity(0.1))
                    .clipShape(Capsule())
                Button("DEL") { if !nodes.isEmpty { nodes.removeLast() } }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.1)).clipShape(Capsule())
                Button("RESET") { nodes.removeAll(); links.removeAll(); pendingLink = nil }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.05)).clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.white.opacity(0.03))
            .overlay(Rectangle().frame(height:0.5)
                .foregroundColor(themeVM.accent.opacity(0.1)), alignment:.top)
        }
        .background(Color(red:0.03,green:0.06,blue:0.12))
        .overlay(Rectangle().frame(height:0.5)
            .foregroundColor(themeVM.accent.opacity(0.2)), alignment:.bottom)
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

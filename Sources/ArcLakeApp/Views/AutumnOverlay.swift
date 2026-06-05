import SwiftUI

// MARK: — AutumnOverlay
// Floating push-to-talk button always available in ArcLake.
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

    var body: some View {
        NavigationView {
            ZStack {
                themeVM.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // ── Top gap banner (like web app Ash Canvas drawer) ─────
                    ZStack {
                        // Subtle gradient glow at top
                        LinearGradient(
                            colors: [themeVM.accent.opacity(0.12), Color.clear],
                            startPoint: .top, endPoint: .bottom)
                        HStack {
                            // Drag indicator
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 36, height: 4)
                        }
                    }
                    .frame(height: 22)
                    .background(themeVM.bg.opacity(0.98))

                    // ── Avatar + title strip ────────────────────────────────
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

                    // Messages
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

                    // Input
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
        .presentationDetents([.fraction(0.65),.large])
    }
}

// MARK: — Message bubble
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

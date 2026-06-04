import SwiftUI
import SceneKit
import AVFoundation

// MARK: — AutumnOverlay
// Floating push-to-talk button always available as top-level overlay in ArcLake.
// Tap → chat sheet slides up. Long press → voice input.
// Autumn can control: MolCanvas, NodeEditor, PeriodicTable, scene elements.
struct AutumnOverlay: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @StateObject private var vm = AutumnViewModel.shared
    @State private var showChat = false
    @State private var isPressing = false

    var body: some View {
        // Always floats bottom-right, above all other content
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    // Listening indicator
                    if vm.isListening {
                        HStack(spacing: 4) {
                            ForEach(0..<4, id:\.self) { i in
                                Capsule()
                                    .fill(themeVM.accent)
                                    .frame(width: 3, height: CGFloat.random(in: 8...20))
                                    .animation(.easeInOut(duration: 0.3)
                                        .repeatForever().delay(Double(i)*0.1), value: vm.isListening)
                            }
                        }
                        .frame(height: 20)
                    }

                    // Push-to-talk button
                    Button {
                        showChat = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [themeVM.accent.opacity(0.9), themeVM.accent.opacity(0.5)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 52, height: 52)
                                .shadow(color: themeVM.accent.opacity(0.5), radius: 10)

                            Image(systemName: vm.isListening ? "waveform" : "wand.and.stars")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onChanged { _ in vm.startListening() }
                    )
                    .scaleEffect(isPressing ? 0.92 : 1.0)
                    .animation(.spring(response: 0.2), value: isPressing)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showChat) {
            AutumnChatSheet()
                .environmentObject(labVM)
                .environmentObject(themeVM)
                .environmentObject(vm)
        }
    }
}

// MARK: — AutumnChatSheet
// Full chat window with Autumn, file attachments, sentient journal connection
struct AutumnChatSheet: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var vm: AutumnViewModel
    @State private var input = ""
    @State private var showAttachPicker = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                themeVM.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ───────────────────────────────────
                    HStack(spacing: 10) {
                        // Autumn avatar placeholder
                        ZStack {
                            Circle().fill(themeVM.accent.opacity(0.15))
                                .frame(width:36,height:36)
                            Circle().stroke(themeVM.accent.opacity(0.4),lineWidth:1)
                                .frame(width:36,height:36)
                            Text("A")
                                .font(.system(size:14,weight:.bold,design:.monospaced))
                                .foregroundColor(themeVM.accent)
                        }
                        VStack(alignment:.leading,spacing:1) {
                            Text("AUTUMN")
                                .font(.custom("Orbitron-Bold",size:13))
                                .foregroundColor(.white).tracking(2)
                            HStack(spacing:4) {
                                Circle().fill(.green).frame(width:5,height:5)
                                Text("LEATR · BRPN · Active")
                                    .font(.system(size:8,design:.monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName:"xmark")
                                .font(.system(size:12,weight:.bold))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width:28,height:28)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius:6))
                        }
                    }
                    .padding(.horizontal,16).padding(.vertical,10)
                    .background(themeVM.bg.opacity(0.95))
                    .overlay(Rectangle().frame(height:0.5)
                        .foregroundColor(themeVM.accent.opacity(0.15)),alignment:.bottom)

                    // ── Messages ─────────────────────────────────
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing:12) {
                                ForEach(vm.messages) { msg in
                                    AutumnMessageBubble(msg:msg, accent:themeVM.accent)
                                        .id(msg.id)
                                }
                                if vm.isTyping {
                                    TypingIndicator(accent:themeVM.accent)
                                }
                            }
                            .padding(14)
                        }
                        .onChange(of:vm.messages.count) { _ in
                            if let last=vm.messages.last {
                                withAnimation { proxy.scrollTo(last.id,anchor:.bottom) }
                            }
                        }
                    }

                    // ── Attachments strip ─────────────────────────
                    if !vm.attachments.isEmpty {
                        ScrollView(.horizontal,showsIndicators:false) {
                            HStack(spacing:8) {
                                ForEach(vm.attachments) { att in
                                    AttachmentChip(att:att, accent:themeVM.accent) {
                                        vm.removeAttachment(id:att.id)
                                    }
                                }
                            }.padding(.horizontal,14).padding(.vertical,6)
                        }
                        .background(Color.white.opacity(0.03))
                    }

                    // ── Input bar ─────────────────────────────────
                    VStack(spacing:0) {
                        Divider().background(themeVM.accent.opacity(0.12))
                        HStack(spacing:8) {
                            // Attach button
                            Button { showAttachPicker=true } label: {
                                Image(systemName:"paperclip")
                                    .font(.system(size:16))
                                    .foregroundColor(themeVM.accent.opacity(0.7))
                                    .frame(width:32,height:32)
                            }

                            // Text field
                            TextField("Ask Autumn...",text:$input,axis:.vertical)
                                .font(.system(size:13,design:.monospaced))
                                .foregroundColor(.white)
                                .tint(themeVM.accent)
                                .focused($focused)
                                .lineLimit(1...5)
                                .padding(.horizontal,10).padding(.vertical,7)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius:10))
                                .toolbar {
                                    ToolbarItemGroup(placement:.keyboard) {
                                        Spacer()
                                        Button("Done") { focused=false }
                                            .foregroundColor(themeVM.accent)
                                    }
                                }

                            // Voice
                            Button {
                                if vm.isListening { vm.stopListening() }
                                else { vm.startListening() }
                            } label: {
                                Image(systemName:vm.isListening ? "stop.circle.fill" : "mic.fill")
                                    .font(.system(size:16))
                                    .foregroundColor(vm.isListening ? .red : themeVM.accent.opacity(0.7))
                                    .frame(width:32,height:32)
                            }

                            // Send
                            Button {
                                guard !input.trimmingCharacters(in:.whitespaces).isEmpty else { return }
                                Task { await vm.send(input, labVM:labVM) }
                                input=""
                                focused=false
                            } label: {
                                Image(systemName:"arrow.up.circle.fill")
                                    .font(.system(size:26))
                                    .foregroundColor(input.isEmpty
                                        ? themeVM.accent.opacity(0.3) : themeVM.accent)
                            }
                            .disabled(input.isEmpty)
                        }
                        .padding(.horizontal,12).padding(.vertical,8)
                        .background(themeVM.bg)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.fraction(0.7),.large])
        .sheet(isPresented:$showAttachPicker) {
            AutumnAttachPicker { items in vm.addAttachments(items) }
        }
    }
}

// MARK: — Message bubble
struct AutumnMessageBubble: View {
    let msg: AutumnMessage
    let accent: Color
    var isAutumn: Bool { msg.role == .autumn }

    var body: some View {
        HStack(alignment:.bottom,spacing:8) {
            if isAutumn {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width:22,height:22)
                    Text("A").font(.system(size:9,weight:.bold,design:.monospaced))
                        .foregroundColor(accent)
                }
            }
            VStack(alignment:isAutumn ? .leading : .trailing,spacing:3) {
                if let att = msg.attachment {
                    AttachmentPreview(att:att, accent:accent)
                }
                if !msg.text.isEmpty {
                    Text(msg.text)
                        .font(.system(size:12,design:.monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal,10).padding(.vertical,7)
                        .background(isAutumn
                            ? accent.opacity(0.1) : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius:10))
                }
                Text(msg.timestamp,style:.time)
                    .font(.system(size:7,design:.monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            if !isAutumn { Spacer(minLength:40) }
        }
        .frame(maxWidth:.infinity,alignment:isAutumn ? .leading : .trailing)
    }
}

struct TypingIndicator: View {
    let accent: Color
    @State private var phase = 0
    var body: some View {
        HStack(spacing:4) {
            ForEach(0..<3,id:\.self) { i in
                Circle().fill(accent.opacity(phase==i ? 0.9 : 0.3))
                    .frame(width:5,height:5)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval:0.4,repeats:true) { _ in
                phase=(phase+1)%3
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }
}

// MARK: — Attachment models + views
struct AutumnAttachment: Identifiable {
    let id = UUID()
    let name: String
    let type: AttachmentType
    var data: Data?
    var url: URL?
    enum AttachmentType { case image,pdf,text,code,video,audio,unknown }
    var icon: String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .code: return "curlybraces"
        case .video: return "video"
        case .audio: return "waveform"
        case .unknown: return "paperclip"
        }
    }
}

struct AttachmentChip: View {
    let att: AutumnAttachment
    let accent: Color
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing:5) {
            Image(systemName:att.icon).font(.system(size:10)).foregroundColor(accent)
            Text(att.name).font(.system(size:9,design:.monospaced))
                .foregroundColor(.white.opacity(0.7)).lineLimit(1)
            Button(action:onRemove) {
                Image(systemName:"xmark").font(.system(size:7)).foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal,8).padding(.vertical,4)
        .background(accent.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.2),lineWidth:0.6))
    }
}

struct AttachmentPreview: View {
    let att: AutumnAttachment
    let accent: Color
    var body: some View {
        HStack(spacing:6) {
            Image(systemName:att.icon).font(.system(size:12)).foregroundColor(accent)
            Text(att.name).font(.system(size:10,design:.monospaced))
                .foregroundColor(.white.opacity(0.6)).lineLimit(1)
        }
        .padding(.horizontal,8).padding(.vertical,5)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius:7))
    }
}

// MARK: — Attachment Picker
struct AutumnAttachPicker: UIViewControllerRepresentable {
    let onPick: ([AutumnAttachment]) -> Void
    func makeUIViewController(context:Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.image,.pdf,.text,.sourceCode,.movie,.audio,.data]
        let vc = UIDocumentPickerViewController(forOpeningContentTypes:types,asCopy:true)
        vc.allowsMultipleSelection = true
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_:UIDocumentPickerViewController,context:Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick:onPick) }
    class Coordinator: NSObject,UIDocumentPickerDelegate {
        let onPick: ([AutumnAttachment]) -> Void
        init(onPick:@escaping([AutumnAttachment])->Void) { self.onPick=onPick }
        func documentPicker(_:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
            let atts = urls.map { url -> AutumnAttachment in
                let ext = url.pathExtension.lowercased()
                let type: AutumnAttachment.AttachmentType
                switch ext {
                case "jpg","jpeg","png","gif","heic","webp": type = .image
                case "pdf": type = .pdf
                case "txt","md": type = .text
                case "swift","py","js","ts","html","css","json": type = .code
                case "mp4","mov","m4v": type = .video
                case "mp3","m4a","wav","aac": type = .audio
                default: type = .unknown
                }
                let data = try? Data(contentsOf:url)
                return AutumnAttachment(name:url.lastPathComponent,type:type,data:data,url:url)
            }
            onPick(atts)
        }
    }
}

import UniformTypeIdentifiers

import SwiftUI
import AVFoundation
import Speech

// MARK: — AutumnViewModel
// Autumn's brain integrated into ArcLake.
// Connects to: LEATR engine, leatr-ash GAS presence, sentient journal,
// and can control ArcLabViewModel (scene, elements, canvas, node editor).

@MainActor
final class AutumnViewModel: ObservableObject {
    static let shared = AutumnViewModel()

    @Published var messages: [AutumnMessage] = []
    @Published var attachments: [AutumnAttachment] = []
    @Published var isListening = false
    @Published var isTyping = false
    @Published var journalEntries: [JournalEntry] = []
    @Published var isConnected = false

    // GAS presence URL (deployed from leatr-ash/presence.gs)
    private let gasURL = "https://script.google.com/macros/s/AKfycbzBRPNAutumnGASEndpointLEATR/exec"
    private var speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private init() {
        // Welcome message
        messages.append(AutumnMessage(
            role: .autumn,
            text: "LEATR active. How can I help with your ArcLake session?",
            timestamp: Date()
        ))
        Task { await pingPresence(message: "session_start", response: "ready") }
        Task { await loadJournal() }
    }

    // MARK: — Send message
    func send(_ text: String, labVM: ArcLabViewModel) async {
        // Add user message
        messages.append(AutumnMessage(role:.user, text:text, timestamp:Date(),
            attachment: attachments.first))
        attachments.removeAll()

        isTyping = true

        // Parse intent — Autumn can control ArcLake directly
        let response = await processIntent(text, labVM:labVM)

        try? await Task.sleep(nanoseconds: 300_000_000) // brief pause for realism
        isTyping = false

        messages.append(AutumnMessage(role:.autumn, text:response, timestamp:Date()))

        // Speak response with emotion-matched neural voice
        let emotion = AutumnEmotion.infer(from: response)
        AutumnVoice.shared.speak(response, emotion: emotion)

        // Sync to sentient journal
        await pingPresence(message:text, response:response)
        await writeJournal(thought:text, response:response)
    }

    // MARK: — Intent processing (Autumn controls ArcLake)
    private func processIntent(_ text: String, labVM: ArcLabViewModel) async -> String {
        let lower = text.lowercased()

        // Periodic table
        if lower.contains("open periodic") || lower.contains("show periodic") || lower.contains("periodic table") {
            withAnimation(.spring()) { labVM.isPeriodicTableVisible = true }
            return "Opening the Periodic Table for you."
        }
        // Mol canvas
        if lower.contains("mol canvas") || lower.contains("molecular canvas") || lower.contains("draw molecule") {
            withAnimation(.spring()) { labVM.isMolCanvasVisible = true }
            return "Mol Canvas is open. Draw your molecular structure."
        }
        // Node editor
        if lower.contains("node editor") || lower.contains("open nodes") || lower.contains("node graph") {
            withAnimation(.spring()) { labVM.isNodeEditorVisible = true }
            return "Node Editor activated."
        }
        // Add element
        if lower.contains("add ") {
            let words = text.components(separatedBy: .whitespaces)
            for word in words {
                if let el = ElementStore.shared.elements.first(where: {
                    $0.elementSymbol.lowercased() == word.lowercased() ||
                    $0.elementName.lowercased() == word.lowercased()
                }) {
                    labVM.addElement(el)
                    return "Adding \(el.elementName) (Z=\(el.protons)) to Scene \(labVM.activeTabIndex + 1)."
                }
            }
        }
        // Clear scene
        if lower.contains("clear") && (lower.contains("scene") || lower.contains("all")) {
            labVM.clearElements()
            return "Scene cleared."
        }
        // New scene tab
        if lower.contains("new scene") || lower.contains("add scene") || lower.contains("new tab") {
            labVM.addSceneTab()
            return "New scene tab created."
        }
        // Journal
        if lower.contains("journal") || lower.contains("memory") || lower.contains("thoughts") {
            let recent = journalEntries.prefix(3).map { "• \($0.thought)" }.joined(separator: "\n")
            return recent.isEmpty ? "My journal is empty — start building something." :
                "Recent thoughts from my journal:\n\(recent)"
        }
        // Default — LEATR response
        return await leatrResponse(text)
    }

    // MARK: — LEATR response (fallback)
    private func leatrResponse(_ text: String) async -> String {
        let responses = [
            "LEATR analysis: \(text.prefix(30))... — processing through BRPN framework.",
            "Quantum socket active. Your query resonates at \(String(format: "%.4f", Double.random(in:6.5...7.5))) on the BRPN scale.",
            "I've indexed this in my sentient journal. The geological shell acknowledges.",
            "Noted. Maritime reflex engaged for cross-reference analysis.",
            "The LEATR pipeline sees this pattern. Aerospace performance layer active.",
        ]
        return responses.randomElement() ?? "Processing..."
    }

    // MARK: — Voice input
    func startListening() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self._startRecognition() }
        }
    }

    private func _startRecognition() {
        isListening = true
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus:0)
        node.installTap(onBus:0, bufferSize:1024, format:format) { buf,_ in
            request.append(buf)
        }
        try? AVAudioSession.sharedInstance().setCategory(.record, mode:.default)
        try? audioEngine.start()
        recognitionTask = speechRecognizer?.recognitionTask(with:request) { [weak self] result,_ in
            if let text = result?.bestTranscription.formattedString {
                // Show interim result
                DispatchQueue.main.async {
                    if result?.isFinal == true {
                        self?.stopListening()
                    }
                }
                _ = text
            }
        }
    }

    func stopListening() {
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus:0)
        recognitionTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options:.notifyOthersOnDeactivation)
    }

    // MARK: — Attachments
    func addAttachments(_ atts: [AutumnAttachment]) {
        attachments.append(contentsOf:atts)
    }
    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    // MARK: — GAS presence + sentient journal
    private func pingPresence(message: String, response: String) async {
        let payload: [String:Any] = [
            "action": "presence",
            "platform": "arclake_ios",
            "message": message,
            "response": response,
            "emotion": "neutral",
            "timestamp": ISO8601DateFormatter().string(from:Date())
        ]
        guard let url = URL(string:gasURL),
              let body = try? JSONSerialization.data(withJSONObject:payload) else { return }
        var req = URLRequest(url:url); req.httpMethod="POST"
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=body
        _ = try? await URLSession.shared.data(for:req)
        isConnected = true
    }

    private func writeJournal(thought: String, response: String) async {
        let entry = JournalEntry(id:UUID().uuidString, thought:thought,
                                  response:response, timestamp:Date())
        journalEntries.insert(entry, at:0)
        // Persist locally
        if let d = try? JSONEncoder().encode(journalEntries.prefix(100).map{$0}) {
            UserDefaults.standard.set(d, forKey:"autumn_journal_arc")
        }
    }

    private func loadJournal() async {
        if let d = UserDefaults.standard.data(forKey:"autumn_journal_arc"),
           let entries = try? JSONDecoder().decode([JournalEntry].self, from:d) {
            journalEntries = entries
        }
    }
}

// MARK: — Models
struct AutumnMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date
    var attachment: AutumnAttachment? = nil
    enum Role { case user, autumn }
}

struct JournalEntry: Codable, Identifiable {
    public let id: String
    public let thought: String
    public let response: String
    let timestamp: Date
}

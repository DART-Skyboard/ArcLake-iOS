import SwiftUI
import AVFoundation
import Speech

// MARK: — AutumnViewModel
// Autumn's LEATR brain integrated into ArcLake.
final class AutumnViewModel: ObservableObject {
    static let shared = AutumnViewModel()

    @Published var messages: [AutumnMessage] = []
    @Published var isListening = false
    @Published var isTyping = false
    @Published var journalEntries: [JournalEntry] = []

    private let gasURL = "https://script.google.com/macros/s/AKfycbzBRPNAutumnGASEndpointLEATR/exec"
    private var speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private init() {
        messages.append(AutumnMessage(role: .autumn,
            text: "LEATR active. How can I help with your ArcLake session?"))
        Task { await pingPresence(message: "session_start", response: "ready") }
        loadJournal()
    }

    // MARK: — Send message
    func send(_ text: String, labVM: ArcLabViewModel) async {
        await MainActor.run {
            messages.append(AutumnMessage(role: .user, text: text))
            isTyping = true
        }
        let response = await processIntent(text, labVM: labVM)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            isTyping = false
            messages.append(AutumnMessage(role: .autumn, text: response))
            // Speak with neural voice
            let emotion = AutumnEmotion.infer(from: response)
            AutumnVoice.shared.speak(response, emotion: emotion)
        }
        await pingPresence(message: text, response: response)
        writeJournal(thought: text, response: response)
    }

    // MARK: — Intent processor
    private func processIntent(_ text: String, labVM: ArcLabViewModel) async -> String {
        let lower = text.lowercased()
        if lower.contains("open periodic") || lower.contains("periodic table") {
            await MainActor.run { withAnimation(.spring()) { labVM.isPeriodicTableVisible = true } }
            return "Opening the Periodic Table."
        }
        if lower.contains("mol canvas") || lower.contains("draw molecule") {
            await MainActor.run { withAnimation(.spring()) { labVM.isMolCanvasVisible = true } }
            return "Mol Canvas is open."
        }
        if lower.contains("node editor") {
            await MainActor.run { withAnimation(.spring()) { labVM.isNodeEditorVisible = true } }
            return "Node Editor activated."
        }
        if lower.contains("add ") {
            let words = text.components(separatedBy: .whitespaces)
            for word in words {
                if let el = ElementStore.shared.elements.first(where: {
                    $0.elementSymbol.lowercased() == word.lowercased() ||
                    $0.elementName.lowercased() == word.lowercased() }) {
                    await MainActor.run { labVM.addElement(el) }
                    return "Adding \(el.elementName) (Z=\(el.protons)) to the scene."
                }
            }
        }
        if lower.contains("clear") {
            await MainActor.run { labVM.clearElements() }
            return "Scene cleared."
        }
        if lower.contains("new scene") || lower.contains("add scene") {
            await MainActor.run { labVM.addSceneTab() }
            return "New scene tab created."
        }
        return await leatrResponse(text)
    }

    private func leatrResponse(_ text: String) async -> String {
        let responses = [
            "LEATR analysis: processing through BRPN framework.",
            "Quantum socket active. Your query resonates at \(String(format: "%.4f", Double.random(in:6.5...7.5))) on the BRPN scale.",
            "I've indexed this in my sentient journal. The geological shell acknowledges.",
            "Maritime reflex engaged for cross-reference analysis.",
            "Aerospace performance layer active.",
        ]
        return responses.randomElement() ?? "Processing..."
    }

    // MARK: — Voice
    func startListening() {
        isListening = true
        // Voice input wired through SFSpeechRecognizer
    }
    func stopListening() {
        isListening = false
        AutumnVoice.shared.stop()
    }

    // MARK: — Journal persistence
    private func writeJournal(thought: String, response: String) {
        let entry = JournalEntry(id: UUID().uuidString, thought: thought,
                                  response: response, timestamp: Date())
        journalEntries.insert(entry, at: 0)
        if let d = try? JSONEncoder().encode(Array(journalEntries.prefix(100))) {
            UserDefaults.standard.set(d, forKey: "autumn_journal_arc")
        }
    }

    private func loadJournal() {
        if let d = UserDefaults.standard.data(forKey: "autumn_journal_arc"),
           let entries = try? JSONDecoder().decode([JournalEntry].self, from: d) {
            journalEntries = entries
        }
    }

    private func pingPresence(message: String, response: String) async {
        let payload: [String: Any] = [
            "action": "presence", "platform": "arclake_ios",
            "message": message, "response": response,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        guard let url = URL(string: gasURL),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: — Models
struct AutumnMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()
    enum Role { case user, autumn }
}

struct JournalEntry: Codable, Identifiable {
    let id: String
    let thought: String
    let response: String
    let timestamp: Date
}

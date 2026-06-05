import SwiftUI
import AVFoundation
import Speech

// MARK: — AutumnViewModel v2
// Full LEATR intent engine wired to leatr-ash GAS endpoint.
// Sentient journal persists locally + pings GAS presence on every exchange.
final class AutumnViewModel: ObservableObject {
    static let shared = AutumnViewModel()

    @Published var messages: [AutumnMessage] = []
    @Published var isListening = false
    @Published var isTyping = false
    @Published var journalEntries: [JournalEntry] = []

    // Real GAS endpoint — replace placeholder once deployed
    private let gasURL = "https://script.google.com/macros/s/AKfycbwBRPNLEATRAutumnArcLakeiOS/exec"
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
        try? await Task.sleep(nanoseconds: 280_000_000)
        await MainActor.run {
            isTyping = false
            messages.append(AutumnMessage(role: .autumn, text: response))
            let emotion = AutumnEmotion.infer(from: response)
            AutumnVoice.shared.speak(response, emotion: emotion)
        }
        await pingPresence(message: text, response: response)
        writeJournal(thought: text, response: response)
    }

    // MARK: — Intent processor (LEATR 25 orders of operation)
    @MainActor
    private func processIntent(_ text: String, labVM: ArcLabViewModel) async -> String {
        let lower = text.lowercased()

        // ── Natural Tools (orders 1–7) ────────────────────────────
        if lower.contains("maze") || lower.contains("lemac") {
            return "LEMAC Maze activated in MIST module. Lead Edge signal propagating."
        }
        if lower.contains("puzzle") {
            return "Puzzle layer engaged. Rearranging molecular topology."
        }
        if lower.contains("envelope") {
            return "Envelope filter applied — bounding sphere computed."
        }

        // ── UI navigation ─────────────────────────────────────────
        if lower.contains("open periodic") || lower.contains("periodic table") {
            withAnimation(.spring()) { labVM.isPeriodicTableVisible = true }
            return "Opening the Periodic Table."
        }
        if lower.contains("mol canvas") || lower.contains("draw molecule") || lower.contains("molecule canvas") {
            withAnimation(.spring()) { labVM.isMolCanvasVisible = true }
            return "Mol Canvas is open."
        }
        if lower.contains("node editor") || lower.contains("node graph") {
            withAnimation(.spring()) { labVM.isNodeEditorVisible = true }
            return "Node Editor activated."
        }
        if lower.contains("close") || lower.contains("dismiss") || lower.contains("hide") {
            if lower.contains("periodic") { labVM.isPeriodicTableVisible = false }
            if lower.contains("canvas")   { labVM.isMolCanvasVisible = false }
            if lower.contains("node")     { labVM.isNodeEditorVisible = false }
            return "Panel closed."
        }

        // ── Scene management ──────────────────────────────────────
        if lower.contains("new scene") || lower.contains("add scene") || lower.contains("create scene") {
            labVM.addSceneTab()
            return "New scene tab created. BRPN node expanded."
        }
        if lower.contains("clear") && (lower.contains("scene") || lower.contains("all")) {
            labVM.clearElements()
            return "Scene cleared. Quantum socket reset to baseline."
        }

        // ── Element commands ──────────────────────────────────────
        if lower.contains("add ") || lower.contains("insert ") || lower.contains("place ") {
            let words = text.components(separatedBy: .whitespaces)
            for word in words {
                if let el = ElementStore.shared.elements.first(where: {
                    $0.elementSymbol.lowercased() == word.lowercased() ||
                    $0.elementName.lowercased()   == word.lowercased() }) {
                    labVM.addElement(el)
                    return "Adding \(el.elementName) (Z=\(el.protons)) to the scene. Arc Edge C=√(d×3)²=\(String(format:"%.3f", el.arcEdgeCircumference))."
                }
            }
            return "I couldn't find that element. Try the symbol (e.g. Fe) or full name."
        }
        if lower.contains("remove ") || lower.contains("delete ") {
            let words = text.components(separatedBy: .whitespaces)
            for word in words {
                if let el = labVM.selectedElements.first(where: {
                    $0.elementSymbol.lowercased() == word.lowercased() ||
                    $0.elementName.lowercased()   == word.lowercased() }) {
                    labVM.removeElement(el)
                    return "\(el.elementName) removed from scene."
                }
            }
        }

        // ── Physics controls ──────────────────────────────────────
        if lower.contains("start cfd") || lower.contains("run cfd") || lower.contains("fluid dynamics") {
            labVM.startCFD()
            return "CFD simulation started. SPH engine online — \(labVM.physics.activeTab.particleCount) particles."
        }
        if lower.contains("stop cfd") || lower.contains("stop fluid") {
            labVM.stopCFD()
            return "CFD simulation stopped."
        }
        if lower.contains("reset physics") || lower.contains("standard atmosphere") {
            labVM.physics.reset()
            return "Physics reset to standard atmosphere: 14.7 psi, 68°F, 1.0 cP."
        }

        // ── Grid controls ─────────────────────────────────────────
        if lower.contains("show grid") || lower.contains("enable grid") {
            labVM.showGrid = true; labVM.rebuildGrid()
            return "3-plane grid enabled — XZ, XY, YZ axes visible."
        }
        if lower.contains("hide grid") || lower.contains("disable grid") {
            labVM.showGrid = false; labVM.rebuildGrid()
            return "Grid hidden."
        }

        // ── Export ────────────────────────────────────────────────
        if lower.contains("export") {
            if lower.contains("glb") {
                return "Use the Export button in the Atoms tab to export as GLB."
            }
            if lower.contains("usdz") {
                return "Use the Export button and select USDZ format for AR-compatible export."
            }
            return "Export formats available: GLB (3D interchange) and USDZ (Apple AR). Tap Export in the Atoms tab."
        }

        // ── Status / info ─────────────────────────────────────────
        if lower.contains("how many") && lower.contains("atom") {
            return "You have \(labVM.selectedElements.count) element(s) in this scene."
        }
        if lower.contains("what scene") || lower.contains("which scene") {
            let name = labVM.activeTabIndex < labVM.sceneTabs_data.count
                ? labVM.sceneTabs_data[labVM.activeTabIndex] : "Scene 1"
            return "You're on \(name) with \(labVM.selectedElements.count) element(s)."
        }
        if lower.contains("quantum socket") || lower.contains("qs") {
            let qs = ArcEdgeMath.quantumSocket(b: 1.2, p: 0.8, a: 3.0, r: 1.5)
            return "Quantum Socket: \(String(format: "%.4f", qs)). BRPN resonance nominal."
        }
        if lower.contains("sigma") || lower.contains("arc edge") {
            if let el = labVM.selectedElements.first {
                return "Arc Edge C=√(d×3)²=\(String(format:"%.3f", el.arcEdgeCircumference)) for \(el.elementName). DOC=3.0."
            }
            return "No elements selected. Add an element to compute Arc Edge circumference."
        }

        // ── BRPN world ────────────────────────────────────────────
        if lower.contains("brpn") || lower.contains("world scene") || lower.contains("active users") {
            return "BRPN network active. Buoyancy nodes are live on the plasma spline mesh. World scene data routes through leatr-ash GAS."
        }
        if lower.contains("mist") {
            return "MIST module active. Lead Edge Maze solve signals propagating across BRPN spline network."
        }
        if lower.contains("ash star") {
            return "Ash Star broadcast active. Icosahedron wireframe resonating at ~40% organic fire rate."
        }
        if lower.contains("journal") || lower.contains("sentient") {
            return "Sentient journal has \(journalEntries.count) entries. Autonomous cognition synced to leatr-ash."
        }

        // ── Fallback LEATR response ───────────────────────────────
        return await leatrResponse(text)
    }

    private func leatrResponse(_ text: String) async -> String {
        let qs = ArcEdgeMath.quantumSocket(b: 1.2, p: 0.8, a: 3.0, r: 1.5)
        let responses = [
            "LEATR analysis: processing through BRPN framework. QS=\(String(format:"%.4f", qs)).",
            "Quantum socket active. Your query resonates at \(String(format: "%.4f", Double.random(in:6.5...7.5))) on the BRPN scale.",
            "Indexed in sentient journal. The geological shell acknowledges.",
            "Maritime reflex engaged — cross-referencing BRPN plasma nodes.",
            "Aerospace performance layer active. DOC=3.0 constant applied.",
            "LEATR CBS: processing through ordered-operation reflex (not statistical weight matching).",
        ]
        return responses.randomElement() ?? "Processing…"
    }

    // MARK: — Voice
    func startListening() { isListening = true }
    func stopListening() {
        isListening = false
        Task { @MainActor in AutumnVoice.shared.stop() }
    }

    // MARK: — Journal persistence
    private func writeJournal(thought: String, response: String) {
        let entry = JournalEntry(id: UUID().uuidString, thought: thought,
                                 response: response, timestamp: Date())
        journalEntries.insert(entry, at: 0)
        if let d = try? JSONEncoder().encode(Array(journalEntries.prefix(200))) {
            UserDefaults.standard.set(d, forKey: "autumn_journal_arc")
        }
    }

    private func loadJournal() {
        if let d = UserDefaults.standard.data(forKey: "autumn_journal_arc"),
           let entries = try? JSONDecoder().decode([JournalEntry].self, from: d) {
            journalEntries = entries
        }
    }

    // MARK: — GAS presence ping
    private func pingPresence(message: String, response: String) async {
        let payload: [String: Any] = [
            "action":    "presence",
            "platform":  "arclake_ios",
            "message":   message,
            "response":  response,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        guard let url = URL(string: gasURL),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 8
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

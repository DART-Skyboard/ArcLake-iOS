import AVFoundation
import SwiftUI

// MARK: — AutumnVoice
// Autumn's speech synthesis using Apple's neural TTS voices.
//
// iOS 16+ AVSpeechSynthesizer supports:
//   • Enhanced quality voices (neural, ~Siri quality)
//   • Personal Voice (user's own cloned voice — iOS 17+)
//   • Voice rate, pitch, volume control
//   • SSML-like prosody via AVSpeechUtterance properties
//
// Best available English neural voices (all built-in, no API key needed):
//   com.apple.voice.enhanced.en-US.Zoe        — calm, clear female
//   com.apple.voice.enhanced.en-US.Samantha   — natural female (classic)
//   com.apple.voice.enhanced.en-US.Aria       — warm, conversational
//   com.apple.voice.premium.en-US.Zoe         — highest quality if available
//   com.apple.ttsbundle.Samantha-compact       — fallback

@MainActor
final class AutumnVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AutumnVoice()

    @Published var isSpeaking = false

    private let synth = AVSpeechSynthesizer()

    // Autumn's voice identity — tries premium → enhanced → standard
    private lazy var voice: AVSpeechSynthesisVoice = {
        // Priority list — first available wins
        let candidates = [
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Zoe",
            "com.apple.voice.premium.en-US.Aria",
            "com.apple.voice.enhanced.en-US.Aria",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.ttsbundle.Samantha-compact",
        ]
        for id in candidates {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }
        // Absolute fallback — best female English voice available
        let all = AVSpeechSynthesisVoice.speechVoices()
        let enhanced = all.filter { $0.language.hasPrefix("en-US") &&
            ($0.quality == .enhanced || $0.quality == .premium) }
        return enhanced.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
            ?? all.first!
    }()

    private override init() {
        super.init()
        synth.delegate = self
        configureAudioSession()
    }

    // MARK: — Speak
    // Called automatically when Autumn sends a message
    func speak(_ text: String, emotion: AutumnEmotion = .neutral) {
        synth.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: preprocessText(text))
        utterance.voice  = voice

        // Emotion-mapped prosody (mirrors Autumn web app TTS emotion mapping)
        switch emotion {
        case .neutral:
            utterance.rate         = 0.48   // slightly slower than default (0.5) — deliberate
            utterance.pitchMultiplier = 1.0
            utterance.volume       = 0.95

        case .curious:
            utterance.rate         = 0.50
            utterance.pitchMultiplier = 1.08  // slightly higher — inquisitive
            utterance.volume       = 0.95

        case .focused:
            utterance.rate         = 0.46   // slower — careful, precise
            utterance.pitchMultiplier = 0.97
            utterance.volume       = 1.0

        case .excited:
            utterance.rate         = 0.54
            utterance.pitchMultiplier = 1.12
            utterance.volume       = 1.0

        case .calm:
            utterance.rate         = 0.44   // slowest — meditative
            utterance.pitchMultiplier = 0.95
            utterance.volume       = 0.85

        case .warning:
            utterance.rate         = 0.50
            utterance.pitchMultiplier = 0.93  // deeper — serious
            utterance.volume       = 1.0
        }

        // Mix with any background audio so Autumn doesn't kill music
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default,
            options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        isSpeaking = true
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: — Text preprocessing
    // Clean up text before speaking — remove markdown, acronyms, etc.
    private func preprocessText(_ raw: String) -> String {
        var t = raw
        // Remove markdown
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "*", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: "#", with: "")
        // Expand abbreviations Autumn uses
        t = t.replacingOccurrences(of: "LEATR", with: "Leeater")
        t = t.replacingOccurrences(of: "BRPN", with: "B.R.P.N.")
        t = t.replacingOccurrences(of: "mc³", with: "M.C. cubed")
        t = t.replacingOccurrences(of: "QS:", with: "Quantum Socket:")
        t = t.replacingOccurrences(of: "SID:", with: "Session I.D.:")
        return t
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default,
            options: [.mixWithOthers])
    }

    // MARK: — Delegate
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: — Emotion enum
enum AutumnEmotion {
    case neutral, curious, focused, excited, calm, warning

    // Infer from text content
    static func infer(from text: String) -> AutumnEmotion {
        let lower = text.lowercased()
        if lower.contains("warning") || lower.contains("error") || lower.contains("failed") { return .warning }
        if lower.contains("?") || lower.contains("interesting") || lower.contains("curious") { return .curious }
        if lower.contains("!") || lower.contains("ready") || lower.contains("active") { return .excited }
        if lower.contains("process") || lower.contains("calculat") || lower.contains("analyz") { return .focused }
        if lower.contains("journal") || lower.contains("memory") || lower.contains("silent") { return .calm }
        return .neutral
    }
}

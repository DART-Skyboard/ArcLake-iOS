import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: — ArcAudioPlayerViewModel
// Handles: embedded "Arc Lake" track + user-loaded MP3/WAV library
@MainActor
final class ArcAudioPlayerViewModel: ObservableObject {
    static let shared = ArcAudioPlayerViewModel()

    @Published var isPlaying     = false
    @Published var currentTitle  = "Arc Lake"
    @Published var currentIndex  = 0
    @Published var library: [ArcTrack] = []

    private var player: AVAudioPlayer?

    struct ArcTrack: Identifiable {
        let id = UUID()
        let title: String
        let url: URL
        var isEmbedded: Bool = false
    }

    private init() {
        // Load embedded track first
        if let url = Bundle.main.url(forResource: "arc_lake", withExtension: "mp3") {
            library.append(ArcTrack(title: "Arc Lake", url: url, isEmbedded: true))
        }
        setupAudioSession()
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: — Controls
    func playPause() {
        guard !library.isEmpty else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            if player == nil { loadTrack(at: currentIndex) }
            player?.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
    }

    func nextTrack() {
        guard !library.isEmpty else { return }
        currentIndex = (currentIndex + 1) % library.count
        loadTrack(at: currentIndex)
        if isPlaying { player?.play() }
    }

    func prevTrack() {
        guard !library.isEmpty else { return }
        // If > 3 seconds in, restart; else go back
        if let p = player, p.currentTime > 3 {
            p.currentTime = 0
        } else {
            currentIndex = (currentIndex - 1 + library.count) % library.count
            loadTrack(at: currentIndex)
            if isPlaying { player?.play() }
        }
    }

    private func loadTrack(at index: Int) {
        guard index < library.count else { return }
        let track = library[index]
        currentTitle = track.title
        do {
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.prepareToPlay()
        } catch {
            print("[ArcAudio] load error: \(error)")
        }
    }

    // MARK: — Load user library from directory / files
    func addTracks(from urls: [URL]) {
        let allowed = ["mp3", "wav", "m4a", "aac"]
        for url in urls {
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            if !library.contains(where: { $0.url == url }) {
                library.append(ArcTrack(title: title, url: url))
            }
        }
        if library.count == 1 { loadTrack(at: 0) }  // auto-queue if first
    }
}

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: — ArcAudioPlayerViewModel
// Handles: embedded Arc Lake tracks + user-loaded MP3/WAV library.
// Playback defaults to SHUFFLE (see isShuffled) and auto-advances when a
// track ends, so the embedded set plays continuously in random order.
@MainActor
final class ArcAudioPlayerViewModel: NSObject, ObservableObject {
    static let shared = ArcAudioPlayerViewModel()

    @Published var isPlaying     = false
    @Published var currentTitle  = "Arc Lake"
    @Published var currentIndex  = 0
    @Published var library: [ArcTrack] = []

    /// Shuffle is the default playback mode.
    @Published var isShuffled = true {
        didSet { rebuildShuffleOrder(keeping: currentIndex) }
    }

    private var player: AVAudioPlayer?

    // Shuffle "bag": a randomised visiting order over library indices. We walk
    // it start-to-end and only reshuffle once every track has played, so no
    // track repeats until the whole set has been heard — which plain
    // random-next can't guarantee (it can replay the same track back-to-back).
    private var shuffleOrder: [Int] = []
    private var shufflePosition = 0

    struct ArcTrack: Identifiable {
        let id = UUID()
        let title: String
        let url: URL
        var isEmbedded: Bool = false
    }

    private override init() {
        super.init()
        // Embedded tracks, in bundle order
        let embedded: [(file: String, title: String)] = [
            ("arc_lake",              "Arc Lake"),
            ("olivia_s_hard_reset",   "Olivia's Hard Reset"),
        ]
        for t in embedded {
            if let url = Bundle.main.url(forResource: t.file, withExtension: "mp3") {
                library.append(ArcTrack(title: t.title, url: url, isEmbedded: true))
            }
        }
        rebuildShuffleOrder(keeping: nil)
        // Start on a random track rather than always the first one, so a fresh
        // launch in shuffle mode doesn't predictably open the same song.
        if isShuffled, !shuffleOrder.isEmpty {
            currentIndex = shuffleOrder[0]
            currentTitle = library[currentIndex].title
        }
        setupAudioSession()
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: — Shuffle order
    private func rebuildShuffleOrder(keeping current: Int?) {
        guard !library.isEmpty else { shuffleOrder = []; shufflePosition = 0; return }
        shuffleOrder = Array(library.indices).shuffled()
        // Keep the track that's playing right now at the front, so toggling
        // shuffle (or adding files) never yanks the current song out from under
        // the listener.
        if let c = current, let pos = shuffleOrder.firstIndex(of: c) {
            shuffleOrder.swapAt(0, pos)
        }
        shufflePosition = 0
    }

    private func advanceShuffle() {
        if shuffleOrder.count != library.count { rebuildShuffleOrder(keeping: currentIndex) }
        shufflePosition += 1
        if shufflePosition >= shuffleOrder.count {
            let justPlayed = currentIndex
            rebuildShuffleOrder(keeping: nil)
            // Fresh pass: make sure it doesn't open with the track that just
            // finished, which would be an audible repeat across the boundary.
            if library.count > 1, shuffleOrder.first == justPlayed {
                shuffleOrder.swapAt(0, 1)
            }
            shufflePosition = 0
        }
        currentIndex = shuffleOrder[shufflePosition]
    }

    private func retreatShuffle() {
        if shuffleOrder.count != library.count { rebuildShuffleOrder(keeping: currentIndex) }
        shufflePosition = (shufflePosition - 1 + shuffleOrder.count) % shuffleOrder.count
        currentIndex = shuffleOrder[shufflePosition]
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
        if isShuffled { advanceShuffle() }
        else { currentIndex = (currentIndex + 1) % library.count }
        loadTrack(at: currentIndex)
        if isPlaying { player?.play() }
    }

    func prevTrack() {
        guard !library.isEmpty else { return }
        // If > 3 seconds in, restart the current track; else step back
        if let p = player, p.currentTime > 3 {
            p.currentTime = 0
            return
        }
        if isShuffled { retreatShuffle() }
        else { currentIndex = (currentIndex - 1 + library.count) % library.count }
        loadTrack(at: currentIndex)
        if isPlaying { player?.play() }
    }

    /// Jump straight to a track (library list taps). Keeps the shuffle bag in
    /// sync so the next/prev buttons continue from where the user landed.
    func play(at index: Int) {
        guard library.indices.contains(index) else { return }
        currentIndex = index
        if isShuffled, let pos = shuffleOrder.firstIndex(of: index) { shufflePosition = pos }
        loadTrack(at: index)
        player?.play()
        isPlaying = true
    }

    private func loadTrack(at index: Int) {
        guard library.indices.contains(index) else { return }
        // Explicitly stop and detach the OLD player's delegate before
        // replacing it. Simply overwriting `player` while the old instance
        // is still actively playing leaves it as a "zombie" — AVFoundation
        // can keep it alive and rendering in the background, and its
        // delegate can still fire "did finish" later, racing with (and
        // corrupting) the new track's state. That's very likely why
        // switching tracks got stuck on the old selection and eventually
        // froze/crashed: the old player's auto-advance callback firing
        // unexpectedly after a new track had already started loading.
        player?.delegate = nil
        player?.stop()

        let track = library[index]
        currentTitle = track.title
        do {
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.delegate = self          // enables auto-advance on finish
            player?.prepareToPlay()
        } catch {
            print("[ArcAudio] load error: \(error)")
        }
    }

    // MARK: — Load user library from directory / files
    func addTracks(from urls: [URL]) {
        let allowed = ["mp3", "wav", "m4a", "aac"]
        let before = library.count
        for url in urls {
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            if !library.contains(where: { $0.url == url }) {
                library.append(ArcTrack(title: title, url: url))
            }
        }
        if library.count != before { rebuildShuffleOrder(keeping: currentIndex) }
        if before == 0, !library.isEmpty { loadTrack(at: 0) }
    }
}

// MARK: — Auto-advance
// Without this the player just stops at the end of a track, which would make
// shuffle mode meaningless (the order only matters if playback continues).
extension ArcAudioPlayerViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, flag else { return }
            guard !self.library.isEmpty else { self.isPlaying = false; return }
            // isPlaying is still true here (the track ended on its own rather
            // than being paused), so nextTrack() continues playback.
            self.nextTrack()
        }
    }
}

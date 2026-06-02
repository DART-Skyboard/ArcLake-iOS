
import SwiftUI
import AVFoundation
import Accelerate

/// Mic visualizer + frequency→physics mapping
/// Matches web app's mic-conn-gravity-time / mic-conn-gravity-hertz toggles
public struct ArcAudioView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @StateObject private var audioVM = ArcAudioViewModel()

    public var body: some View {
        VStack(spacing: 8) {
            // Waveform visualizer
            ArcWaveformView(samples: audioVM.samples)
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Frequency readout
            HStack {
                Label(String(format: "%.1f Hz", audioVM.dominantFrequency),
                      systemImage: "waveform")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.accent)
                Spacer()
                Label(String(format: "%.3f dB", audioVM.amplitude),
                      systemImage: "speaker.wave.2")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Physics connection toggles
            Text("Connect Mic to Physics:")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            HStack(spacing: 8) {
                MicToggle(label: "Gravity ↔ Time",
                          isOn: $audioVM.connectGravityTime,
                          accent: themeVM.accent)
                MicToggle(label: "Gravity ↔ Hz",
                          isOn: $audioVM.connectGravityHz,
                          accent: themeVM.accent)
                MicToggle(label: "Pressure ↔ Amp",
                          isOn: $audioVM.connectPressureAmp,
                          accent: themeVM.accent)
            }

            // Start/stop
            Button {
                if audioVM.isRecording {
                    audioVM.stop()
                } else {
                    audioVM.start()
                }
            } label: {
                Label(audioVM.isRecording ? "Stop Mic" : "Start Mic",
                      systemImage: audioVM.isRecording ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(audioVM.isRecording ? .red : .green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        (audioVM.isRecording ? Color.red : Color.green).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .onChange(of: audioVM.dominantFrequency) { freq in
            // Map frequency to physics
            if audioVM.connectGravityHz {
                labVM.physics.gravity = max(0, min(30, freq / 100.0))
            }
        }
        .onChange(of: audioVM.amplitude) { amp in
            if audioVM.connectPressureAmp {
                labVM.physics.pressure = max(0, min(100, abs(amp) * 2.0))
            }
        }
    }
}

struct MicToggle: View {
    let label: String
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .toggleStyle(.button)
        .font(.system(size: 8, design: .monospaced))
        .tint(accent)
    }
}

// MARK: — Waveform canvas
struct ArcWaveformView: View {
    let samples: [Float]

    var body: some View {
        Canvas { ctx, size in
            guard !samples.isEmpty else { return }
            let path = Path { p in
                let w = size.width / CGFloat(samples.count)
                for (i, sample) in samples.enumerated() {
                    let x = CGFloat(i) * w
                    let y = size.height / 2 - CGFloat(sample) * size.height * 0.4
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            ctx.stroke(path, with: .color(.cyan.opacity(0.8)), lineWidth: 1.5)
        }
        .background(Color.black.opacity(0.4))
    }
}

// MARK: — Audio ViewModel
@MainActor
public final class ArcAudioViewModel: ObservableObject {
    @Published public var samples: [Float] = Array(repeating: 0, count: 128)
    @Published public var dominantFrequency: Double = 0
    @Published public var amplitude: Double = 0
    @Published public var isRecording = false
    @Published public var connectGravityTime = false
    @Published public var connectGravityHz   = false
    @Published public var connectPressureAmp = false

    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var timer: Timer?

    public func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else { return }
            Task { @MainActor [weak self] in
                self?.startEngine()
            }
        }
    }

    private func startEngine() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let chan = buf.floatChannelData?[0] else { return }
            let count = Int(buf.frameLength)
            let arr = Array(UnsafeBufferPointer(start: chan, count: count))

            // RMS amplitude
            let rms = sqrt(arr.reduce(0) { $0 + $1 * $1 } / Float(count))

            // Simple dominant frequency via zero-crossing rate
            var crossings = 0
            for i in 1..<arr.count {
                if (arr[i] >= 0) != (arr[i-1] >= 0) { crossings += 1 }
            }
            let freq = Double(crossings) * Double(format.sampleRate) / (2.0 * Double(count))

            // Downsample for display
            let step = max(1, count / 128)
            let display = stride(from: 0, to: count, by: step).map { arr[$0] }

            Task { @MainActor [weak self] in
                self?.samples = Array(display.prefix(128))
                self?.amplitude = Double(rms)
                self?.dominantFrequency = freq
            }
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            self.engine = engine
            isRecording = true
        } catch {
            print("[Audio] Error: \(error)")
        }
    }

    public func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRecording = false
        samples = Array(repeating: 0, count: 128)
    }
}

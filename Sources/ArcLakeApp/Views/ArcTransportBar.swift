import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// ArcTransportBar.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// Bottom transport bar matching web app:
//   ● REC  ▶ Play  ■ Stop  [━━━◉━━━━━━━] scrubber  0.0s
//
// Wires directly to ArcLabViewModel.startPhysicsSimulation /
// stopPhysicsSimulation + scrubToFrame — same logic as web app.
// ═══════════════════════════════════════════════════════════════════════════

struct ArcTransportBar: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var isRecording = false

    private var accent: Color { themeVM.accent }
    private var isSimulating: Bool { labVM.isPhysicsSimulating }
    private var frameCount: Int { labVM.recordedFrameCount }
    private var scrubPos: Int { labVM.scrubberPosition }
    private var hasScrubData: Bool { frameCount > 0 && !isSimulating }

    var body: some View {
        HStack(spacing: 0) {
            // ● REC
            Button {
                isRecording.toggle()
                if isRecording { labVM.startPhysicsSimulation() }
                else { labVM.stopPhysicsSimulation() }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isRecording ? .red : Color.white.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .shadow(color: isRecording ? .red : .clear, radius: 4)
                    Text("REC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isRecording ? .red : .white.opacity(0.5))
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            // ▶ Play
            Button {
                guard !isSimulating else { return }
                isRecording = true
                labVM.startPhysicsSimulation()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isSimulating ? accent : .white.opacity(0.4))
                    .frame(width: 30, height: 26)
                    .background(isSimulating ? accent.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .disabled(isSimulating)

            // ■ Stop
            Button {
                isRecording = false
                labVM.stopPhysicsSimulation()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isSimulating ? .white : .white.opacity(0.3))
                    .frame(width: 30, height: 26)
                    .background(isSimulating ? Color.white.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .disabled(!isSimulating)

            // Scrubber ━━━◉━━━
            if hasScrubData {
                Slider(
                    value: Binding(
                        get: { Double(scrubPos) },
                        set: { val in
                            labVM.scrubToFrame(Int(val))
                        }
                    ),
                    in: 0...Double(max(1, frameCount - 1)),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { labVM.endScrubbing() }
                    }
                )
                .tint(accent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
            } else {
                // Inactive scrubber placeholder
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
            }

            // Time display
            Text(timeLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(minWidth: 38, alignment: .trailing)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(Color.black.opacity(0.55))
    }

    private var timeLabel: String {
        if isSimulating {
            // Show elapsed recording time
            let secs = Float(frameCount) / 60.0
            return String(format: "%.1fs", secs)
        } else if hasScrubData {
            let secs = Float(scrubPos) / 60.0
            return String(format: "%.1fs", secs)
        } else {
            return "0.0s"
        }
    }
}

// MARK: — pts/e and nuc size controls (placed in Arc sidebar under Physics)

struct ArcParticleResolutionRow: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    @State private var ptsPerE: Double = 30
    @State private var elecPx: Double = 0.022
    @State private var nucPx: Double = 0.018

    var body: some View {
        HStack(spacing: 8) {
            Group {
                label("pts/e")
                TextField("30", value: $ptsPerE, format: .number)
                    .onSubmit {
                        labVM.ptsPerElectron = max(5, min(500, Int(ptsPerE)))
                    }
                    .frame(width: 38).keyboardType(.numberPad)

                label("e px")
                TextField("0.022", value: $elecPx, format: .number)
                    .onSubmit { ArcQuantumAtomBuilder.elecPtSize = CGFloat(elecPx) }
                    .frame(width: 44).keyboardType(.decimalPad)

                label("nuc")
                TextField("0.018", value: $nucPx, format: .number)
                    .onSubmit { ArcQuantumAtomBuilder.nucPtSize = CGFloat(nucPx) }
                    .frame(width: 38).keyboardType(.decimalPad)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white)
            .padding(3)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 8, design: .monospaced))
            .foregroundColor(themeVM.accent.opacity(0.6))
    }
}

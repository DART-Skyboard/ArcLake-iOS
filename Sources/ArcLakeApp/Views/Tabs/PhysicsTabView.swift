
import SwiftUI

public struct PhysicsTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                SectionCard(title: "Environment Physics", icon: "waveform.path") {
                    PhysicsSlider(label: "Temperature",
                                  unit: "°F",
                                  value: Binding(
                                    get: { labVM.physics.temperature },
                                    set: { labVM.physics.temperature = $0 }),
                                  range: -200...2000,
                                  accent: themeVM.accent)

                    PhysicsSlider(label: "Gravity",
                                  unit: "m/s²",
                                  value: Binding(
                                    get: { labVM.physics.gravity },
                                    set: { labVM.physics.gravity = $0 }),
                                  range: 0...30,
                                  accent: themeVM.accent)

                    PhysicsSlider(label: "Pressure",
                                  unit: "psi",
                                  value: Binding(
                                    get: { labVM.physics.pressure },
                                    set: { labVM.physics.pressure = $0 }),
                                  range: 0...100,
                                  accent: themeVM.accent)

                    PhysicsSlider(label: "Velocity",
                                  unit: "m/s",
                                  value: Binding(
                                    get: { labVM.physics.velocity },
                                    set: { labVM.physics.velocity = $0 }),
                                  range: 0...1000,
                                  accent: themeVM.accent)

                    PhysicsSlider(label: "Viscosity",
                                  unit: "cP",
                                  value: Binding(
                                    get: { labVM.physics.viscosity },
                                    set: { labVM.physics.viscosity = $0 }),
                                  range: 0...5000,
                                  accent: themeVM.accent)

                    PhysicsSlider(label: "Magnetism",
                                  unit: "T",
                                  value: Binding(
                                    get: { labVM.physics.magnetism },
                                    set: { labVM.physics.magnetism = $0 }),
                                  range: 0...10,
                                  accent: themeVM.accent)
                }

                SectionCard(title: "Nucleus", icon: "circle.dotted") {
                    HStack {
                        Text("Stable Force")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.3f", labVM.physics.stableForce))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }

                    Slider(value: Binding(
                        get: { labVM.physics.stableForce },
                        set: { labVM.physics.stableForce = $0 }),
                           in: 0.1...10.0)
                    .tint(themeVM.accent)

                    HStack {
                        Label("Arc Edge Influence",
                              systemImage: "arrow.triangle.branch")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format: "%.4f", labVM.physics.arcEdgeInfluence))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(labVM.physics.isThresholdExceeded ? .orange : themeVM.accent)
                    }

                    if labVM.physics.isThresholdExceeded {
                        Label("⚡ Nucleus Blast Threshold Exceeded",
                              systemImage: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                SectionCard(title: "CFD Controls", icon: "wind") {
                    HStack(spacing: 12) {
                        Button {
                            if labVM.isCFDActive { labVM.stopCFD() }
                            else { labVM.startCFD() }
                        } label: {
                            Label(labVM.isCFDActive ? "Stop CFD" : "Start CFD",
                                  systemImage: labVM.isCFDActive ? "stop.fill" : "play.fill")
                                .font(.caption)
                                .foregroundColor(labVM.isCFDActive ? .red : .green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    (labVM.isCFDActive ? Color.red : Color.green).opacity(0.15))
                                .clipShape(Capsule())
                        }

                        if labVM.isCFDActive {
                            Text("\(labVM.cfdParticles.count) particles")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                        }
                    }

                    PhysicsSlider(label: "Particle Count",
                                  unit: "",
                                  value: Binding(
                                    get: { Double(labVM.physics.activeTab.particleCount) },
                                    set: { labVM.physics.activeTab.particleCount = Int($0) }),
                                  range: 50...2000,
                                  accent: themeVM.accent)
                }

                // Reset button
                Button {
                    labVM.physics.reset()
                    labVM.log("Physics reset to defaults")
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 6)
                }
            }
            .padding(12)
        }
    }
}

// MARK: — Reusable physics slider
struct PhysicsSlider: View {
    let label: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accent: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(accent)
                    .frame(width: 60)
                Text(unit)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 24, alignment: .leading)
            }
            Slider(value: $value, in: range)
                .tint(accent)
        }
        .padding(.vertical, 2)
    }
}

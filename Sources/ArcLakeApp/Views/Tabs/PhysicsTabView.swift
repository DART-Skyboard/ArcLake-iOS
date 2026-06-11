import SwiftUI

public struct PhysicsTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                PhysicsEnvSection()  // Env presets · matter state · wind

                // ── Point cloud resolution ──────────────────────────
                SectionCard(title: "Particle Resolution", icon: "circle.grid.3x3") {
                    VStack(spacing: 6) {
                        HStack {
                            Text("pts / component")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("\(labVM.ptsPerComponent)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                        }
                        Slider(value: Binding(
                            get: { Double(labVM.ptsPerComponent) },
                            set: { labVM.ptsPerComponent = max(1, Int($0)) }),
                               in: 1...500, step: 1)
                            .tint(themeVM.accent)
                        HStack {
                            Text("1 (fast)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                            Spacer()
                            Text("500 (detail)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        Text("Total pts = (p + n) × \(labVM.ptsPerComponent) nucleus + Σ(electrons) × \(labVM.ptsPerComponent) shells")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)

                        Button {
                            labVM.rebuildAllAtoms()
                        } label: {
                            Label("Apply to Scene", systemImage: "arrow.clockwise")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(themeVM.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        HStack(spacing: 6) {
                            ForEach([("Low",5),("Def",30),("Med",100),("High",250),("Max",500)], id: \.0) { label, val in
                                Button {
                                    labVM.ptsPerComponent = val
                                    labVM.rebuildAllAtoms()
                                } label: {
                                    Text(label)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(labVM.ptsPerComponent == val ? .black : .white.opacity(0.6))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(labVM.ptsPerComponent == val ? themeVM.accent : Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                // ── Environment physics ─────────────────────────────
                SectionCard(title: "Environment Physics", icon: "waveform.path") {
                    PhysicsSlider(label: "Temperature", unit: "°F",
                        value: Binding(get:{labVM.physics.temperature},set:{labVM.physics.temperature=$0}),
                        range: -200...2000, accent: themeVM.accent)
                    PhysicsSlider(label: "Gravity",     unit: "m/s²",
                        value: Binding(get:{labVM.physics.gravity},    set:{labVM.physics.gravity=$0}),
                        range: 0...30, accent: themeVM.accent)
                    PhysicsSlider(label: "Pressure",    unit: "psi",
                        value: Binding(get:{labVM.physics.pressure},   set:{labVM.physics.pressure=$0}),
                        range: 0...100, accent: themeVM.accent)
                    PhysicsSlider(label: "Velocity",    unit: "m/s",
                        value: Binding(get:{labVM.physics.velocity},   set:{labVM.physics.velocity=$0}),
                        range: 0...1000, accent: themeVM.accent)
                    PhysicsSlider(label: "Viscosity",   unit: "cP",
                        value: Binding(get:{labVM.physics.viscosity},  set:{labVM.physics.viscosity=$0}),
                        range: 0...5000, accent: themeVM.accent)
                    PhysicsSlider(label: "Magnetism",   unit: "T",
                        value: Binding(get:{labVM.physics.magnetism},  set:{labVM.physics.magnetism=$0}),
                        range: 0...10, accent: themeVM.accent)
                    Button("Reset to Standard Atmosphere") {
                        labVM.physics.pressure  = 14.7
                        labVM.physics.viscosity = 1.0
                        labVM.physics.temperature = 68.0
                        labVM.physics.gravity   = 9.81
                        labVM.log("Physics reset to standard atmosphere")
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)
                }

                // ── Nucleus ─────────────────────────────────────────
                SectionCard(title: "Nucleus", icon: "circle.dotted") {
                    HStack {
                        Text("Stable Force")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format:"%.3f", labVM.physics.stableForce))
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(themeVM.accent)
                    }
                    Slider(value: Binding(
                        get:{labVM.physics.stableForce}, set:{labVM.physics.stableForce=$0}),
                           in: 0.1...10).tint(themeVM.accent)
                    HStack {
                        Text("Arc Edge Influence")
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text(String(format:"%.4f", labVM.physics.arcEdgeInfluence))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(labVM.physics.isThresholdExceeded ? .orange : themeVM.accent)
                    }
                    if labVM.physics.isThresholdExceeded {
                        Label("⚡ Nucleus Blast Threshold Exceeded", systemImage: "bolt.fill")
                            .font(.caption2).foregroundColor(.orange)
                    }
                }

                // ── FLUID DYNAMICS ──────────────────────────────────
                SectionCard(title: "Fluid Dynamics", icon: "wind") {
                    VStack(spacing: 10) {
                        // Particle count
                        HStack {
                            Text("Particles")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("\(labVM.physics.activeTab.particleCount)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                            Text("SPH engine")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        Slider(value: Binding(
                            get:{Double(labVM.physics.activeTab.particleCount)},
                            set:{labVM.physics.activeTab.particleCount=Int($0)}),
                               in: 50...2000, step: 50)
                            .tint(themeVM.accent)

                        // Start/Stop CFD — full width, no HStack overflow
                        Button {
                            if labVM.isCFDActive { labVM.stopCFD() } else { labVM.startCFD() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: labVM.isCFDActive ? "stop.fill" : "play.fill")
                                    .font(.system(size: 12))
                                Text(labVM.isCFDActive ? "Stop CFD" : "Start CFD")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Spacer()
                                if labVM.isCFDActive {
                                    Text("\(labVM.cfdParticles.count) particles")
                                        .font(.system(size: 9, design: .monospaced))
                                        .opacity(0.7)
                                    Text("SPH engine")
                                        .font(.system(size: 8, design: .monospaced))
                                        .opacity(0.4)
                                }
                            }
                            .foregroundColor(labVM.isCFDActive ? .white : .black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(
                                labVM.isCFDActive
                                    ? Color.red.opacity(0.75)
                                    : themeVM.accent
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Button {
                    labVM.physics.reset()
                    labVM.log("Physics reset to defaults")
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(.caption).foregroundColor(.white.opacity(0.4)).padding(.vertical, 6)
                }
            }
            .padding(12)
        }
    }
}

struct PhysicsSlider: View {
    let label: String; let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>; let accent: Color
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                Spacer()
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.plain).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(accent)
                    .frame(width: 60)
                Text(unit).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3)).frame(width: 24)
            }
            Slider(value: $value, in: range).tint(accent)
        }.padding(.vertical, 2)
    }
}


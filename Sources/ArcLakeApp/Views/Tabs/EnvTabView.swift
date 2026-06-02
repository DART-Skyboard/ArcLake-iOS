
import SwiftUI

public struct EnvTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var selectedTabIdx = 0

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Large Scale CFD header
                SectionCard(title: "Large Scale CFD", icon: "cloud.fill") {
                    // Scene tab selector (5 tabs like web app)
                    HStack(spacing: 4) {
                        ForEach(0..<5) { idx in
                            Button {
                                selectedTabIdx = idx
                                labVM.physics.activeTabIndex = idx
                            } label: {
                                Text("Tab \(idx + 1)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(
                                        selectedTabIdx == idx ? .black : .white.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        selectedTabIdx == idx ?
                                        themeVM.accent : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Spacer()
                    }
                }

                // Per-tab physics
                SectionCard(title: "Tab \(selectedTabIdx + 1) Environment",
                            icon: "slider.horizontal.3") {
                    let binding = Binding<CFDTab>(
                        get: { labVM.physics.tabs[selectedTabIdx] },
                        set: { labVM.physics.tabs[selectedTabIdx] = $0 })

                    PhysicsSlider(label: "Temperature", unit: "°F",
                                  value: Binding(
                                    get: { labVM.physics.tabs[selectedTabIdx].temperature },
                                    set: { labVM.physics.tabs[selectedTabIdx].temperature = $0 }),
                                  range: -200...2000, accent: themeVM.accent)

                    PhysicsSlider(label: "Gravity", unit: "m/s²",
                                  value: Binding(
                                    get: { labVM.physics.tabs[selectedTabIdx].gravity },
                                    set: { labVM.physics.tabs[selectedTabIdx].gravity = $0 }),
                                  range: 0...30, accent: themeVM.accent)

                    PhysicsSlider(label: "Pressure", unit: "psi",
                                  value: Binding(
                                    get: { labVM.physics.tabs[selectedTabIdx].pressure },
                                    set: { labVM.physics.tabs[selectedTabIdx].pressure = $0 }),
                                  range: 0...100, accent: themeVM.accent)

                    PhysicsSlider(label: "Viscosity", unit: "cP",
                                  value: Binding(
                                    get: { labVM.physics.tabs[selectedTabIdx].viscosity },
                                    set: { labVM.physics.tabs[selectedTabIdx].viscosity = $0 }),
                                  range: 0...5000, accent: themeVM.accent)

                    // Sigma readout
                    HStack {
                        Label("Sigma Σ", systemImage: "waveform.path.ecg")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text(String(format: "%.4f",
                                    labVM.physics.tabs[selectedTabIdx].sigmaReadout))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }
                }

                // CFD particle visualizer
                if labVM.isCFDActive {
                    SectionCard(title: "CFD Particle View", icon: "circle.grid.3x3") {
                        CFDParticleView(particles: labVM.cfdParticles)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Audio-physics connections
                SectionCard(title: "Mic → Physics", icon: "mic.fill") {
                    ArcAudioView()
                }
            }
            .padding(12)
        }
    }
}

// MARK: — 2D CFD particle visualization
struct CFDParticleView: View {
    let particles: [SPHEngine.Particle]

    var body: some View {
        Canvas { ctx, size in
            let scale: CGFloat = size.width / 6.0
            let cx = size.width / 2
            let cy = size.height / 2
            for p in particles.prefix(300) {
                let x = cx + CGFloat(p.position.x) * scale
                let y = cy + CGFloat(p.position.y) * scale
                guard x >= 0 && x <= size.width && y >= 0 && y <= size.height else { continue }
                let speed = sqrt(p.velocity.x*p.velocity.x + p.velocity.y*p.velocity.y)
                let hue = Double(min(speed * 0.5, 1.0)) * 0.7
                let color = Color(hue: hue, saturation: 0.8, brightness: 0.9, opacity: 0.7)
                ctx.fill(Path(ellipseIn: CGRect(x: x-1.5, y: y-1.5, width: 3, height: 3)),
                         with: .color(color))
            }
        }
        .background(Color.black.opacity(0.5))
    }
}

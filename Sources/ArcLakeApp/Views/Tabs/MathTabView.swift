
import SwiftUI

public struct MathTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var selectedElement: ArcElement? = nil
    @State private var customZ: Int = 1

    private var element: ArcElement? {
        selectedElement ?? labVM.selectedElements.first ??
        ElementStore.shared.elements.first(where: { $0.protons == customZ })
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MathSetsSection()  // SET 1–4 neutron-first math engine

                SectionCard(title: "Neutron-First Math", icon: "function") {
                    Text("n⁰ → p⁺ → K → L → M → N → O → P → Q")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(themeVM.accent.opacity(0.8))
                        .padding(.bottom, 4)

                    // Element picker
                    HStack {
                        Text("Atomic Number (Z):")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Stepper("\(customZ)", value: $customZ, in: 1...128)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }

                    if let el = element {
                        Divider().background(themeVM.accent.opacity(0.2))

                        // Neutron-first propagation
                        mathRow("Neutrons (n⁰)", value: "\(el.neutrons)",
                                color: .orange)
                        mathRow("Protons (p⁺)",  value: "\(el.protons)",
                                color: .red)
                        mathRow("Electrons (e⁻)", value: "\(el.electrons)",
                                color: .cyan)
                        mathRow("Orbits",         value: "\(el.orbits)",
                                color: .purple)

                        Divider().background(themeVM.accent.opacity(0.2))

                        // Shell distribution K→Q
                        Text("Shell Distribution:")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        let shellNames = ["K","L","M","N","O","P","Q"]
                        ForEach(Array(el.electronOrbits.enumerated()), id: \.0) { idx, count in
                            HStack {
                                Text(idx < shellNames.count ? shellNames[idx] : "?")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(themeVM.accent)
                                    .frame(width: 20)
                                ProgressView(value: Double(count), total: Double(max(el.electronOrbits.max() ?? 1, 1)))
                                    .tint(themeVM.accent)
                                Text("\(count) e⁻")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 36)
                            }
                        }

                        Divider().background(themeVM.accent.opacity(0.2))

                        // Computed values
                        mathRow("Atomic Mass", value: String(format: "%.6f u", el.atomicMass),
                                color: .green)
                        mathRow("Neutron-First Mass",
                                value: String(format: "%.6f u", el.neutronFirstMass),
                                color: .yellow)
                        mathRow("Arc Edge C",
                                value: String(format: "%.4f pm", el.arcEdgeCircumference),
                                color: themeVM.accent)
                    }
                }

                // LEATR formula display
                SectionCard(title: "LEATR Formula", icon: "angle") {
                    formulaBlock("Core", "(xa²√xa)±1")
                    formulaBlock("Arc Edge", "C = √(d × 3.0)²")
                    formulaBlock("Quantum Socket", "(b·b)·(p(a²))/r")
                    formulaBlock("Sigma Meridian", "φ = 1.618...")
                    formulaBlock("Nucleus Blast",
                                 "F > φ × stable → blast")
                }
            }
            .padding(12)
        }
    }

    private func mathRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.vertical, 1)
    }

    private func formulaBlock(_ name: String, _ formula: String) -> some View {
        HStack {
            Text(name + ":")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 90, alignment: .leading)
            Text(formula)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeVM.accent)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}


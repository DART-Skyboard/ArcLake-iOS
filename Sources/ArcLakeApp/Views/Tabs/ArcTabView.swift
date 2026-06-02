
import SwiftUI

public struct ArcTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var selectedComponents: Set<ArcEdgeMath.ArcComponent> = [.group]
    @State private var showAllToAll = false
    @State private var arcResults: [ArcResult] = []

    struct ArcResult: Identifiable {
        let id = UUID()
        let component: String
        let value: Double
        let unit: String
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                SectionCard(title: "Arc Edge Algorithm", icon: "circle.and.line.horizontal") {
                    // DOC constant display
                    HStack {
                        Text("DOC (replaces π)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format: "%.1f", ArcEdgeMath.DOC))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(themeVM.accent)
                    }

                    HStack {
                        Text("Sigma Meridian (φ)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(String(format: "%.6f", ArcEdgeMath.SIGMA_MERIDIAN))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.purple)
                    }

                    Divider().background(themeVM.accent.opacity(0.2))

                    // Component selection
                    Text("Arc Components:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 8) {
                        ForEach(ArcEdgeMath.ArcComponent.allCases, id: \.self) { comp in
                            Toggle(comp.rawValue.capitalized,
                                   isOn: Binding(
                                    get: { selectedComponents.contains(comp) },
                                    set: { on in
                                        if on { selectedComponents.insert(comp) }
                                        else  { selectedComponents.remove(comp) }
                                    }))
                            .toggleStyle(.button)
                            .font(.system(size: 9, design: .monospaced))
                            .tint(themeVM.accent)
                        }
                    }

                    // All-to-all links
                    Toggle("All-to-All Links", isOn: $showAllToAll)
                        .font(.system(size: 10, design: .monospaced))
                        .tint(themeVM.accent)
                }

                // Compute button
                Button {
                    computeArcEdge()
                } label: {
                    Label("Compute Arc Edge", systemImage: "play.circle.fill")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(themeVM.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 12)

                // Results
                if !arcResults.isEmpty {
                    SectionCard(title: "Arc Results", icon: "chart.xyaxis.line") {
                        ForEach(arcResults) { result in
                            HStack {
                                Text(result.component)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                Spacer()
                                Text(String(format: "%.4f", result.value))
                                    .font(.system(size: 10, weight: .semibold,
                                                 design: .monospaced))
                                    .foregroundColor(themeVM.accent)
                                Text(result.unit)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: 24)
                            }
                        }
                    }
                }

                // Quantum socket calculator
                SectionCard(title: "Quantum Socket", icon: "cpu") {
                    QuantumSocketCalc()
                }
            }
            .padding(12)
        }
    }

    private func computeArcEdge() {
        arcResults = []
        for el in labVM.selectedElements {
            for comp in selectedComponents {
                let d: Double
                switch comp {
                case .group:    d = Double(el.protons + el.neutrons) * 0.1
                case .neutron:  d = Double(el.neutrons) * 0.1
                case .proton:   d = Double(el.protons) * 0.1
                case .electron: d = Double(el.electrons) * 0.05
                }
                let c = ArcEdgeMath.circumference(diameter: d)
                arcResults.append(ArcResult(
                    component: "\(el.elementSymbol).\(comp.rawValue)",
                    value: c,
                    unit: "pm"))
            }
        }
        labVM.log("Arc Edge computed for \(labVM.selectedElements.count) elements, \(selectedComponents.count) components")
    }
}

struct QuantumSocketCalc: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var b: Double = 1.0
    @State private var p: Double = 1.0
    @State private var a: Double = 1.0
    @State private var r: Double = 1.0

    var result: Double { ArcEdgeMath.quantumSocket(b: b, p: p, a: a, r: r) }

    var body: some View {
        VStack(spacing: 6) {
            Text("(b·b)·(p(a²))/r")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeVM.accent)

            ForEach([("b", $b), ("p", $p), ("a", $a), ("r", $r)],
                    id: \.0) { label, binding in
                HStack {
                    Text(label)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 16)
                    Slider(value: binding, in: 0.1...10.0)
                        .tint(themeVM.accent)
                    Text(String(format: "%.2f", binding.wrappedValue))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 40)
                }
            }

            HStack {
                Text("Result:")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(String(format: "%.6f", result))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(themeVM.accent)
            }
        }
    }
}

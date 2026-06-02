
import SwiftUI

/// Orbit Delta Floating Node Popup — per-atom probe
/// Matches web app's #orbit-delta-popup
public struct OrbitDeltaNodeView: View {
    let element: ArcElement
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var dragOffset = CGSize.zero

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(Color(element.category.color).opacity(0.3))
                    .overlay(Circle().stroke(Color(element.category.color), lineWidth: 1))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(element.elementSymbol)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(element.elementName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(element.category.rawValue)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color(element.category.color))
                }

                Spacer()

                Button {
                    withAnimation(.spring()) {
                        labVM.isOrbitDeltaVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Divider().background(themeVM.accent.opacity(0.3))

            // Atomic data
            Group {
                probeRow("Z (Protons)",   "\(element.protons)",    .red)
                probeRow("N (Neutrons)",  "\(element.neutrons)",   .orange)
                probeRow("e⁻ (Electrons)","\(element.electrons)", .cyan)
                probeRow("Orbits",        "\(element.orbits)",     .purple)
                probeRow("Atomic Mass",
                         String(format: "%.4f u", element.atomicMass), .green)
                probeRow("n-First Mass",
                         String(format: "%.4f u", element.neutronFirstMass), .yellow)
                probeRow("Arc-Edge C",
                         String(format: "%.4f pm", element.arcEdgeCircumference),
                         themeVM.accent)
            }

            Divider().background(themeVM.accent.opacity(0.3))

            // Shell distribution
            Text("Electron Shells:")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            let shellNames = ["K","L","M","N","O","P","Q"]
            ForEach(Array(element.electronOrbits.enumerated()), id: \.0) { idx, count in
                HStack(spacing: 6) {
                    Text(idx < shellNames.count ? shellNames[idx] : "?")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                        .frame(width: 14)
                    ForEach(0..<min(count, 18), id: \.self) { _ in
                        Circle()
                            .fill(Color.cyan.opacity(0.7))
                            .frame(width: 6, height: 6)
                    }
                    if count > 18 {
                        Text("+\(count-18)")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Divider().background(themeVM.accent.opacity(0.3))

            // Actions
            HStack(spacing: 8) {
                Button {
                    labVM.removeElement(element)
                    labVM.isOrbitDeltaVisible = false
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.red.opacity(0.7))
                }

                Spacer()

                Button {
                    labVM.isMolCanvasVisible = true
                    labVM.isOrbitDeltaVisible = false
                } label: {
                    Label("To Canvas", systemImage: "scribble")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                }
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeVM.accent.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: themeVM.accent.opacity(0.2), radius: 16)
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { val in dragOffset = val.translation }
        )
        .padding()
    }

    private func probeRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

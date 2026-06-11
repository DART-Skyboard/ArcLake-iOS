
import SwiftUI

public struct OrbitDeltaNodeView: View {
    let element: ArcElement
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var dragOffset = CGSize.zero
    @State private var basePos    = CGSize.zero

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(element.category.color).opacity(0.25))
                        .overlay(Circle().stroke(Color(element.category.color), lineWidth: 1))
                        .frame(width: 32, height: 32)
                    Text(element.elementSymbol)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(element.elementName)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white).lineLimit(1)
                    Text(element.category.rawValue)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color(element.category.color)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.spring()) { labVM.isOrbitDeltaVisible = false }
                } label: {
                    Image(systemName: "xmark").font(.caption)
                        .foregroundColor(.white.opacity(0.5)).frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.05))

            Divider().background(themeVM.accent.opacity(0.2))

            ScrollView {
                VStack(spacing: 0) {
                    probeRow("Z (Protons)",  "\(element.protons)",   .red)
                    probeRow("N (Neutrons)", "\(element.neutrons)",  .orange)
                    probeRow("e⁻",           "\(element.electrons)", .cyan)
                    probeRow("Orbits",       "\(element.orbits)",    .purple)
                    probeRow("Mass",         String(format:"%.4f u", element.atomicMass), .green)
                    probeRow("n-First",      String(format:"%.4f u", element.neutronFirstMass), .yellow)
                    probeRow("Arc-C",        String(format:"%.4f pm", element.arcEdgeCircumference), themeVM.accent)

                    Divider().background(themeVM.accent.opacity(0.15)).padding(.vertical, 4)

                    HStack {
                        Text("Shells:")
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        Spacer()
                    }.padding(.horizontal, 12)

                    let shellNames = ["K","L","M","N","O","P","Q"]
                    ForEach(Array(element.electronOrbits.enumerated()), id: \.0) { idx, count in
                        HStack(spacing: 4) {
                            Text(idx < shellNames.count ? shellNames[idx] : "?")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(themeVM.accent).frame(width: 14)
                            HStack(spacing: 2) {
                                ForEach(0..<min(count,14), id:\.self) { _ in
                                    Circle().fill(Color.cyan.opacity(0.7)).frame(width:5,height:5)
                                }
                                if count > 14 {
                                    Text("+\(count-14)")
                                        .font(.system(size:7, design:.monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            Spacer()
                            Text("\(count)")
                                .font(.system(size:8, design:.monospaced))
                                .foregroundColor(.white.opacity(0.4)).frame(width:20, alignment:.trailing)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider().background(themeVM.accent.opacity(0.2))

            HStack(spacing: 8) {
                Button {
                    labVM.removeElement(element)
                    labVM.isOrbitDeltaVisible = false
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.red.opacity(0.8))
                }
                Spacer()
                // Add to canvas — actually adds atom to mol canvas
                Button {
                    labVM.addToMolCanvas(element: element)
                    labVM.isMolCanvasVisible = true
                    labVM.isOrbitDeltaVisible = false
                } label: {
                    Label("To Canvas", systemImage: "scribble")
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(themeVM.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 230)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.35), lineWidth: 0.5))
        .shadow(color: themeVM.accent.opacity(0.2), radius: 12)
        .offset(CGSize(width:  basePos.width  + dragOffset.width,
                       height: basePos.height + dragOffset.height))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded { val in
                    // Accumulate — card stays where you leave it, anywhere on screen
                    basePos.width  += val.translation.width
                    basePos.height += val.translation.height
                    dragOffset = .zero
                }
        )
    }

    private func probeRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.system(size:9, design:.monospaced))
                .foregroundColor(.white.opacity(0.4)).frame(width:70, alignment:.leading)
            Spacer()
            Text(value).font(.system(size:9, weight:.semibold, design:.monospaced))
                .foregroundColor(color).lineLimit(1).frame(width:110, alignment:.trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
    }
}


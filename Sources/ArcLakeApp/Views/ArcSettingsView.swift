import SwiftUI

// MARK: — ArcSettingsView
// Settings menu for Arc Lake.
// • 3D Scene — grid plane defaults, divisions, axis display
// • Arc Edge Physics (Advanced) — DOC constant, Sigma Meridian,
//   per-plane meridian join. Ported from arc-edge-vector.html.
//   Not needed for typical chemistry-lab use — for advanced
//   environmental physics/math directly in the hardware 3D scene.
// • About / Open Source — engine credits
struct ArcSettingsView: View {
    @EnvironmentObject var labVM:   ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.039, blue: 0.063).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {

                    // Header
                    HStack {
                        Text("SETTINGS")
                            .font(.custom("Orbitron-Bold", size: 14))
                            .foregroundColor(themeVM.accent)
                            .tracking(3)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .padding(.top, 18)

                    // ── 3D SCENE ──────────────────────────────────
                    settingsCard("3D SCENE") {
                        toggleRow("Floor Plane (XZ)", isOn: $labVM.showGridXZ)
                        toggleRow("Wall Plane (XY)",  isOn: $labVM.showGridXY)
                        toggleRow("Wall Plane (YZ)",  isOn: $labVM.showGridYZ)
                        toggleRow("Axis Gimbal (XYZ)", isOn: $labVM.showAxisIndicators)
                        toggleRow("Axis Labels",       isOn: $labVM.showAxisLabels)

                        // Grid divisions stepper
                        HStack {
                            Text("Grid Divisions")
                                .font(.custom("Exo2-Regular", size: 13))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text("\(labVM.gridDivisions) × \(labVM.gridDivisions)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(themeVM.accent)
                            Stepper("", value: $labVM.gridDivisions, in: 4...60, step: 4)
                                .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: labVM.showGridXZ)        { _ in labVM.rebuildGrid() }
                    .onChange(of: labVM.showGridXY)        { _ in labVM.rebuildGrid() }
                    .onChange(of: labVM.showGridYZ)        { _ in labVM.rebuildGrid() }
                    .onChange(of: labVM.showAxisIndicators){ _ in labVM.rebuildGrid() }
                    .onChange(of: labVM.showAxisLabels)    { _ in labVM.rebuildGrid() }
                    .onChange(of: labVM.gridDivisions)     { _ in labVM.rebuildGrid() }

                    // ── ARC EDGE PHYSICS (ADVANCED) ───────────────
                    settingsCard("ARC EDGE PHYSICS · ADVANCED") {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                showAdvanced.toggle()
                            }
                        } label: {
                            HStack {
                                Text(showAdvanced ? "Hide Advanced Controls" : "Show Advanced Controls")
                                    .font(.custom("Exo2-SemiBold", size: 12))
                                    .foregroundColor(themeVM.accent)
                                Spacer()
                                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundColor(themeVM.accent.opacity(0.6))
                            }
                        }

                        if showAdvanced {
                            Text("Hardware-level arc vector environment controls ported from the Arc Edge Vector engine. Not required for typical chemistry-lab use.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                                .fixedSize(horizontal: false, vertical: true)

                            // DOC constant
                            sliderRow("DOC Constant",
                                      value: $labVM.arcDOC, range: 1.0...6.0,
                                      format: "%.2f",
                                      hint: "Arc Edge deviation constant — replaces π in arc math")

                            Divider().background(Color.white.opacity(0.08))

                            // Sigma Meridian
                            Text("SIGMA MERIDIAN — shared 3D lock point")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4)).tracking(1.5)
                            sliderRow("σ X", value: $labVM.sigmaMX, range: -5...5, format: "%.2f")
                            sliderRow("σ Y", value: $labVM.sigmaMY, range: -5...5, format: "%.2f")
                            sliderRow("σ Z", value: $labVM.sigmaMZ, range: -5...5, format: "%.2f")

                            Divider().background(Color.white.opacity(0.08))

                            // Per-plane meridian join
                            Text("JOIN MERIDIAN — GRID PLANES")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4)).tracking(1.5)
                            toggleRow("Plane XZ unified arc", isOn: $labVM.meridianJoinXZ)
                            toggleRow("Plane XY unified arc", isOn: $labVM.meridianJoinXY)
                            toggleRow("Plane ZY unified arc", isOn: $labVM.meridianJoinZY)

                            // Reset
                            Button {
                                labVM.arcDOC = 3.0
                                labVM.sigmaMX = 0; labVM.sigmaMY = 0; labVM.sigmaMZ = 0
                                labVM.meridianJoinXZ = true
                                labVM.meridianJoinXY = true
                                labVM.meridianJoinZY = true
                            } label: {
                                Text("RESET ARC EDGE DEFAULTS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                    }

                    // ── ABOUT / OPEN SOURCE ───────────────────────
                    settingsCard("ABOUT · OPEN SOURCE") {
                        aboutRow("3D Engine",
                                 "Arc Edge Vector — custom turntable scene system",
                                 link: "https://radicaldeepscale.com/arc-edge-vector.html")
                        Divider().background(Color.white.opacity(0.08))
                        aboutRow("Renderer",
                                 "Apple SceneKit · Metal — native hardware graphics",
                                 link: nil)
                        Divider().background(Color.white.opacity(0.08))
                        aboutRow("GL Translation Research",
                                 "MetalANGLE — OpenGL ES → Metal API translation layer (MIT)",
                                 link: "https://github.com/kakashidinho/metalangle")
                        Divider().background(Color.white.opacity(0.08))
                        aboutRow("Framework",
                                 "LEATR · BRPN · mc³ — Radical Deepscale LLC",
                                 link: "https://radicaldeepscale.com")
                    }

                    Spacer().frame(height: 30)
                }
                .padding(.horizontal, 18)
            }
        }
        .preferredColorScheme(.dark)
    }

    // ── Card scaffold ─────────────────────────────────────────────
    @ViewBuilder
    private func settingsCard<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2.5)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.14), lineWidth: 0.8))
    }

    @ViewBuilder
    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.custom("Exo2-Regular", size: 13))
                .foregroundColor(.white.opacity(0.8))
        }
        .tint(themeVM.accent)
    }

    @ViewBuilder
    private func sliderRow(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, format: String,
                           hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.custom("Exo2-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(themeVM.accent)
            }
            Slider(value: value, in: range)
                .tint(themeVM.accent)
            if let hint {
                Text(hint)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private func aboutRow(_ title: String, _ detail: String, link: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.custom("Exo2-SemiBold", size: 12))
                .foregroundColor(.white.opacity(0.85))
            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            if let link, let url = URL(string: link) {
                Link(link.replacingOccurrences(of: "https://", with: ""),
                     destination: url)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.8))
            }
        }
    }
}

import SwiftUI

public struct MoleculeTabView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showExportPicker = false
    @State private var exportURL: URL?

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Active elements list
                SectionCard(title: "Active Elements", icon: "atom") {
                    if labVM.selectedElements.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "atom")
                                .font(.system(size: 28))
                                .foregroundColor(themeVM.accent.opacity(0.3))
                            Text("Open the Periodic Table to add elements")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else {
                        ForEach(labVM.selectedElements) { el in
                            elementRow(el)
                        }
                    }
                }

                // Quick actions — 4 buttons in a scrollable row, no overflow
                SectionCard(title: "Actions", icon: "sparkles") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ActionButton(
                                title: "Periodic\nTable",
                                icon: "tablecells",
                                color: themeVM.accent
                            ) {
                                withAnimation(.spring()) {
                                    labVM.isPeriodicTableVisible.toggle()
                                }
                            }

                            ActionButton(
                                title: "Mol\nCanvas",
                                icon: "scribble",
                                color: .purple
                            ) {
                                withAnimation(.spring()) {
                                    labVM.isMolCanvasVisible.toggle()
                                }
                            }

                            ActionButton(
                                title: "Export\nGLB/USDZ",
                                icon: "square.and.arrow.up",
                                color: .green
                            ) {
                                showExportPicker = true
                            }

                            ActionButton(
                                title: "Clear\nAll",
                                icon: "trash",
                                color: .red.opacity(0.8)
                            ) {
                                labVM.clearElements()
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                // Alloy builder
                SectionCard(title: "Alloy Components", icon: "flask.fill") {
                    AlloyBuilderView()
                }
            }
            .padding(12)
        }
        // Export format picker
        .confirmationDialog("Export Format", isPresented: $showExportPicker, titleVisibility: .visible) {
            Button("Export as GLB (3D interchange)") {
                if let url = labVM.exportGLB() { share(url: url) }
            }
            Button("Export as USDZ (Apple AR)") {
                if let url = labVM.exportUSDZ() { share(url: url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the 3D export format")
        }
    }

    private func share(url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Present from the key window's root VC
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        // On iPad, anchor the popover
        av.popoverPresentationController?.sourceView = rootVC.view
        av.popoverPresentationController?.sourceRect = CGRect(
            x: rootVC.view.bounds.midX, y: rootVC.view.bounds.maxY - 100, width: 1, height: 1)
        rootVC.present(av, animated: true)
    }

    private func elementRow(_ el: ArcElement) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(el.category.color).opacity(0.3))
                .overlay(Circle().stroke(Color(el.category.color), lineWidth: 1))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(el.elementSymbol)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(el.elementName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                Text("Z=\(el.protons)  n=\(el.neutrons)  mass=\(String(format:"%.3f", el.atomicMass))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button { labVM.openProbe(for: el) } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.caption).foregroundColor(themeVM.accent)
            }
            Button { labVM.removeElement(el) } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(Color(el.category.color).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: — Alloy builder
struct AlloyBuilderView: View {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    var body: some View {
        VStack(spacing: 8) {
            if labVM.alloyComponents.isEmpty {
                Text("Add elements to build an alloy")
                    .font(.caption2).foregroundColor(.white.opacity(0.3)).padding(.vertical, 8)
            } else {
                ForEach(labVM.alloyComponents) { comp in
                    HStack {
                        Text(comp.element.elementSymbol)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(comp.element.category.color)).frame(width: 28)
                        Text("\(String(format: "%.1f", comp.percentage))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        ProgressView(value: comp.percentage / 100)
                            .tint(Color(comp.element.category.color))
                        Text("#\(comp.castingOrder)")
                            .font(.caption2).foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            if !labVM.selectedElements.isEmpty {
                Button { addSelectedAsAlloy() } label: {
                    Label("Build Alloy from Selection", systemImage: "plus.circle")
                        .font(.caption).foregroundColor(themeVM.accent)
                }
            }
        }
    }

    private func addSelectedAsAlloy() {
        let count = labVM.selectedElements.count
        labVM.alloyComponents = labVM.selectedElements.enumerated().map { idx, el in
            AlloyComponent(element: el,
                          percentage: 100.0 / Double(count),
                          castingOrder: idx + 1)
        }
        labVM.log("Alloy built: \(labVM.alloyComponents.map{$0.element.elementSymbol}.joined(separator: "-"))")
    }
}

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// ArcCompoundLibraryView — view/manage saved named compounds (task #39).
// Simple list + delete; renaming via swipe-to-edit is intentionally
// skipped for v1 (not asked for) — delete + re-save covers it.
// ═══════════════════════════════════════════════════════════════════

struct ArcCompoundLibraryView: View {
    @StateObject private var library = ArcCompoundLibrary.shared
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if library.compounds.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "flask").font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No saved compounds yet")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Text("Build something in the Mol Canvas, then tap \"Save Compound\" in the Build tab.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(library.compounds) { compound in
                            HStack(spacing: 10) {
                                Circle().fill(compound.displayColor).frame(width: 14, height: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(compound.name)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text("\(compound.displayFormula) · \(compound.elements.count) atoms · ~\(Int(compound.estimatedDensityKgM3)) kg/m³")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                            }
                            .listRowBackground(Color(red:0.04,green:0.06,blue:0.11))
                        }
                        .onDelete { library.delete(at: $0) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red:0.02,green:0.04,blue:0.09))
            .navigationTitle("Saved Compounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

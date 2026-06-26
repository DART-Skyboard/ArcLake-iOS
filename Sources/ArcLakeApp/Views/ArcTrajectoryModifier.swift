import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════════════
// ArcTrajectoryModifier.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// ViewModifier that attaches all trajectory-related UI to any view
// WITHOUT adding complexity to DARTRootView.body.
//
// Applies:
//   · Target body selector sheet (presented via labVM.mantis.showTargetBodySelector)
//   · Trajectory scrubber overlay (shown at top when trajectory is linked)
// ═══════════════════════════════════════════════════════════════════════════

struct ArcTrajectoryModifier: ViewModifier {
    @EnvironmentObject var labVM: ArcLabViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel

    func body(content: Content) -> some View {
        content
            // Target body selector sheet
            // Custom Binding because labVM.mantis is `public let` (not @Published)
            .sheet(isPresented: Binding(
                get: { labVM.mantis.showTargetBodySelector },
                set: { labVM.mantis.showTargetBodySelector = $0 }
            )) {
                ArcTargetBodySelector { selectedId in
                    labVM.mantis.showTargetBodySelector = false
                    labVM.mantis.isTrajectoryLinked = true
                    Task {
                        let vNode = labVM.mantis.vehicleNode(in: labVM.scene) ?? SCNNode()
                        await ArcTrajectoryEngine.shared.link(
                            scene: labVM.scene,
                            vehicleNode: vNode,
                            targetId: selectedId)
                    }
                }
                .environmentObject(themeVM)
            }
            // Trajectory scrubber overlay — top of screen when linked
            .overlay(alignment: .top) {
                if ArcTrajectoryEngine.shared.isLinked {
                    ArcTrajectoryScrubberOverlay()
                        .environmentObject(themeVM)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: ArcTrajectoryEngine.shared.isLinked)
                }
            }
    }
}

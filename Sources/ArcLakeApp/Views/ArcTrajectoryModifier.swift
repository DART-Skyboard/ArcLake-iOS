import SwiftUI
import SceneKit

// ArcTrajectoryModifier — attaches trajectory scrubber overlay to any view.
// Target selection is now inline in MantisSettingsSheet (no separate modal).

struct ArcTrajectoryModifier: ViewModifier {
    @EnvironmentObject var themeVM: ArcThemeViewModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if ArcTrajectoryEngine.shared.isLinked {
                    ArcTrajectoryScrubberOverlay()
                        .environmentObject(themeVM)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3),
                                   value: ArcTrajectoryEngine.shared.isLinked)
                }
            }
    }
}

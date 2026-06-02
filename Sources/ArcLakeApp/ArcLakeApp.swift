
import SwiftUI

@main
struct ArcLakeApp: App {
    @StateObject private var labVM    = ArcLabViewModel()
    @StateObject private var themeVM  = ArcThemeViewModel()

    var body: some Scene {
        WindowGroup {
            ArcRootView()
                .environmentObject(labVM)
                .environmentObject(themeVM)
                .preferredColorScheme(.dark)
        }
    }
}

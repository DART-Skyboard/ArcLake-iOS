import SwiftUI

@main
struct ArcLakeClipApp: App {
    var body: some Scene {
        WindowGroup {
            ClipRootView()
                .preferredColorScheme(.dark)
        }
    }
}

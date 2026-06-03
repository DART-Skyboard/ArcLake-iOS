import SwiftUI

@main
struct DARTApp: App {
    @StateObject private var labVM   = ArcLabViewModel()
    @StateObject private var themeVM = ArcThemeViewModel()
    @StateObject private var authVM  = ArcAuthViewModel()

    var body: some Scene {
        WindowGroup {
            DARTAppRootView()
                .environmentObject(labVM)
                .environmentObject(themeVM)
                .environmentObject(authVM)
                .preferredColorScheme(.dark)
        }
    }
}

struct DARTAppRootView: View {
    @EnvironmentObject var authVM: ArcAuthViewModel
    var body: some View {
        Group {
            if authVM.isSignedIn {
                DARTRootView()
            } else {
                ArcWelcomeView()
            }
        }
        .onAppear { authVM.restoreSession() }
    }
}

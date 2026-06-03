import SwiftUI

@main
struct ArcLakeApp: App {
    @StateObject private var labVM   = ArcLabViewModel()
    @StateObject private var themeVM = ArcThemeViewModel()
    @StateObject private var authVM  = ArcAuthViewModel()

    var body: some Scene {
        WindowGroup {
            ArcAppRootView()
                .environmentObject(labVM)
                .environmentObject(themeVM)
                .environmentObject(authVM)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: — App root — gates on sign-in
struct ArcAppRootView: View {
    @EnvironmentObject var authVM: ArcAuthViewModel

    var body: some View {
        Group {
            if authVM.isSignedIn {
                ArcRootView()
            } else {
                ArcWelcomeView()
            }
        }
        .onAppear { authVM.restoreSession() }
    }
}

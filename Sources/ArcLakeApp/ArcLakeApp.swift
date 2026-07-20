import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

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
                // Google Sign-In OAuth callback (reversed client-ID URL scheme)
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
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
        .onAppear {
            authVM.restoreSession()
            // Google session restore — GIDClientID is read from Info.plist automatically
            authVM.restoreGoogleSession()
        }
    }
}

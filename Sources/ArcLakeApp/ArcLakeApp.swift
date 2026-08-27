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
                .task {
                    // Capture the environment snapshot automatically instead of
                    // relying on the Log tab button being tapped — this is the
                    // data that shows whether the SHIPPED build actually carries
                    // the Sign in with Apple entitlement.
                    ArcDiagnostics.shared.captureEnvironment()
                }
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
    // Which marketing version last showed the intro on this device — the
    // intro replays whenever this doesn't match the current version (a new
    // update was installed), in addition to first install and post-sign-out.
    @AppStorage("arc_lastIntroVersionShown") private var lastIntroVersionShown: String = ""
    @State private var decided = false
    @State private var showIntro = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var body: some View {
        Group {
            if !decided {
                // A single neutral frame while session restoration settles —
                // avoids a flash of the wrong screen for anyone signed in via
                // Apple ID, whose restore path is asynchronous.
                Color.black.ignoresSafeArea()
            } else if showIntro {
                ArcIntroView {
                    lastIntroVersionShown = currentVersion
                    showIntro = false
                }
            } else if authVM.isSignedIn {
                DARTRootView()
            } else {
                ArcWelcomeView()
            }
        }
        .onAppear {
            authVM.restoreSession()
            // Google session restore — GIDClientID is read from Info.plist automatically
            authVM.restoreGoogleSession()
            // Apple ID restoration (unlike GitHub's) resolves via an async
            // completion handler, so isSignedIn may not have settled the
            // instant restoreSession() returns. A brief window lets that
            // resolve before the intro/skip decision is made, rather than
            // deciding on a value that might still be mid-flight.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showIntro = (lastIntroVersionShown != currentVersion) || !authVM.isSignedIn
                decided = true
            }
        }
    }
}

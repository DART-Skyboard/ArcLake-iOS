import SwiftUI
import AuthenticationServices
import SafariServices

// MARK: — ArcWelcomeView v2
// Smart auth state detection:
// • GitHub token in Keychain  → "Continue as [username]" (no re-auth)
// • Apple credential valid    → skipped entirely (restoreSession handles it)
// • Neither                   → full sign-in flow
struct ArcWelcomeView: View {
    @EnvironmentObject var authVM: ArcAuthViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showGitHubSheet = false
    @State private var pulseAnim = false

    // Computed: do we have a saved GitHub token we can resume from?
    var hasStoredGitHub: Bool {
        guard let t = KeychainHelper.load(key: "arc_github_pat") else { return false }
        return !t.isEmpty
    }
    var storedGitHubUser: String {
        KeychainHelper.load(key: "arc_github_username") ?? "GitHub"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red:0.024,green:0.039,blue:0.063), Color(red:0.039,green:0.055,blue:0.078)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Logo orb ─────────────────────────────────────────
                ZStack {
                    Circle()
                        .stroke(themeVM.accent.opacity(0.10), lineWidth: 1)
                        .frame(width: pulseAnim ? 195 : 160, height: pulseAnim ? 195 : 160)
                        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                                   value: pulseAnim)
                    Circle().fill(themeVM.accent.opacity(0.06)).frame(width: 140, height: 140)
                    Circle().stroke(themeVM.accent.opacity(0.4), lineWidth: 1.5).frame(width: 140, height: 140)
                    // Arc Lake logo — Autumn + hummingbird (bundle asset)
                    if let logo = UIImage(named: "ArcLakeLogo") {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 134, height: 134)
                            .clipShape(Circle())
                    } else {
                        Text("AL")
                            .font(.custom("Orbitron-Bold", size: 36))
                            .foregroundColor(themeVM.accent)
                    }
                }
                .onAppear { pulseAnim = true }

                Spacer().frame(height: 28)

                VStack(spacing: 5) {
                    Text("ARC LAKE")
                        .font(.custom("Orbitron-Bold", size: 26))
                        .foregroundColor(.white)
                        .tracking(6)
                    Text("LEATR · Molecular Physics · Radical Deepscale")
                        .font(.custom("Exo2-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // ── Auth buttons ──────────────────────────────────────
                VStack(spacing: 12) {

                    // ① Sign in with Apple — ALWAYS first
                    if !authVM.savedAppleAccounts.isEmpty {
                        // Saved Apple accounts — show them as quick-resume rows
                        ForEach(authVM.savedAppleAccounts) { account in
                            Button { authVM.switchAppleAccount(to: account) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.1)).frame(width:32,height:32)
                                        Image(systemName: "applelogo")
                                            .font(.system(size:13)).foregroundColor(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Continue as \(account.displayName)")
                                            .font(.custom("Exo2-SemiBold", size: 15))
                                            .foregroundColor(.white)
                                        Text("Apple ID · saved")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.green.opacity(0.7))
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green.opacity(0.8))
                                }
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                        }
                        // Add another Apple ID
                        SignInWithAppleButton(.signIn) { req in
                            authVM.configureAppleRequest(req)
                        } onCompletion: { result in
                            authVM.handleAppleResult(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 44).cornerRadius(10)
                    } else {
                        // No saved Apple accounts — show full Sign In button
                        SignInWithAppleButton(.signIn) { req in
                            authVM.configureAppleRequest(req)
                        } onCompletion: { result in
                            authVM.handleAppleResult(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52).cornerRadius(12)
                    }

                    // ② Google Sign-In
                    if authVM.googleConnected {
                        Button { authVM.signOutGoogle() } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.1)).frame(width:32,height:32)
                                    // Google "G" in brand colors
                                    Text("G").font(.system(size:14,weight:.bold)).foregroundColor(.white)
                                }
                                VStack(alignment:.leading, spacing:2) {
                                    Text("Signed in: \(authVM.googleEmail)")
                                        .font(.custom("Exo2-SemiBold",size:13)).foregroundColor(.white)
                                    Text("Google · tap to disconnect")
                                        .font(.system(size:9,design:.monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName:"checkmark.circle.fill").foregroundColor(.green.opacity(0.8))
                            }
                            .padding(.horizontal,14).frame(maxWidth:.infinity).frame(height:52)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius:12))
                            .overlay(RoundedRectangle(cornerRadius:12)
                                .stroke(Color.white.opacity(0.15),lineWidth:1))
                        }
                    } else {
                        Button { authVM.signInWithGoogle() } label: {
                            HStack(spacing:10) {
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.1)).frame(width:32,height:32)
                                    Text("G").font(.system(size:14,weight:.bold)).foregroundColor(.white)
                                }
                                Text("Sign in with Google")
                                    .font(.custom("Exo2-SemiBold",size:15)).foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal,14).frame(maxWidth:.infinity).frame(height:52)
                            .background(Color(red:0.26,green:0.52,blue:0.96).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius:12))
                            .overlay(RoundedRectangle(cornerRadius:12)
                                .stroke(Color(red:0.26,green:0.52,blue:0.96).opacity(0.4),lineWidth:1))
                        }
                    }

                    // ③ GitHub — dynamic label based on stored token
                    if hasStoredGitHub {
                        Button { authVM.resumeStoredGitHubSession() } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(themeVM.accent.opacity(0.15)).frame(width:30,height:30)
                                    Text(String(storedGitHubUser.prefix(1)).uppercased())
                                        .font(.system(size:13, weight:.bold, design:.monospaced))
                                        .foregroundColor(themeVM.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Continue as \(storedGitHubUser)")
                                        .font(.custom("Exo2-SemiBold", size: 15)).foregroundColor(.white)
                                    Text("GitHub · already authorized")
                                        .font(.system(size:9, design:.monospaced))
                                        .foregroundColor(.green.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName:"checkmark.circle.fill")
                                    .font(.system(size:17)).foregroundColor(.green.opacity(0.8))
                            }
                            .padding(.horizontal, 14)
                            .frame(maxWidth:.infinity).frame(height: 58)
                            .background(themeVM.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(themeVM.accent.opacity(0.4), lineWidth: 1.2))
                        }
                        Button { showGitHubSheet = true } label: {
                            Text("Use a different GitHub account")
                                .font(.system(size:11, design:.monospaced))
                                .foregroundColor(.white.opacity(0.3)).underline()
                        }
                        .padding(.top, -4)
                    } else {
                        Button { showGitHubSheet = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName:"link.circle.fill").font(.system(size:17))
                                Text("Connect GitHub").font(.custom("Exo2-SemiBold", size: 15))
                            }
                            .foregroundColor(themeVM.accent)
                            .frame(maxWidth:.infinity).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .stroke(themeVM.accent.opacity(0.35), lineWidth: 1.2))
                        }
                    }

                    // ③ Continue as Guest — always visible
                    Button { authVM.continueAsGuest() } label: {
                        HStack(spacing: 8) {
                            Image(systemName:"person.fill")
                                .font(.system(size:14)).foregroundColor(.white.opacity(0.5))
                            Text("Continue as Guest")
                                .font(.custom("Exo2-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth:.infinity).frame(height: 48)
                        .background(Color.white.opacity(0.05)).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }

                    if let err = authVM.error {
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Text("Your work saves to Autumn-Ash in iCloud Drive")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, 8)
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 48)
            }
        }
        .sheet(isPresented: $showGitHubSheet) {
            ArcGitHubDeviceFlowSheet()
        }
    }
}

// MARK: — GitHub Device Flow Sheet
struct ArcGitHubDeviceFlowSheet: View {
    @EnvironmentObject var authVM: ArcAuthViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showSafari = false
    @State private var didAutoOpen = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red:0.024,green:0.039,blue:0.063), Color(red:0.039,green:0.055,blue:0.078)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Connect GitHub")
                    .font(.custom("Orbitron-Bold", size: 20))
                    .foregroundColor(themeVM.accent)
                    .padding(.top, 32)

                if let flow = authVM.deviceFlowCode {
                    VStack(spacing: 16) {
                        // Step 1: Show the code prominently — user can copy it BEFORE going to GitHub
                        VStack(spacing: 8) {
                            Text("STEP 1 — Copy this code")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .tracking(1)

                            Button {
                                UIPasteboard.general.string = flow.userCode
                            } label: {
                                VStack(spacing: 6) {
                                    Text(flow.userCode)
                                        .font(.custom("Orbitron-Bold", size: 32))
                                        .foregroundColor(.white).tracking(10)
                                        .padding(.horizontal, 20).padding(.vertical, 14)
                                        .background(Color.white.opacity(0.08)).cornerRadius(12)
                                    Label("Tap to copy", systemImage: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                        }

                        // Step 2: Open GitHub (code is already in clipboard)
                        VStack(spacing: 6) {
                            Text("STEP 2 — Authorize on GitHub")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .tracking(1)

                            Button {
                                UIPasteboard.general.string = flow.userCode
                                showSafari = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "safari.fill").font(.system(size: 15))
                                    Text("Open GitHub Authorization")
                                        .font(.custom("Exo2-SemiBold", size: 14))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(themeVM.accent).cornerRadius(12)
                            }
                            .padding(.horizontal, 28)

                            Text("Paste the code when GitHub asks for it.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }

                        HStack(spacing: 10) {
                            ProgressView().tint(themeVM.accent).scaleEffect(0.9)
                            Text("Waiting for authorization…")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 24)
                    .onAppear {
                        // Auto-copy code on appear — but do NOT auto-open Safari
                        // so the user has time to read/copy the code first
                        if !didAutoOpen {
                            didAutoOpen = true
                            UIPasteboard.general.string = flow.userCode
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("Authorize ArcLake to sync with your GitHub repositories.")
                            .font(.custom("Exo2-Regular", size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                        Button {
                            Task { await authVM.startGitHubAuth() }
                        } label: {
                            Text("Start GitHub Authorization")
                                .font(.custom("Exo2-SemiBold", size: 15))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(themeVM.accent).cornerRadius(12)
                        }
                        .padding(.horizontal, 28)
                    }
                }

                if let err = authVM.error {
                    Text(err).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }

                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundColor(.white.opacity(0.4)).padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showSafari) {
            if let url = URL(string: "https://github.com/login/device") {
                ArcSafariView(url: url).ignoresSafeArea()
            }
        }
        .onChange(of: authVM.githubConnected) { connected in
            if connected { dismiss() }
        }
    }
}

struct ArcSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0, green: 0.9, blue: 1.0, alpha: 1)
        vc.preferredBarTintColor = UIColor(red: 0.02, green: 0.05, blue: 0.08, alpha: 1)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}




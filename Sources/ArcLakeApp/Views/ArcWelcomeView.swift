import SwiftUI
import AuthenticationServices
import SafariServices

// MARK: — ArcWelcomeView
// Sign-in screen for ArcLake — matches Autumn's design language
struct ArcWelcomeView: View {
    @EnvironmentObject var authVM: ArcAuthViewModel
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @State private var showGitHubSheet = false
    @State private var pulseAnim = false

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
                    Text("AL")
                        .font(.custom("Orbitron-Bold", size: 36))
                        .foregroundColor(themeVM.accent)
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

                    // ① Sign in with Apple
                    SignInWithAppleButton(.signIn) { req in
                        authVM.configureAppleRequest(req)
                    } onCompletion: { result in
                        authVM.handleAppleResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .cornerRadius(12)

                    // ② Connect GitHub
                    Button { showGitHubSheet = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "link.circle.fill").font(.system(size: 17))
                            Text(authVM.githubConnected ? "GitHub Connected ✓" : "Connect GitHub")
                                .font(.custom("Exo2-SemiBold", size: 15))
                        }
                        .foregroundColor(authVM.githubConnected ? .green : themeVM.accent)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .stroke(authVM.githubConnected
                                    ? Color.green.opacity(0.4)
                                    : themeVM.accent.opacity(0.35), lineWidth: 1.2))
                    }

                    // ③ Continue as Guest
                    Button { authVM.continueAsGuest() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                            Text("Continue as Guest")
                                .font(.custom("Exo2-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
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

                    // Vault note
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

// MARK: — GitHub Device Flow Sheet (ArcLake)
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
                        Button {
                            UIPasteboard.general.string = flow.userCode
                        } label: {
                            VStack(spacing: 6) {
                                Text(flow.userCode)
                                    .font(.custom("Orbitron-Bold", size: 30))
                                    .foregroundColor(.white).tracking(8)
                                    .padding(.horizontal, 20).padding(.vertical, 14)
                                    .background(Color.white.opacity(0.08)).cornerRadius(12)
                                Label("Tap to copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }

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

                        Text("Code copied — paste it on the GitHub page.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center).padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            ProgressView().tint(themeVM.accent).scaleEffect(0.9)
                            Text("Waiting for authorization…")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 24)
                    .onAppear {
                        if !didAutoOpen {
                            didAutoOpen = true
                            UIPasteboard.general.string = flow.userCode
                            showSafari = true
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

// Color(hex:) is defined in SharedComponents.swift

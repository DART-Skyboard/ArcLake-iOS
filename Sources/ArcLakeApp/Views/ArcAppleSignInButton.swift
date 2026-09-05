import SwiftUI
import AuthenticationServices
import CryptoKit

// ═══════════════════════════════════════════════════════════════════════
// ArcAppleSignInButton
//
// Ported verbatim in behaviour from Ash Tree IDE (AppleSignInButton in
// GitHubAuth.swift), where Sign in with Apple works reliably in production.
//
// Why this instead of SwiftUI's SignInWithAppleButton:
//   • SwiftUI's wrapper resolves its own presentation context internally.
//     When it's presented from inside a sheet / confirmationDialog that is
//     mid-transition, the anchor is stale and performRequests() silently
//     no-ops — this is the "app did not respond when we attempted to Sign
//     in with Apple ID" App Review rejection.
//   • Here the Coordinator IS the delegate AND the presentation anchor
//     provider, creates the controller fresh on each tap, retains it
//     strongly for the lifetime of the request, and always resolves the
//     LIVE key window at presentation time.
//
// Each button instance owns its own coordinator and controller, so there
// is no shared singleton state to get stuck between attempts.
// ═══════════════════════════════════════════════════════════════════════

struct ArcAppleSignInButton: UIViewRepresentable {
    let onRequest:    (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    /// .white matches Arc Lake's dark welcome screen (same as Ash Tree IDE).
    var style: ASAuthorizationAppleIDButton.Style = .white
    var type:  ASAuthorizationAppleIDButton.ButtonType = .signIn

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: style)
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.tapped),
                         for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject,
                             ASAuthorizationControllerDelegate,
                             ASAuthorizationControllerPresentationContextProviding {
        let parent: ArcAppleSignInButton
        // Strong reference — a local would be deallocated before the
        // delegate callbacks fire, which silently kills the request.
        private var controller: ASAuthorizationController?

        init(parent: ArcAppleSignInButton) { self.parent = parent }

        @objc func tapped() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            parent.onRequest(request)                 // scopes + nonce set by caller
            let ctrl = ASAuthorizationController(authorizationRequests: [request])
            ctrl.delegate                    = self
            ctrl.presentationContextProvider = self
            controller = ctrl                          // retain
            ctrl.performRequests()
        }

        // Always resolve the LIVE key window — correct from any presentation
        // context, including from inside a sheet that is still dismissing.
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? UIWindow()
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithAuthorization auth: ASAuthorization) {
            self.controller = nil
            parent.onCompletion(.success(auth))
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithError error: Error) {
            self.controller = nil
            parent.onCompletion(.failure(error))
        }
    }
}

// MARK: — Nonce helpers (same construction as Ash Tree IDE)

enum ArcAppleNonce {
    /// Cryptographically random nonce string.
    static func generate(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for r in randoms {
                guard remaining > 0, r < charset.count else { continue }
                result += String(charset[charset.index(charset.startIndex, offsetBy: Int(r))])
                remaining -= 1
            }
        }
        return result
    }

    /// SHA256 hex digest — what gets attached to the request.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

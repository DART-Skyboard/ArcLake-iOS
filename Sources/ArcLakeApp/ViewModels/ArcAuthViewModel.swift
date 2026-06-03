import SwiftUI
import AuthenticationServices

// MARK: — ArcAuthViewModel (Fruta pattern)
// Follows Apple's canonical Sign in with Apple implementation exactly:
// 1. On launch: check keychain for saved user ID → getCredentialState → skip login if .authorized
// 2. performExistingAccountSetupFlows: checks Apple ID + iCloud Keychain password silently
// 3. Only show login screen when truly needed

@MainActor
public final class ArcAuthViewModel: NSObject, ObservableObject {

    // MARK: — State
    @Published public var isSignedIn      = false
    @Published public var isGuest         = false
    @Published public var githubConnected = false
    @Published public var username        = ""
    @Published public var githubUsername  = ""
    @Published public var appleUserId     = ""
    @Published public var error: String?  = nil
    @Published public var deviceFlowCode: ArcDeviceFlowDisplay? = nil
    @Published public var savedAppleAccounts:  [ArcSavedAccount] = []
    @Published public var savedGitHubAccounts: [ArcSavedAccount] = []

    private let githubClientId = "Ov23li2K0njEqO1WTSdD"
    private let keychainKey    = "autumn_apple_user_id"
    private let displayNameKey = "arc_apple_display_name"

    // MARK: — Launch restore (Fruta pattern)
    // Called from .onAppear — silently restores session or shows login
    public func restoreSession() {
        loadArcSavedAccounts()

        // Restore GitHub first (always works from keychain)
        if let pat = KeychainHelper.load(key: "arc_github_pat"), !pat.isEmpty {
            Task { await ArcGitHubClient.shared.setToken(pat) }
            let ghUser = KeychainHelper.load(key: "arc_github_username") ?? ""
            if !ghUser.isEmpty {
                githubConnected = true
                githubUsername  = ghUser
            }
        }

        // Check saved Apple credential state
        guard let savedUID = KeychainHelper.load(key: keychainKey),
              !savedUID.isEmpty else {
            // No saved credential — check for existing accounts silently
            performExistingAccountSetupFlows()
            return
        }

        // Verify the credential is still valid (Fruta: .authorized or .transferred)
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: savedUID) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized, .transferred:
                    // Still valid — restore session immediately
                    self.appleUserId = savedUID
                    self.username    = KeychainHelper.load(key: self.displayNameKey) ?? "User"
                    self.isSignedIn  = true
                    self.isGuest     = false
                    Task { await ArcVaultService.shared.setup(
                        githubUsername: self.githubConnected ? self.githubUsername : nil) }
                case .revoked, .notFound:
                    // Credential revoked — clear and show login
                    KeychainHelper.delete(key: self.keychainKey)
                    KeychainHelper.delete(key: self.displayNameKey)
                    self.performExistingAccountSetupFlows()
                @unknown default:
                    self.performExistingAccountSetupFlows()
                }
            }
        }
    }

    // MARK: — performExistingAccountSetupFlows (Fruta pattern)
    // Silently checks for BOTH Apple ID credential AND iCloud Keychain password
    // If found, completes silently without showing the login UI
    public func performExistingAccountSetupFlows() {
        let requests: [ASAuthorizationRequest] = [
            ASAuthorizationAppleIDProvider().createRequest(),
            ASAuthorizationPasswordProvider().createRequest()
        ]
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate                    = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: — Explicit Sign in with Apple (user-initiated)
    public func signInWithApple() {
        error = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                    = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: — Switch Apple account
    public func switchAppleAccount(to account: ArcSavedAccount) {
        appleUserId = account.id
        username    = account.displayName
        KeychainHelper.save(key: keychainKey,      value: account.id)
        KeychainHelper.save(key: displayNameKey,   value: account.displayName)
        isSignedIn = true; isGuest = false
        Task { await ArcVaultService.shared.setup(
            githubUsername: githubConnected ? githubUsername : nil) }
    }

    // MARK: — GitHub Device Flow
    public func startGitHubAuth() async {
        error = nil
        do {
            let flow = try await ArcGitHubClient.shared.startDeviceFlow(clientId: githubClientId)
            deviceFlowCode = ArcDeviceFlowDisplay(
                userCode: flow.userCode, verificationUrl: flow.verificationUri,
                deviceCode: flow.deviceCode, interval: flow.interval)
            await pollForGitHubToken(deviceCode: flow.deviceCode, interval: flow.interval)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pollForGitHubToken(deviceCode: String, interval: Int) async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            guard let token = try? await ArcGitHubClient.shared.pollDeviceFlow(
                clientId: githubClientId, deviceCode: deviceCode), !token.isEmpty else { continue }

            KeychainHelper.save(key: "arc_github_pat", value: token)
            await ArcGitHubClient.shared.setToken(token)
            let ghUser = (try? await ArcGitHubClient.shared.fetchAuthenticatedUser()) ?? "GitHub User"
            KeychainHelper.save(key: "arc_github_username", value: ghUser)

            githubConnected = true
            githubUsername  = ghUser
            deviceFlowCode  = nil
            if !isSignedIn { isSignedIn = true; username = ghUser }
            saveGitHubAccount(id: ghUser, displayName: ghUser)
            Task { await ArcVaultService.shared.setup(githubUsername: ghUser) }
            return
        }
        deviceFlowCode = nil
        error = "Authorization timed out. Please try again."
    }

    public func switchGitHubAccount(to account: ArcSavedAccount) {
        guard let token = KeychainHelper.load(key: "arc_github_pat_\(account.id)") else { return }
        KeychainHelper.save(key: "arc_github_pat", value: token)
        Task { await ArcGitHubClient.shared.setToken(token) }
        githubUsername = account.displayName; githubConnected = true
        Task { await ArcVaultService.shared.setup(githubUsername: account.displayName) }
    }

    public func disconnectGitHub() {
        githubConnected = false; githubUsername = ""
        KeychainHelper.delete(key: "arc_github_pat")
        KeychainHelper.delete(key: "arc_github_username")
    }

    // MARK: — PAT (Settings only)
    // PAT not used in ArcLake standalone app
        error = nil
        KeychainHelper.save(key: "arc_github_pat", value: pat)
        Task { await ArcGitHubClient.shared.setToken(pat) }
        githubConnected = true; githubUsername = "dartsolarpunk"
        if !isSignedIn { isSignedIn = true; username = "dartsolarpunk" }
        Task { await ArcVaultService.shared.setup(githubUsername: "dartsolarpunk") }
    }

    // MARK: — Guest
    public func continueAsGuest() {
        isGuest = true; isSignedIn = true; username = "Guest"; error = nil
        Task { await ArcVaultService.shared.setup(githubUsername: nil) }
    }

    // MARK: — Sign out
    public func signOut() {
        isSignedIn = false; isGuest = false; githubConnected = false
        username = ""; githubUsername = ""; appleUserId = ""
        deviceFlowCode = nil; error = nil
        KeychainHelper.delete(key: keychainKey)
        KeychainHelper.delete(key: displayNameKey)
        KeychainHelper.delete(key: "arc_github_pat")
        KeychainHelper.delete(key: "arc_github_username")
    }

    @AppStorage("policy_accepted_v1") public var hasAcceptedPolicy = false
    public func acceptPolicy() { hasAcceptedPolicy = true }

    // MARK: — Multi-account persistence
    private func saveGitHubAccount(id: String, displayName: String) {
        if !savedGitHubAccounts.contains(where: { $0.id == id }) {
            savedGitHubAccounts.append(ArcSavedAccount(id: id, displayName: displayName))
            persistAccounts()
        }
        if let token = KeychainHelper.load(key: "arc_github_pat") {
            KeychainHelper.save(key: "arc_github_pat_\(id)", value: token)
        }
    }

    private func loadArcSavedAccounts() {
        if let d = UserDefaults.standard.data(forKey: "arc_saved_github"),
           let a = try? JSONDecoder().decode([ArcSavedAccount].self, from: d) { savedGitHubAccounts = a }
        if let d = UserDefaults.standard.data(forKey: "arc_saved_apple"),
           let a = try? JSONDecoder().decode([ArcSavedAccount].self, from: d) { savedAppleAccounts = a }
    }

    private func persistAccounts() {
        if let d = try? JSONEncoder().encode(savedGitHubAccounts) {
            UserDefaults.standard.set(d, forKey: "arc_saved_github")
        }
    }
}

// MARK: — ASAuthorization delegates (exact Fruta pattern)
extension ArcAuthViewModel:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        switch authorization.credential {
        case let appleID as ASAuthorizationAppleIDCredential:
            let uid = appleID.user

            // Full name only available on FIRST sign-in — fall back to saved name
            let first   = appleID.fullName?.givenName ?? ""
            let last    = appleID.fullName?.familyName ?? ""
            let newName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            let display = newName.isEmpty
                ? (KeychainHelper.load(key: displayNameKey) ?? "User")
                : newName

            // Persist to keychain
            KeychainHelper.save(key: keychainKey,    value: uid)
            KeychainHelper.save(key: displayNameKey, value: display)

            // Save to multi-account list
            if !savedAppleAccounts.contains(where: { $0.id == uid }) {
                savedAppleAccounts.append(ArcSavedAccount(id: uid, displayName: display))
                if let d = try? JSONEncoder().encode(savedAppleAccounts) {
                    UserDefaults.standard.set(d, forKey: "arc_saved_apple")
                }
            }

            appleUserId = uid; username = display
            isSignedIn = true; isGuest = false; error = nil
            Task { await ArcVaultService.shared.setup(
                githubUsername: githubConnected ? githubUsername : nil) }

        case let password as ASPasswordCredential:
            // iCloud Keychain — sign in silently with existing credentials
            username   = password.user
            isSignedIn = true; isGuest = false; error = nil

        default:
            break
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let asErr = error as? ASAuthorizationError
        // .canceled and .unknown (1001) are not real errors — user dismissed or
        // performExistingAccountSetupFlows found no credential. Ignore silently.
        switch asErr?.code {
        case .canceled, .unknown:
            return
        default:
            self.error = error.localizedDescription
        }
    }
}

// MARK: — Models
public struct ArcDeviceFlowDisplay {
    public let userCode: String
    public let verificationUrl: String
    public let deviceCode: String
    public let interval: Int
}

public struct ArcSavedAccount: Codable, Identifiable {
    public let id: String
    public let displayName: String
}

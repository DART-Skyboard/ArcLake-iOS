import SwiftUI
import AuthenticationServices

// MARK: — ArcAuthViewModel (Fruta pattern)
// Follows Apple's canonical Sign in with Apple implementation exactly:
// 1. On launch: check keychain for saved user ID → getCredentialState → skip login if .authorized
// 2. performExistingAccountSetupFlows: checks Apple ID + iCloud Keychain password silently
// 3. Only show login screen when truly needed

@MainActor
public final class ArcAuthViewModel: NSObject, ObservableObject {
    // Retain the controller so it's not deallocated before the delegate fires
    private var appleAuthController: ASAuthorizationController?
    private var googleSignInCompletion: ((Bool) -> Void)?

    // MARK: — State
    @Published public var isSignedIn      = false
    @Published public var isGuest         = false
    @Published public var githubConnected = false
    @Published public var username        = ""
    @Published public var githubUsername  = ""
    @Published public var githubAvatarURL: URL? = nil
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

        // Restore GitHub silently — token in keychain means already authorized,
        // never show OAuth flow again on relaunch
        if let pat = KeychainHelper.load(key: "arc_github_pat"), !pat.isEmpty {
            Task {
                await ArcGitHubClient.shared.setToken(pat)
                // Verify token still valid
                if let user = try? await ArcGitHubClient.shared.fetchAuthenticatedUser() {
                    KeychainHelper.save(key: "arc_github_username", value: user)
                    await MainActor.run {
                        githubConnected = true
                        githubUsername  = user
                        if !isSignedIn {
                            isSignedIn = true
                            username   = user
                        }
                    }
                }
            }
            let ghUser = KeychainHelper.load(key: "arc_github_username") ?? ""
            if !ghUser.isEmpty {
                githubConnected = true
                githubUsername  = ghUser
                if !isSignedIn { isSignedIn = true; username = ghUser }
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
        appleAuthController = controller   // retain — prevents dealloc before delegate
        controller.performRequests()
    }

    // MARK: — Explicit Sign in with Apple (user-initiated)
    // signInWithApple() is called via SignInWithAppleButton's onRequest closure.
    // The button handles presentation — we configure the request here.
    public func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        error = nil
        request.requestedScopes = [.fullName, .email]
        // No nonce — only needed for server-side JWT verification (Firebase etc.)
    }

    // Called by SwiftUI SignInWithAppleButton onCompletion
    public func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            // Process directly without routing through ASAuthorizationController delegate
            guard let appleID = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let uid     = appleID.user
            let first   = appleID.fullName?.givenName ?? ""
            let last    = appleID.fullName?.familyName ?? ""
            let newName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            let display = newName.isEmpty
                ? (KeychainHelper.load(key: displayNameKey) ?? "Apple User")
                : newName

            KeychainHelper.save(key: keychainKey,    value: uid)
            KeychainHelper.save(key: displayNameKey, value: display)

            if !savedAppleAccounts.contains(where: { $0.id == uid }) {
                savedAppleAccounts.append(ArcSavedAccount(id: uid, displayName: display))
                if let d = try? JSONEncoder().encode(savedAppleAccounts) {
                    UserDefaults.standard.set(d, forKey: "arc_saved_apple")
                }
            }

            appleUserId = uid; username = display
            isSignedIn  = true; isGuest = false; error = nil
            Task { await ArcVaultService.shared.setup(
                githubUsername: githubConnected ? githubUsername : nil) }

        case .failure(let err):
            let asErr = err as? ASAuthorizationError
            switch asErr?.code {
            case .canceled, .unknown: break  // user dismissed — not an error
            default: self.error = "Apple Sign-In failed: \(err.localizedDescription)"
            }
        }
    }

    // Legacy — kept for compatibility
    public func signInWithApple() {
        error = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                    = self
        controller.presentationContextProvider = self
        // Retain controller — local vars get deallocated before delegate fires
        appleAuthController = controller
        controller.performRequests()
    }

    // MARK: — Google Sign-In
    // Uses Google Sign-In SDK (GoogleSignIn-iOS). If SDK not yet added to project,
    // this compiles as a no-op stub. Add via SPM: https://github.com/google/GoogleSignIn-iOS
    @Published public var googleConnected = false
    @Published public var googleEmail = ""
    @Published public var savedGoogleAccounts: [ArcSavedAccount] = []

    public func signInWithGoogle() {
        #if canImport(GoogleSignIn)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { self.error = "Google Sign-In: no root view controller"; return }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, err in
            guard let self else { return }
            if let err {
                DispatchQueue.main.async { self.error = err.localizedDescription }
                return
            }
            guard let user = result?.user,
                  let profile = user.profile else { return }
            let email = profile.email
            let name  = profile.name
            DispatchQueue.main.async {
                self.googleConnected = true
                self.googleEmail = email
                if !self.savedGoogleAccounts.contains(where: { $0.id == email }) {
                    self.savedGoogleAccounts.append(ArcSavedAccount(id: email, displayName: name))
                }
                KeychainHelper.save(key: "arc_google_email", value: email)
                KeychainHelper.save(key: "arc_google_name",  value: name)
                if !self.isSignedIn { self.isSignedIn = true; self.username = name }
            }
        }
        #else
        self.error = "Google Sign-In SDK not yet installed. Add via SPM: github.com/google/GoogleSignIn-iOS"
        #endif
    }

    public func signOutGoogle() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        googleConnected = false
        googleEmail = ""
        KeychainHelper.delete(key: "arc_google_email")
        KeychainHelper.delete(key: "arc_google_name")
    }

    public func restoreGoogleSession() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, err in
            guard let self, let user, err == nil,
                  let profile = user.profile else { return }
            DispatchQueue.main.async {
                self.googleConnected = true
                self.googleEmail = profile.email
                if !self.isSignedIn { self.isSignedIn = true; self.username = profile.name }
            }
        }
        #else
        if let email = KeychainHelper.load(key: "arc_google_email"),
           let name  = KeychainHelper.load(key: "arc_google_name") {
            googleConnected = true; googleEmail = email
            savedGoogleAccounts = [ArcSavedAccount(id: email, displayName: name)]
            if !isSignedIn { isSignedIn = true; username = name }
        }
        #endif
    }

    // MARK: — Switch Apple account
    // Verify credential state before switching (handles expired sessions)
    public func switchAppleAccount(to account: ArcSavedAccount) {
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: account.id) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized, .transferred:
                    self.appleUserId = account.id
                    self.username    = account.displayName
                    KeychainHelper.save(key: self.keychainKey,    value: account.id)
                    KeychainHelper.save(key: self.displayNameKey, value: account.displayName)
                    self.isSignedIn = true; self.isGuest = false; self.error = nil
                    Task { await ArcVaultService.shared.setup(
                        githubUsername: self.githubConnected ? self.githubUsername : nil) }
                case .revoked, .notFound:
                    // Session expired — remove stale account, prompt re-auth
                    self.savedAppleAccounts.removeAll { $0.id == account.id }
                    if let d = try? JSONEncoder().encode(self.savedAppleAccounts) {
                        UserDefaults.standard.set(d, forKey: "arc_saved_apple")
                    }
                    self.error = "Apple ID session expired — please sign in again"
                    self.signInWithApple()
                @unknown default: break
                }
            }
        }
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
            // Fetch GitHub avatar
            Task { await self.fetchGitHubAvatar(for: ghUser) }
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

    // MARK: — PAT not used in ArcLake standalone app


    // MARK: — resumeStoredGitHubSession
    // Called from WelcomeView "Continue as [user]" button.
    // Token already in Keychain — instant re-entry, zero Device Flow.
    public func resumeStoredGitHubSession() {
        guard let token = KeychainHelper.load(key: "arc_github_pat"), !token.isEmpty else {
            Task { await startGitHubAuth() }
            return
        }
        let cachedUser = KeychainHelper.load(key: "arc_github_username") ?? "GitHub User"
        // Instant local restore — UI unblocks immediately
        isSignedIn      = true
        isGuest         = false
        githubConnected = true
        githubUsername  = cachedUser
        username        = cachedUser
        error           = nil
        Task {
            await ArcGitHubClient.shared.setToken(token)
            // Background verify — refresh username if token still valid
            if let fresh = try? await ArcGitHubClient.shared.fetchAuthenticatedUser() {
                KeychainHelper.save(key: "arc_github_username", value: fresh)
                await MainActor.run { self.githubUsername = fresh; self.username = fresh }
                await ArcVaultService.shared.setup(githubUsername: fresh)
            } else {
                // Token expired / revoked — evict and show error
                await MainActor.run {
                    KeychainHelper.delete(key: "arc_github_pat")
                    KeychainHelper.delete(key: "arc_github_username")
                    self.githubConnected = false
                    self.isSignedIn      = false
                    self.error = "GitHub session expired — please reconnect."
                }
            }
        }
    }

    // MARK: — GitHub Avatar
    public func fetchGitHubAvatar(for username: String) async {
        // GitHub API: GET /users/{username} → avatar_url
        guard let url = URL(string: "https://api.github.com/users/\(username)") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = KeychainHelper.load(key: "arc_github_pat") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let avatarStr = json["avatar_url"] as? String,
              let avatarURL = URL(string: avatarStr) else { return }
        await MainActor.run {
            self.githubAvatarURL = avatarURL
            // Cache the URL string
            KeychainHelper.save(key: "arc_github_avatar_url", value: avatarStr)
        }
    }

    // MARK: — Guest
    public func continueAsGuest() {
        isGuest = true; isSignedIn = true; username = "Guest"; error = nil
        Task { await ArcVaultService.shared.setup(githubUsername: nil) }
    }

    // MARK: — Sign out
    public func signOut() {
        // Clear SESSION state only — keep Keychain tokens so "Continue as [user]"
        // appears on the welcome screen. Tokens are only deleted on revocation.
        isSignedIn = false; isGuest = false; githubConnected = false
        username = ""; githubUsername = ""; appleUserId = ""
        deviceFlowCode = nil; error = nil
        // Keep: arc_github_pat, arc_github_username — enables instant re-login
        // Keep: Apple keychainKey / displayNameKey — Fruta restore handles those
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
        // Must run on main thread — always true since ArcAuthViewModel is @MainActor
        // Walk all window scenes to find the one with a key window
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows where window.isKeyWindow { return window }
        }
        // Fallback: any visible window
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows where !window.isHidden { return window }
        }
        // Should never reach here in a normal app lifecycle
        return UIApplication.shared.windows.first ?? UIWindow()
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


// MARK: — KeychainHelper (local to ArcLake)
struct KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data
        ]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(key: String) {
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}






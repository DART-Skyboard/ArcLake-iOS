import SwiftUI
import AuthenticationServices

// MARK: — ArcAuthViewModel
// Mirrors Autumn's AuthViewModel for ArcLake.
// Shares the same iCloud container (iCloud.com.dartmeadow.autumn)
// and the same Autumn-Ash vault — ArcLake data goes in ArcLake/ subfolder.

@MainActor
public final class ArcAuthViewModel: NSObject, ObservableObject {

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

    // MARK: — Continue as Guest
    public func continueAsGuest() {
        isGuest    = true
        isSignedIn = true
        username   = "Guest"
        error      = nil
        Task { await ArcVaultService.shared.setup(githubUsername: nil) }
    }

    // MARK: — Sign in with Apple
    public func signInWithApple() {
        error = nil
        let provider   = ASAuthorizationAppleIDProvider()
        let request    = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate                    = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    public func switchAppleAccount(to account: ArcSavedAccount) {
        appleUserId = account.id
        username    = account.displayName
        KeychainHelper.save(key: "arc_apple_user_id",      value: account.id)
        KeychainHelper.save(key: "arc_apple_display_name", value: account.displayName)
        isSignedIn = true; isGuest = false
        Task { await ArcVaultService.shared.setup(githubUsername: githubConnected ? githubUsername : nil) }
    }

    public func restoreSession() {
        let uid = KeychainHelper.load(key: "arc_apple_user_id") ?? ""
        if !uid.isEmpty {
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: uid) { [weak self] state, _ in
                DispatchQueue.main.async {
                    guard state == .authorized else { return }
                    self?.appleUserId = uid
                    self?.isSignedIn  = true
                    self?.username    = KeychainHelper.load(key: "arc_apple_display_name") ?? "User"
                    Task { await ArcVaultService.shared.setup(githubUsername: self?.githubUsername) }
                }
            }
        }
        // Restore GitHub
        if let pat = KeychainHelper.load(key: "arc_github_pat"), !pat.isEmpty {
            Task { await ArcGitHubClient.shared.setToken(pat) }
            githubConnected = true
            githubUsername  = KeychainHelper.load(key: "arc_github_username") ?? ""
        }
        loadSavedAccounts()
    }

    // MARK: — GitHub Device Flow
    public func startGitHubAuth() async {
        error = nil
        do {
            let flow = try await ArcGitHubClient.shared.startDeviceFlow(clientId: githubClientId)
            deviceFlowCode = ArcDeviceFlowDisplay(
                userCode: flow.userCode,
                verificationUrl: flow.verificationUri,
                deviceCode: flow.deviceCode,
                interval: flow.interval)
            await pollGitHub(deviceCode: flow.deviceCode, interval: flow.interval)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pollGitHub(deviceCode: String, interval: Int) async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            if let token = try? await ArcGitHubClient.shared.pollDeviceFlow(
                clientId: githubClientId, deviceCode: deviceCode), !token.isEmpty {
                KeychainHelper.save(key: "arc_github_pat", value: token)
                await ArcGitHubClient.shared.setToken(token)
                let gh = (try? await ArcGitHubClient.shared.fetchAuthenticatedUser()) ?? "GitHub User"
                KeychainHelper.save(key: "arc_github_username", value: gh)
                githubConnected = true
                githubUsername  = gh
                deviceFlowCode  = nil
                if !isSignedIn { isSignedIn = true; username = gh }
                saveGitHubAccount(id: gh, displayName: gh, token: token)
                Task { await ArcVaultService.shared.setup(githubUsername: gh) }
                return
            }
        }
        deviceFlowCode = nil
        error = "Authorization timed out."
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
    }

    // MARK: — Sign out
    public func signOut() {
        isSignedIn = false; isGuest = false; githubConnected = false
        username = ""; githubUsername = ""; appleUserId = ""
        deviceFlowCode = nil; error = nil
        KeychainHelper.delete(key: "arc_apple_user_id")
        KeychainHelper.delete(key: "arc_github_pat")
    }

    // MARK: — Multi-account helpers
    private func saveGitHubAccount(id: String, displayName: String, token: String) {
        if !savedGitHubAccounts.contains(where: { $0.id == id }) {
            savedGitHubAccounts.append(ArcSavedAccount(id: id, displayName: displayName))
            persistAccounts()
        }
        KeychainHelper.save(key: "arc_github_pat_\(id)", value: token)
    }

    private func loadSavedAccounts() {
        if let d = UserDefaults.standard.data(forKey: "arc_saved_github"),
           let a = try? JSONDecoder().decode([ArcSavedAccount].self, from: d) {
            savedGitHubAccounts = a
        }
        if let d = UserDefaults.standard.data(forKey: "arc_saved_apple"),
           let a = try? JSONDecoder().decode([ArcSavedAccount].self, from: d) {
            savedAppleAccounts = a
        }
    }

    private func persistAccounts() {
        if let d = try? JSONEncoder().encode(savedGitHubAccounts) {
            UserDefaults.standard.set(d, forKey: "arc_saved_github")
        }
    }
}

// MARK: — ASAuthorization delegates
extension ArcAuthViewModel:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        let uid     = cred.user
        let first   = cred.fullName?.givenName ?? ""
        let last    = cred.fullName?.familyName ?? ""
        let full    = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let display = full.isEmpty
            ? (KeychainHelper.load(key: "arc_apple_display_name") ?? "User")
            : full

        KeychainHelper.save(key: "arc_apple_user_id",      value: uid)
        KeychainHelper.save(key: "arc_apple_display_name", value: display)

        if !savedAppleAccounts.contains(where: { $0.id == uid }) {
            savedAppleAccounts.append(ArcSavedAccount(id: uid, displayName: display))
            if let d = try? JSONEncoder().encode(savedAppleAccounts) {
                UserDefaults.standard.set(d, forKey: "arc_saved_apple")
            }
        }
        appleUserId = uid; username = display
        isSignedIn = true; isGuest = false; error = nil
        Task { await ArcVaultService.shared.setup(githubUsername: githubConnected ? githubUsername : nil) }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError err: Error
    ) {
        let asErr = err as? ASAuthorizationError
        if asErr?.code == .canceled { return }
        error = err.localizedDescription
    }
}

// MARK: — Keychain helper (local to ArcLake — avoids AutumnServices dependency)
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

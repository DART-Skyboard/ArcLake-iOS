import SwiftUI
import Foundation
import AuthenticationServices
import UIKit
import Network

// MARK: — Arc Lake Diagnostics
// Central, exportable diagnostic log. Two jobs:
//   1. Structured logging (level + category + full error detail) from anywhere
//      in the app, so failures leave a trail instead of a print() nobody sees.
//   2. captureEnvironment() — a one-shot snapshot of everything that actually
//      determines whether platform features (esp. Sign in with Apple) can work
//      on THIS device and THIS build. That includes reading the app's OWN
//      embedded provisioning profile at runtime, which is the only way from
//      inside the app to confirm an entitlement genuinely survived export
//      signing rather than just being present in the source .entitlements file.
public enum ArcLogLevel: String, CaseIterable {
    case debug = "DEBUG", info = "INFO", success = "OK", warning = "WARN", error = "ERROR"

    public var color: Color {
        switch self {
        case .debug:   return .white.opacity(0.35)
        case .info:    return .white.opacity(0.75)
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

public struct ArcDiagnosticEntry: Identifiable {
    public let id = UUID()
    public let timestamp = Date()
    public let level: ArcLogLevel
    public let category: String
    public let message: String
    public let detail: String?

    public var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
    public var plainText: String {
        var s = "[\(timeString)] [\(level.rawValue)] [\(category)] \(message)"
        if let d = detail, !d.isEmpty {
            s += "\n" + d.split(separator: "\n").map { "        \($0)" }.joined(separator: "\n")
        }
        return s
    }
}

@MainActor
public final class ArcDiagnostics: ObservableObject {
    public static let shared = ArcDiagnostics()
    private init() {}

    @Published public private(set) var entries: [ArcDiagnosticEntry] = []
    private let maxEntries = 1500

    // MARK: — Logging
    public func log(_ level: ArcLogLevel, _ category: String, _ message: String, detail: String? = nil) {
        let e = ArcDiagnosticEntry(level: level, category: category, message: message, detail: detail)
        entries.insert(e, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        print("[\(category)] \(level.rawValue): \(message)" + (detail.map { "\n\($0)" } ?? ""))
    }

    public func info(_ c: String, _ m: String, detail: String? = nil)    { log(.info, c, m, detail: detail) }
    public func success(_ c: String, _ m: String, detail: String? = nil) { log(.success, c, m, detail: detail) }
    public func warn(_ c: String, _ m: String, detail: String? = nil)    { log(.warning, c, m, detail: detail) }
    public func error(_ c: String, _ m: String, detail: String? = nil)   { log(.error, c, m, detail: detail) }

    /// Log an Error with its FULL structure — domain, code, userInfo, and the
    /// whole NSUnderlyingError chain. The chain matters: ASAuthorizationError
    /// 1000 is a generic wrapper, and the actionable cause (an
    /// AKAuthenticationError) is usually nested inside it.
    public func logError(_ category: String, _ message: String, error err: Error) {
        log(.error, category, message, detail: Self.describe(err))
    }

    public static func describe(_ err: Error, depth: Int = 0) -> String {
        let ns = err as NSError
        let pad = String(repeating: "  ", count: depth)
        var out = "\(pad)domain: \(ns.domain)\n\(pad)code: \(ns.code)\n\(pad)description: \(ns.localizedDescription)"
        let skip = [NSUnderlyingErrorKey, NSLocalizedDescriptionKey]
        let extras = ns.userInfo.filter { !skip.contains($0.key) }
        if !extras.isEmpty {
            out += "\n\(pad)userInfo:"
            for (k, v) in extras.sorted(by: { $0.key < $1.key }) {
                out += "\n\(pad)  \(k) = \(v)"
            }
        }
        if depth < 5, let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            out += "\n\(pad)underlying →\n" + describe(u, depth: depth + 1)
        }
        return out
    }

    public func clear() { entries.removeAll() }

    // MARK: — Environment snapshot
    /// Captures everything that determines whether platform features can work
    /// here. Run this before reproducing a bug so the log carries context.
    public func captureEnvironment() {
        log(.info, "DIAG", "───── Environment snapshot ─────")

        // App identity — the runtime bundle ID is what Apple's auth daemon
        // actually checks against the App ID that has Sign in with Apple enabled.
        let b = Bundle.main
        let bundleID = b.bundleIdentifier ?? "(nil)"
        let ver   = b.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = b.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        log(.info, "APP", "Arc Lake \(ver) (\(build))", detail: "bundleID: \(bundleID)")

        // Device / OS
        let dev = UIDevice.current
        log(.info, "DEVICE", "\(dev.systemName) \(dev.systemVersion)",
            detail: "model: \(dev.model)\nname: \(Self.hardwareModel())")

        // Distribution channel — sandbox receipt = TestFlight, "MAS" = App Store
        log(.info, "APP", "Install source: \(Self.installSource())")

        // iCloud — Sign in with Apple requires a signed-in iCloud account
        if FileManager.default.ubiquityIdentityToken != nil {
            log(.success, "ICLOUD", "iCloud account is signed in")
        } else {
            log(.warning, "ICLOUD", "No iCloud identity token — device may not be signed into iCloud (Sign in with Apple requires it)")
        }

        // THE important one: does the SHIPPED binary's provisioning profile
        // actually carry the entitlements? Source .entitlements being correct
        // proves nothing if export re-signing dropped them.
        inspectProvisioningProfile()

        log(.info, "DIAG", "───── End snapshot ─────")
    }

    /// Reads the app's own embedded.mobileprovision and reports its entitlements.
    private func inspectProvisioningProfile() {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            log(.warning, "PROFILE", "No embedded.mobileprovision found",
                detail: "Normal for App Store builds (Apple strips it) and simulator runs. Expected present in TestFlight/ad-hoc builds.")
            return
        }
        // The file is CMS-signed; the plist payload sits in plain text inside it.
        guard let start = data.range(of: Data("<?xml".utf8))?.lowerBound,
              let end = data.range(of: Data("</plist>".utf8))?.upperBound,
              let plist = try? PropertyListSerialization.propertyList(
                    from: data.subdata(in: start..<end), options: [], format: nil) as? [String: Any]
        else {
            log(.warning, "PROFILE", "embedded.mobileprovision present but could not be parsed")
            return
        }

        let name = plist["Name"] as? String ?? "?"
        let uuid = plist["UUID"] as? String ?? "?"
        let teamID = (plist["TeamIdentifier"] as? [String])?.first ?? "?"
        var detail = "name: \(name)\nuuid: \(uuid)\nteam: \(teamID)"
        if let exp = plist["ExpirationDate"] as? Date { detail += "\nexpires: \(exp)" }
        log(.info, "PROFILE", "Embedded provisioning profile", detail: detail)

        guard let ents = plist["Entitlements"] as? [String: Any] else {
            log(.error, "PROFILE", "Profile has NO Entitlements dictionary")
            return
        }
        log(.info, "PROFILE", "Profile entitlement keys (\(ents.count))",
            detail: ents.keys.sorted().joined(separator: "\n"))

        // Sign in with Apple specifically
        if let siwa = ents["com.apple.developer.applesignin"] {
            log(.success, "SIWA", "applesignin entitlement IS present in the shipped profile",
                detail: "value: \(siwa)")
        } else {
            log(.error, "SIWA", "applesignin entitlement is MISSING from the shipped profile",
                detail: "This is the actual cause of ASAuthorizationError 1000 — the running build was signed without Sign in with Apple, regardless of what the source .entitlements file says.")
        }

        // App ID prefix vs bundle ID — a mismatch here breaks entitlement matching
        if let appID = ents["application-identifier"] as? String {
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let matches = appID.hasSuffix(bundleID)
            log(matches ? .success : .error, "SIWA",
                matches ? "application-identifier matches the runtime bundle ID"
                        : "application-identifier does NOT match the runtime bundle ID",
                detail: "profile application-identifier: \(appID)\nruntime bundleID: \(bundleID)")
        }
    }

    /// Async because getCredentialState is a network/daemon call.
    public func checkAppleCredentialState(userID: String?) {
        guard let userID, !userID.isEmpty else {
            log(.info, "SIWA", "No saved Apple user ID to check credential state for")
            return
        }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, err in
            Task { @MainActor in
                guard let self else { return }
                if let err { self.logError("SIWA", "getCredentialState failed", error: err); return }
                let desc: (ArcLogLevel, String)
                switch state {
                case .authorized:  desc = (.success, "authorized")
                case .revoked:     desc = (.warning, "revoked — user disabled it for this app")
                case .notFound:    desc = (.info,    "notFound — no credential yet (expected before first sign-in)")
                case .transferred: desc = (.info,    "transferred")
                @unknown default:  desc = (.warning, "unknown state")
                }
                self.log(desc.0, "SIWA", "Apple credential state: \(desc.1)")
            }
        }
    }

    // MARK: — Export
    public func exportText() -> String {
        let dev = UIDevice.current
        let b = Bundle.main
        var header = """
        ═══════════════════════════════════════════════
        Arc Lake — Diagnostic Log
        Exported: \(ISO8601DateFormatter().string(from: Date()))
        App: \(b.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") \
        (\(b.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
        Bundle: \(b.bundleIdentifier ?? "?")
        Device: \(Self.hardwareModel()) · \(dev.systemName) \(dev.systemVersion)
        Entries: \(entries.count)
        ═══════════════════════════════════════════════

        """
        // Oldest-first reads more naturally in a file than newest-first.
        header += entries.reversed().map(\.plainText).joined(separator: "\n")
        return header
    }

    /// Writes the log to a temp .txt and returns the URL for a share sheet.
    public func exportToFile() -> URL? {
        let name = "ArcLake-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try exportText().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            logError("DIAG", "Failed to write diagnostic file", error: error)
            return nil
        }
    }

    // MARK: — Helpers
    static func hardwareModel() -> String {
        var sysinfo = utsname(); uname(&sysinfo)
        let raw = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "?" }
        }
        return raw
    }

    static func installSource() -> String {
        guard let receipt = Bundle.main.appStoreReceiptURL else { return "unknown (no receipt URL)" }
        if receipt.lastPathComponent == "sandboxReceipt" { return "TestFlight (sandbox receipt)" }
        if FileManager.default.fileExists(atPath: receipt.path) { return "App Store" }
        return "Development / direct install (no receipt)"
    }
}

import Foundation

// ═══════════════════════════════════════════════════════════════════
// ArcAshSync — mirrors session .ash files to a remote store.
//
//   GitHub signed-in  → private repo `arclake-ash`
//                          sessions/<sessionId>.ash
//                          assets/<sha256>.<ext>
//   Apple (no GitHub) → iCloud vault   ArcLake/sessions/<sessionId>.ash
//                                      ArcLake/models/<sha256>.<ext>
//                       (local Documents fallback when iCloud is absent)
//
// Conflict policy (revision counter + last-writer-wins WITH a copy):
//   • remote unchanged since our last sync         → fast-forward push
//   • remote changed, local unchanged since sync    → adopt remote
//   • BOTH changed                                  → the side with the later
//     `updatedAt` wins; the loser is preserved as a forked session
//     ("<name> (conflict …)") with a fresh sessionId — nothing is lost.
// ═══════════════════════════════════════════════════════════════════

public enum ArcAshSyncError: Error, CustomStringConvertible {
    case notConfigured(String)
    case offline
    case unauthorized
    case conflict
    case rateLimited(retryAfter: Int?)
    case repoIsPublic(String)
    case tooLarge
    case http(Int, String)
    case other(String)

    public var description: String {
        switch self {
        case .notConfigured(let s): return s
        case .offline: return "Offline"
        case .unauthorized: return "GitHub access was refused — reconnect GitHub in Profile"
        case .conflict: return "Version conflict"
        case .rateLimited: return "GitHub rate limit — will retry"
        case .repoIsPublic(let r): return "Repo \(r) is public — refusing to sync project files to it"
        case .tooLarge: return "File too large to sync"
        case .http(let c, let m): return "Sync error \(c): \(m)"
        case .other(let m): return m
        }
    }

    public static func classify(_ error: Error) -> ArcAshSyncError {
        if let e = error as? ArcAshSyncError { return e }
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff,
                 .dnsLookupFailed, .secureConnectionFailed:
                return .offline
            default: return .other(u.localizedDescription)
            }
        }
        if let h = error as? ArcGitHubHTTPError {
            switch h.status {
            case 401: return .unauthorized
            case 403, 429:
                if h.retryAfter != nil || h.message.lowercased().contains("rate limit") {
                    return .rateLimited(retryAfter: h.retryAfter)
                }
                return .unauthorized
            case 409: return .conflict
            case 413: return .tooLarge
            default: return .http(h.status, h.message)
            }
        }
        return .other(error.localizedDescription)
    }
}

public struct ArcAshRemoteEntry: Sendable {
    public let id: String          // sessionId
    public let token: String?      // backend version token when known without reading the file
}

public protocol ArcAshRemote: Sendable {
    var label: String { get }
    var maxAssetBytes: Int { get }
    func prepare() async throws
    func list() async throws -> [ArcAshRemoteEntry]
    func read(sessionId: String) async throws -> (data: Data, token: String)?
    /// Throws ArcAshSyncError.conflict when `expectedToken` is stale.
    func write(sessionId: String, data: Data, expectedToken: String?) async throws -> String
    func hasAsset(sha: String, ext: String) async throws -> Bool
    func putAsset(sha: String, ext: String, fileURL: URL) async throws
    func getAsset(sha: String, ext: String, to dest: URL) async throws -> Bool
}

private func isSessionFileName(_ n: String) -> Bool {
    // <36-char uuid>.ash — excludes anything else living in the folder
    guard n.hasSuffix(".ash") else { return false }
    let stem = n.dropLast(4)
    return stem.count == 36 && stem.allSatisfy { $0.isHexDigit || $0 == "-" }
}

// MARK: — GitHub backend (private repo)
public struct ArcAshGitHubRemote: ArcAshRemote {
    public static let repoName = "arclake-ash"
    public let owner: String
    public var label: String { "github" }
    public var maxAssetBytes: Int { 25 * 1024 * 1024 }   // Contents API is capped at 100 MB; stay far below
    public init(owner: String) { self.owner = owner }

    private var gh: ArcGitHubClient { ArcGitHubClient.shared }
    private var readyKey: String { "arc_ash_repo_ready" }

    public func prepare() async throws {
        guard await gh.hasToken() else { throw ArcAshSyncError.unauthorized }
        if UserDefaults.standard.string(forKey: readyKey) == owner { return }
        if let info = try await gh.repoInfo(owner: owner, repo: Self.repoName) {
            guard info.isPrivate else { throw ArcAshSyncError.repoIsPublic("\(owner)/\(Self.repoName)") }
        } else {
            try await gh.createPrivateRepo(name: Self.repoName,
                description: "ArcLake project sessions (.ash) — private, managed by the ArcLake app")
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // let the new repo settle
        }
        UserDefaults.standard.set(owner, forKey: readyKey)
    }

    public func list() async throws -> [ArcAshRemoteEntry] {
        let items = try await gh.listDirectory(owner: owner, repo: Self.repoName, path: "sessions")
        return items.filter { isSessionFileName($0.name) }
            .map { ArcAshRemoteEntry(id: String($0.name.dropLast(4)), token: $0.sha) }
    }

    public func read(sessionId: String) async throws -> (data: Data, token: String)? {
        let path = "sessions/\(sessionId).ash"
        guard let entry = try await gh.fileEntry(owner: owner, repo: Self.repoName, path: path),
              let data = try await gh.readRaw(owner: owner, repo: Self.repoName, path: path)
        else { return nil }
        return (data, entry.sha)
    }

    public func write(sessionId: String, data: Data, expectedToken: String?) async throws -> String {
        do {
            return try await gh.putFile(owner: owner, repo: Self.repoName,
                path: "sessions/\(sessionId).ash", data: data,
                message: "arclake: sync session \(sessionId.prefix(8))", sha: expectedToken)
        } catch let e as ArcGitHubHTTPError where e.status == 409 || e.status == 422 {
            throw ArcAshSyncError.conflict
        }
    }

    public func hasAsset(sha: String, ext: String) async throws -> Bool {
        try await gh.fileEntry(owner: owner, repo: Self.repoName, path: assetPath(sha, ext)) != nil
    }

    public func putAsset(sha: String, ext: String, fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= maxAssetBytes else { throw ArcAshSyncError.tooLarge }
        do {
            _ = try await gh.putFile(owner: owner, repo: Self.repoName, path: assetPath(sha, ext),
                                     data: data, message: "arclake: asset \(sha.prefix(12))", sha: nil)
        } catch let e as ArcGitHubHTTPError where e.status == 422 {
            return   // already present (content-addressed, so identical)
        }
    }

    public func getAsset(sha: String, ext: String, to dest: URL) async throws -> Bool {
        guard let d = try await gh.readRaw(owner: owner, repo: Self.repoName, path: assetPath(sha, ext))
        else { return false }
        // Content-addressed: verify before trusting.
        guard ArcAshHash.sha256Hex(d) == sha else { return false }
        try d.write(to: dest, options: .atomic)
        return true
    }

    private func assetPath(_ sha: String, _ ext: String) -> String {
        "assets/\(ext.isEmpty ? sha : "\(sha).\(ext)")"
    }
}

// MARK: — iCloud vault backend (Apple sign-in, no GitHub)
public struct ArcAshVaultRemote: ArcAshRemote {
    public var label: String { "vault" }
    public var maxAssetBytes: Int { 512 * 1024 * 1024 }
    public init() {}

    private var vault: ArcVaultService { ArcVaultService.shared }

    public func prepare() async throws {
        guard await vault.vaultURL != nil else {
            throw ArcAshSyncError.notConfigured("iCloud vault not ready")
        }
    }

    public func list() async throws -> [ArcAshRemoteEntry] {
        let names = await vault.listNames(subfolder: .sessions)
        return names.filter { isSessionFileName($0) }
            .map { ArcAshRemoteEntry(id: String($0.dropLast(4)), token: nil) }
    }

    public func read(sessionId: String) async throws -> (data: Data, token: String)? {
        guard let d = await vault.readData(subfolder: .sessions, filename: "\(sessionId).ash") else { return nil }
        return (d, ArcAshHash.sha256Hex(d))
    }

    public func write(sessionId: String, data: Data, expectedToken: String?) async throws -> String {
        let name = "\(sessionId).ash"
        if let existing = await vault.readData(subfolder: .sessions, filename: name) {
            let cur = ArcAshHash.sha256Hex(existing)
            if expectedToken == nil || cur != expectedToken { throw ArcAshSyncError.conflict }
        } else if expectedToken != nil, await vault.fileExists(subfolder: .sessions, filename: name) {
            // placeholder not downloaded yet — don't overwrite blind
            throw ArcAshSyncError.conflict
        }
        try await vault.writeDataAtomic(subfolder: .sessions, filename: name, data: data)
        return ArcAshHash.sha256Hex(data)
    }

    public func hasAsset(sha: String, ext: String) async throws -> Bool {
        await vault.fileExists(subfolder: .models, filename: fileName(sha, ext))
    }

    public func putAsset(sha: String, ext: String, fileURL: URL) async throws {
        guard let dir = await vault.exportURL(for: .models) else {
            throw ArcAshSyncError.notConfigured("iCloud vault not ready")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(fileName(sha, ext))
        if FileManager.default.fileExists(atPath: dest.path) { return }
        try FileManager.default.copyItem(at: fileURL, to: dest)
    }

    public func getAsset(sha: String, ext: String, to dest: URL) async throws -> Bool {
        guard let dir = await vault.exportURL(for: .models) else { return false }
        let src = dir.appendingPathComponent(fileName(sha, ext))
        guard FileManager.default.fileExists(atPath: src.path) else { return false }
        guard let h = ArcAshHash.sha256Hex(fileURL: src), h.sha == sha else { return false }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        return true
    }

    private func fileName(_ sha: String, _ ext: String) -> String { ext.isEmpty ? sha : "\(sha).\(ext)" }
}

// MARK: — Engine
public struct ArcAshSyncResult {
    public var meta: ArcAshSyncMeta
    public var pushed = false
    /// Remote won: replace the local copy with this.
    public var adopt: (doc: ArcAshDocument, data: Data)? = nil
    /// The losing side of a both-changed conflict, already forked to a new sessionId.
    public var conflictCopy: ArcAshDocument? = nil
}

public enum ArcAshSyncEngine {

    static func fork(_ doc: ArcAshDocument, label: String) -> ArcAshDocument {
        var d = doc
        d.sessionId = UUID().uuidString
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        d.name = "\(doc.name) (conflict – \(label) \(stamp))"
        d.revision = 1
        d.updatedAt = ArcAshTime.iso()
        return d
    }

    /// Reconcile one session with the remote. `localData` must be the exact bytes of `local`.
    public static func syncSession(local: ArcAshDocument, localData: Data,
                                   meta startMeta: ArcAshSyncMeta,
                                   remote: ArcAshRemote) async throws -> ArcAshSyncResult {
        var meta = startMeta
        var attempts = 0
        while true {
            attempts += 1
            let rf = try await remote.read(sessionId: local.sessionId)
            do {
                guard let rf else {
                    // Not on the remote yet (or deleted there) — create it.
                    let tok = try await remote.write(sessionId: local.sessionId, data: localData, expectedToken: nil)
                    meta.token = tok; meta.revision = local.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta, pushed: true)
                }
                if rf.token == meta.token {
                    if local.revision == meta.revision {
                        return ArcAshSyncResult(meta: meta)              // nothing to do
                    }
                    let tok = try await remote.write(sessionId: local.sessionId, data: localData, expectedToken: rf.token)
                    meta.token = tok; meta.revision = local.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta, pushed: true)       // fast-forward
                }
                // The remote moved since our last sync.
                if rf.data == localData {
                    meta.token = rf.token; meta.revision = local.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta)                      // identical content
                }
                guard let remoteDoc = try? ArcAshDocument.decode(rf.data) else {
                    // Unreadable remote copy — replace it with ours.
                    let tok = try await remote.write(sessionId: local.sessionId, data: localData, expectedToken: rf.token)
                    meta.token = tok; meta.revision = local.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta, pushed: true)
                }
                if local.revision <= meta.revision {
                    // No local edits since the last sync → take the remote version.
                    meta.token = rf.token; meta.revision = remoteDoc.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta, adopt: (remoteDoc, rf.data))
                }
                // Both sides changed → last writer wins, loser preserved as a copy.
                let lt = ArcAshTime.parse(local.updatedAt) ?? .distantPast
                let rt = ArcAshTime.parse(remoteDoc.updatedAt) ?? .distantPast
                if lt >= rt {
                    let copy = fork(remoteDoc, label: "other device")
                    let tok = try await remote.write(sessionId: local.sessionId, data: localData, expectedToken: rf.token)
                    meta.token = tok; meta.revision = local.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta, pushed: true, conflictCopy: copy)
                } else {
                    let copy = fork(local, label: "this device")
                    meta.token = rf.token; meta.revision = remoteDoc.revision; meta.lastSync = ArcAshTime.iso()
                    return ArcAshSyncResult(meta: meta, adopt: (remoteDoc, rf.data), conflictCopy: copy)
                }
            } catch ArcAshSyncError.conflict {
                if attempts >= 3 { throw ArcAshSyncError.conflict }
                continue   // a write raced ours — re-read and re-decide
            }
        }
    }

    /// Fetch a session that exists remotely but not locally.
    public static func fetchNew(id: String, remote: ArcAshRemote) async throws
        -> (doc: ArcAshDocument, data: Data, token: String)? {
        guard let rf = try await remote.read(sessionId: id),
              let doc = try? ArcAshDocument.decode(rf.data) else { return nil }
        return (doc, rf.data, rf.token)
    }

    /// Upload model files referenced by the document (content-addressed, so
    /// idempotent). Files above the backend's limit stay reference-only.
    public static func uploadAssets(_ refs: [ArcAshAssetRef], remote: ArcAshRemote) async throws {
        for r in refs {
            guard let sha = r.sha256, r.source == "imported",
                  ArcAshStorage.assetExists(sha: sha, ext: r.ext) else { continue }
            if ArcAshStorage.isPushed(sha: sha, backend: remote.label) { continue }
            if r.bytes > remote.maxAssetBytes { continue }
            do {
                if try await remote.hasAsset(sha: sha, ext: r.ext) == false {
                    try await remote.putAsset(sha: sha, ext: r.ext,
                                              fileURL: ArcAshStorage.assetURL(sha: sha, ext: r.ext))
                }
                ArcAshStorage.markPushed(sha: sha, backend: remote.label)
            } catch {
                let c = ArcAshSyncError.classify(error)
                switch c {
                case .offline, .unauthorized, .rateLimited, .repoIsPublic: throw c
                default: continue   // one bad asset must not block the project file
                }
            }
        }
    }

    /// Try to obtain a model file referenced by a document from the remote.
    public static func fetchAsset(sha: String, ext: String, remote: ArcAshRemote) async -> Bool {
        ArcAshStorage.ensureDirs()
        let dest = ArcAshStorage.assetURL(sha: sha, ext: ext)
        if FileManager.default.fileExists(atPath: dest.path) { return true }
        return (try? await remote.getAsset(sha: sha, ext: ext, to: dest)) ?? false
    }
}

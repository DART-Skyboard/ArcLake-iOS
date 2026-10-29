import Foundation

// ═══════════════════════════════════════════════════════════════════
// ArcAshStorage — on-device layout for .ash sessions and cached assets.
//
//   Application Support/ArcLakeAsh/
//       sessions/<sessionId>.ash       (+ .bak = previous good copy)
//       meta/<sessionId>.json          (per-backend sync bookkeeping)
//       assets/<sha256>.<ext>          (content-addressed model cache)
//       asset-index.json               (display name → file identity)
//
// Writes are atomic (temp file + rename) and keep a one-deep .bak so a
// crash or power loss mid-save can never destroy the last good session.
// ═══════════════════════════════════════════════════════════════════

public struct ArcAshSessionSummary: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var revision: Int
    public var updatedAt: String
    public var url: URL
}

public struct ArcAshSyncMeta: Codable, Equatable {
    /// Backend's opaque version token at last successful sync (git blob sha / content sha).
    public var token: String? = nil
    /// Local revision that token corresponds to.
    public var revision: Int = 0
    public var lastSync: String? = nil
    public init() {}
}

public enum ArcAshStorage {
    public static let maxLocalAssetCopyBytes = 512 * 1024 * 1024

    public static var root: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ArcLakeAsh", isDirectory: true)
    }
    public static var sessionsDir: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    public static var metaDir: URL { root.appendingPathComponent("meta", isDirectory: true) }
    public static var assetsDir: URL { root.appendingPathComponent("assets", isDirectory: true) }

    public static func ensureDirs() {
        let fm = FileManager.default
        for d in [sessionsDir, metaDir, assetsDir] {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    public static func sessionURL(_ id: String) -> URL {
        sessionsDir.appendingPathComponent("\(id).ash")
    }
    public static func assetURL(sha: String, ext: String) -> URL {
        assetsDir.appendingPathComponent(ext.isEmpty ? sha : "\(sha).\(ext)")
    }
    public static func assetExists(sha: String, ext: String) -> Bool {
        FileManager.default.fileExists(atPath: assetURL(sha: sha, ext: ext).path)
    }

    // MARK: — Crash-safe write
    public static func writeAtomic(_ data: Data, to url: URL, keepBackup: Bool = true) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if keepBackup, fm.fileExists(atPath: url.path) {
            let bak = url.appendingPathExtension("bak")
            try? fm.removeItem(at: bak)
            try? fm.copyItem(at: url, to: bak)
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: — Read (falls back to .bak when the primary is unreadable)
    public static func readDocument(at url: URL) -> ArcAshDocument? {
        if let d = try? Data(contentsOf: url), let doc = try? ArcAshDocument.decode(d) { return doc }
        let bak = url.appendingPathExtension("bak")
        if let d = try? Data(contentsOf: bak), let doc = try? ArcAshDocument.decode(d) { return doc }
        return nil
    }
    public static func readDocument(id: String) -> ArcAshDocument? { readDocument(at: sessionURL(id)) }

    public static func listSessions() -> [ArcAshSessionSummary] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: sessionsDir.path) else { return [] }
        var out: [ArcAshSessionSummary] = []
        for n in names where n.hasSuffix(".ash") {
            let url = sessionsDir.appendingPathComponent(n)
            guard let doc = readDocument(at: url) else { continue }
            out.append(ArcAshSessionSummary(id: doc.sessionId, name: doc.name,
                                            revision: doc.revision, updatedAt: doc.updatedAt, url: url))
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    public static func deleteSession(_ id: String) {
        let fm = FileManager.default
        let url = sessionURL(id)
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: url.appendingPathExtension("bak"))
        try? fm.removeItem(at: metaDir.appendingPathComponent("\(id).json"))
    }

    // MARK: — Sync metadata
    public static func loadMeta(_ id: String) -> [String: ArcAshSyncMeta] {
        let url = metaDir.appendingPathComponent("\(id).json")
        guard let d = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode([String: ArcAshSyncMeta].self, from: d) else { return [:] }
        return m
    }
    public static func saveMeta(_ id: String, _ meta: [String: ArcAshSyncMeta]) {
        guard let d = try? JSONEncoder().encode(meta) else { return }
        try? writeAtomic(d, to: metaDir.appendingPathComponent("\(id).json"), keepBackup: false)
    }

    // MARK: — Pushed-asset bookkeeping (UserDefaults, cleared on wipe)
    private static let pushedKey = "arc_ash_pushed_shas"
    /// Keys are "<backend>:<sha256>".
    public static func isPushed(sha: String, backend: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: pushedKey) ?? []).contains("\(backend):\(sha)")
    }
    public static func isPushedAnywhere(sha: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: pushedKey) ?? []).contains { $0.hasSuffix(":" + sha) }
    }
    public static func markPushed(sha: String, backend: String) {
        var cur = UserDefaults.standard.stringArray(forKey: pushedKey) ?? []
        let key = "\(backend):\(sha)"
        if !cur.contains(key) { cur.append(key); UserDefaults.standard.set(cur, forKey: pushedKey) }
    }

    // MARK: — Deleted-session tombstones (so pull doesn't resurrect them)
    private static let tombKey = "arc_ash_deleted_sessions"
    public static func isTombstoned(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: tombKey) ?? []).contains(id)
    }
    public static func tombstone(_ id: String) {
        var cur = UserDefaults.standard.stringArray(forKey: tombKey) ?? []
        if !cur.contains(id) { cur.append(id); UserDefaults.standard.set(cur, forKey: tombKey) }
    }

    // MARK: — Account deletion
    /// Removes every locally stored .ash file, cached asset and bookkeeping key.
    public static func wipeLocal() {
        try? FileManager.default.removeItem(at: root)
        let d = UserDefaults.standard
        for k in ["arc_ash_current_session", "arc_ash_pushed_shas", "arc_ash_deleted_sessions",
                  "arc_ash_restoring", "arc_ash_repo_ready", "arc_ash_device_id"] {
            d.removeObject(forKey: k)
        }
    }
}

// MARK: — Imported-asset index
@MainActor
public final class ArcAshAssetIndex {
    public static let shared = ArcAshAssetIndex()
    private var byName: [String: ArcAshAssetRef] = [:]

    private init() { load() }

    private static var indexURL: URL { ArcAshStorage.root.appendingPathComponent("asset-index.json") }

    public func ref(forName name: String) -> ArcAshAssetRef? { byName[name] }

    public func register(_ ref: ArcAshAssetRef) {
        byName[ref.name] = ref
        persist()
    }
    public func reset() {
        byName = [:]
        try? FileManager.default.removeItem(at: ArcAshAssetIndex.indexURL)
    }

    private func load() {
        guard let d = try? Data(contentsOf: ArcAshAssetIndex.indexURL),
              let m = try? JSONDecoder().decode([String: ArcAshAssetRef].self, from: d) else { return }
        byName = m
    }
    private func persist() {
        ArcAshStorage.ensureDirs()
        guard let d = try? JSONEncoder().encode(byName) else { return }
        try? ArcAshStorage.writeAtomic(d, to: ArcAshAssetIndex.indexURL, keepBackup: false)
    }

    /// Called right after the user picks a model file. Hashes + copies it into
    /// the content-addressed cache off the main thread, then records its identity.
    public nonisolated static func ingest(url: URL, source: String = "imported") {
        Task.detached(priority: .utility) {
            guard let ref = ArcAshAssetIndex.copyIntoStore(url: url, source: source) else { return }
            await MainActor.run { ArcAshAssetIndex.shared.register(ref) }
        }
    }

    public nonisolated static func copyIntoStore(url: URL, source: String) -> ArcAshAssetRef? {
        guard let h = ArcAshHash.sha256Hex(fileURL: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        ArcAshStorage.ensureDirs()
        var storage = "reference"
        let dest = ArcAshStorage.assetURL(sha: h.sha, ext: ext)
        if !FileManager.default.fileExists(atPath: dest.path) {
            if h.bytes <= ArcAshStorage.maxLocalAssetCopyBytes {
                try? FileManager.default.copyItem(at: url, to: dest)
            } else {
                storage = "unavailable"
            }
        }
        return ArcAshAssetRef(name: url.deletingPathExtension().lastPathComponent,
                              fileName: url.lastPathComponent, ext: ext, sha256: h.sha,
                              bytes: h.bytes, source: source, storage: storage)
    }
}

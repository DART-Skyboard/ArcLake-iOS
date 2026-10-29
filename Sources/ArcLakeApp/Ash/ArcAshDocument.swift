import Foundation
import CryptoKit
import UIKit
import UniformTypeIdentifiers

// ═══════════════════════════════════════════════════════════════════
// ArcAshDocument — the ArcLake project file (*.ash).
//
// A complete, versioned application state, like Blender's .blend:
// every module (theme, render, camera, scene assets, fluid/CFD,
// Mantis, chemistry, algebra/physics, UI layout) serialises into
// `modules` as an independent, forward-compatible JSON blob.
//
//   • Unknown top-level fields   → preserved in `unknown`
//   • Unknown modules            → preserved in `modules`
//   • Unknown fields in modules  → preserved by ArcJSON.merged(with:)
//   • `revision` increases by one per persisted change (sync ordering)
// ═══════════════════════════════════════════════════════════════════

public extension UTType {
    /// Declared in Info.plist via project.yml (UTExportedTypeDeclarations).
    static let arcAsh = UTType(exportedAs: "com.dartmeadow.arclake.ash", conformingTo: .json)
}

// MARK: — Time / hashing / colour helpers
public enum ArcAshTime {
    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
    public static func iso(_ d: Date = Date()) -> String { formatter().string(from: d) }
    public static func parse(_ s: String) -> Date? {
        if let d = formatter().date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: s)
    }
}

public enum ArcAshHash {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Streaming hash — never loads a large GLB fully into memory.
    public static func sha256Hex(fileURL: URL) -> (sha: String, bytes: Int)? {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        var total = 0
        while true {
            let chunk: Data? = autoreleasepool { try? fh.read(upToCount: 1 << 20) }
            guard let c = chunk, !c.isEmpty else { break }
            hasher.update(data: c)
            total += c.count
        }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (hex, total)
    }
}

public enum ArcAshColor {
    public static func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
    }
    public static func color(_ s: String) -> UIColor? {
        let h = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard h.count == 6 || h.count == 8 else { return nil }
        var v: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&v) else { return nil }
        let hasAlpha = h.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: — Asset reference (file identity: name / size / SHA-256)
public struct ArcAshAssetRef: Codable, Equatable, Sendable {
    public var name: String            // display base name, e.g. "Combustion_flow"
    public var fileName: String        // original file name incl. extension
    public var ext: String
    public var sha256: String?         // nil for bundled / not-yet-hashed
    public var bytes: Int
    /// "imported" | "bundled" | "remote-cache"
    public var source: String
    /// "reference" (not stored anywhere but the device) | "repo" (assets/<sha>
    /// in the user's private sync repo) | "vault" | "embedded" | "bundled" | "unavailable"
    public var storage: String
    public init(name: String, fileName: String, ext: String, sha256: String?,
                bytes: Int, source: String, storage: String) {
        self.name = name; self.fileName = fileName; self.ext = ext
        self.sha256 = sha256; self.bytes = bytes; self.source = source; self.storage = storage
    }
}

// MARK: — Document
public struct ArcAshDocument: Codable, Equatable {
    public static let formatID = "arclake.ash"
    public static let currentSchemaVersion = 1

    public var format: String = ArcAshDocument.formatID
    public var schemaVersion: Int = ArcAshDocument.currentSchemaVersion
    public var appVersion: String = ""
    public var appBuild: String = ""
    public var createdAt: String = ArcAshTime.iso()
    public var updatedAt: String = ArcAshTime.iso()
    public var revision: Int = 0
    public var deviceId: String = ""
    public var sessionId: String = UUID().uuidString
    public var name: String = "Untitled"
    /// moduleID → {"moduleVersion": Int, "settings": {...}}
    public var modules: [String: ArcJSON] = [:]
    /// Scene asset file references (array of ArcAshAssetRef as ArcJSON)
    public var assets: [ArcJSON] = []
    /// Optional embedded model files: sha256 → base64 (only in exported copies)
    public var embeddedAssets: [String: String] = [:]
    /// Top-level fields this version doesn't know (written by a newer app).
    public var unknown: [String: ArcJSON] = [:]

    public init() {}

    public var isNewerSchema: Bool { schemaVersion > ArcAshDocument.currentSchemaVersion }

    private static let knownKeys: Set<String> = [
        "format", "schemaVersion", "appVersion", "appBuild", "createdAt", "updatedAt",
        "revision", "deviceId", "sessionId", "name", "modules", "assets", "embeddedAssets"
    ]

    private struct DynKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ s: String) { self.stringValue = s }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynKey.self)
        let fmt = (try? c.decode(String.self, forKey: DynKey("format"))) ?? ""
        guard fmt == ArcAshDocument.formatID else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Not an ArcLake .ash project file"))
        }
        format = fmt
        schemaVersion = (try? c.decode(Int.self, forKey: DynKey("schemaVersion"))) ?? 1
        appVersion = (try? c.decode(String.self, forKey: DynKey("appVersion"))) ?? ""
        appBuild = (try? c.decode(String.self, forKey: DynKey("appBuild"))) ?? ""
        createdAt = (try? c.decode(String.self, forKey: DynKey("createdAt"))) ?? ArcAshTime.iso()
        updatedAt = (try? c.decode(String.self, forKey: DynKey("updatedAt"))) ?? createdAt
        revision = (try? c.decode(Int.self, forKey: DynKey("revision"))) ?? 0
        deviceId = (try? c.decode(String.self, forKey: DynKey("deviceId"))) ?? ""
        sessionId = (try? c.decode(String.self, forKey: DynKey("sessionId"))) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: DynKey("name"))) ?? "Untitled"
        modules = (try? c.decode([String: ArcJSON].self, forKey: DynKey("modules"))) ?? [:]
        assets = (try? c.decode([ArcJSON].self, forKey: DynKey("assets"))) ?? []
        embeddedAssets = (try? c.decode([String: String].self, forKey: DynKey("embeddedAssets"))) ?? [:]
        var rest: [String: ArcJSON] = [:]
        for key in c.allKeys where !ArcAshDocument.knownKeys.contains(key.stringValue) {
            if let v = try? c.decode(ArcJSON.self, forKey: key) { rest[key.stringValue] = v }
        }
        unknown = rest
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynKey.self)
        for (k, v) in unknown { try c.encode(v, forKey: DynKey(k)) }
        try c.encode(format, forKey: DynKey("format"))
        try c.encode(schemaVersion, forKey: DynKey("schemaVersion"))
        try c.encode(appVersion, forKey: DynKey("appVersion"))
        try c.encode(appBuild, forKey: DynKey("appBuild"))
        try c.encode(createdAt, forKey: DynKey("createdAt"))
        try c.encode(updatedAt, forKey: DynKey("updatedAt"))
        try c.encode(revision, forKey: DynKey("revision"))
        try c.encode(deviceId, forKey: DynKey("deviceId"))
        try c.encode(sessionId, forKey: DynKey("sessionId"))
        try c.encode(name, forKey: DynKey("name"))
        try c.encode(modules, forKey: DynKey("modules"))
        try c.encode(assets, forKey: DynKey("assets"))
        if !embeddedAssets.isEmpty { try c.encode(embeddedAssets, forKey: DynKey("embeddedAssets")) }
    }

    // MARK: — Serialisation
    public func encoded(pretty: Bool = true) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try? enc.encode(self)
    }
    public static func decode(_ data: Data) throws -> ArcAshDocument {
        try JSONDecoder().decode(ArcAshDocument.self, from: data)
    }

    /// Stable content fingerprint (ignores revision / timestamps / device) —
    /// used to skip no-op autosaves.
    /// By default the live camera view (orbit position) is NOT part of the
    /// fingerprint — orbiting must not create a new revision / sync commit every
    /// few seconds. It is still saved whenever something else changes, and on
    /// background / terminate (includeCameraView: true).
    public func contentFingerprint(includeCameraView: Bool = false) -> String {
        struct Body: Encodable { let name: String; let modules: [String: ArcJSON]; let assets: [ArcJSON] }
        var mods = modules
        if !includeCameraView,
           var cam = mods["camera"]?.objectValue,
           var settings = cam["settings"]?.objectValue,
           var global = settings["global"]?.objectValue {
            global.removeValue(forKey: "view")
            settings["global"] = .object(global)
            cam["settings"] = .object(settings)
            mods["camera"] = .object(cam)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(Body(name: name, modules: mods, assets: assets)) else { return "" }
        return ArcAshHash.sha256Hex(d)
    }

    public func assetRefs() -> [ArcAshAssetRef] {
        assets.compactMap { $0.decode(ArcAshAssetRef.self) }
    }

    // MARK: — Module envelope helpers
    public static func envelope(version: Int, settings: ArcJSON) -> ArcJSON {
        .object(["moduleVersion": .n(version), "settings": settings])
    }
    public func settings(for moduleID: String) -> ArcJSON? {
        guard let env = modules[moduleID] else { return nil }
        if let s = env["settings"] { return s }
        return env
    }
}

// MARK: — Device / app identity
public enum ArcAshIdentity {
    public static var deviceId: String {
        let key = "arc_ash_device_id"
        if let s = UserDefaults.standard.string(forKey: key), !s.isEmpty { return s }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
    public static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    public static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

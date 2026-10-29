import Foundation
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// Per-module presets — the shared schema (keep EXACTLY; the web sandbox
// writes the 'fluid' ones):
//
// {"schema":"arclake.module-preset","version":1,
//  "module":"fluid|mantis|chemistry|thermal|...",
//  "createdAt":ISO8601,"appVersion":"…",
//  "asset":{"name","sha256","bytes","source",
//           "parts":[{"key","name","bbox"}]},
//  "settings":{"global":{…},"parts":{"<partKey>":{…}}}}
// ═══════════════════════════════════════════════════════════════════

public struct ArcAshParsedPreset {
    public let module: String
    public let settings: ArcJSON
    public let asset: ArcJSON?
    public let version: Int
    public var warnings: [String]
}

public struct ArcAshPresetReport {
    public var moduleID: String
    public var applied: Bool
    public var messages: [String]
}

public enum ArcAshPresetError: LocalizedError {
    case notJSON
    case unsupportedSchema(String)
    case noSettings

    public var errorDescription: String? {
        switch self {
        case .notJSON: return "That file isn't valid JSON."
        case .unsupportedSchema(let s): return "Unsupported preset schema “\(s)”."
        case .noSettings: return "The preset has no settings block."
        }
    }
}

@MainActor
public enum ArcModulePreset {
    public static let schemaID = "arclake.module-preset"
    public static let version = 1

    public static func build(moduleID: String, settings: ArcJSON, asset: ArcAshLiveAsset?) -> Data? {
        var root = ArcJB()
        root.str("schema", schemaID)
        root.num("version", version)
        root.str("module", moduleID)
        root.str("createdAt", ArcAshTime.iso())
        root.str("appVersion", ArcAshIdentity.appVersion)
        var effective = settings
        if let asset {
            var parts: [ArcJSON] = []
            let infos = ArcAshSceneModule.parts(of: asset.node)
            for p in infos {
                var b = ArcJB()
                b.str("key", p.key)
                b.str("name", p.name)
                b.vec("bbox", p.bbox)
                parts.append(b.json)
            }
            var a = ArcJB()
            a.str("name", asset.displayName)
            if let sha = asset.ref.sha256 { a.str("sha256", sha) } else { a.set("sha256", .null) }
            a.num("bytes", asset.ref.bytes)
            a.str("source", asset.ref.source)
            a.set("parts", .array(parts))
            root.set("asset", a.json)
            // Scope per-part settings to this asset's parts only.
            if let all = settings.parts.objectValue {
                let keep = Set(infos.map { $0.key })
                var scoped: [String: ArcJSON] = [:]
                for (k, v) in all where keep.contains(k) { scoped[k] = v }
                var s = settings.objectValue ?? [:]
                s["parts"] = .object(scoped)
                effective = .object(s)
            }
        }
        root.set("settings", effective)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(root.json)
    }

    /// Lenient: also accepts the web sandbox's exported fluid JSON.
    public static func parse(_ data: Data) throws -> ArcAshParsedPreset {
        guard let top = try? JSONDecoder().decode(ArcJSON.self, from: data),
              case .object = top else { throw ArcAshPresetError.notJSON }
        var warnings: [String] = []
        if let schema = top.str("schema"), schema != schemaID {
            throw ArcAshPresetError.unsupportedSchema(schema)
        }
        let version = top.integer("version") ?? 1
        if version > ArcModulePreset.version {
            warnings.append("Preset version \(version) is newer than this app understands — applying what's recognised.")
        }
        let settings: ArcJSON
        if let s = top.dict("settings") {
            settings = s
        } else if top["global"] != nil || top["parts"] != nil {
            settings = top                      // bare {global, parts}
        } else {
            throw ArcAshPresetError.noSettings
        }
        let module = (top.str("module") ?? "fluid").lowercased()
        return ArcAshParsedPreset(module: module, settings: settings, asset: top.dict("asset"),
                                  version: version, warnings: warnings)
    }

    /// Re-keys per-part settings from the preset's asset onto the matching asset in this scene.
    public static func remapParts(settings: ArcJSON, presetAsset: ArcJSON?,
                                  liveAssets: [ArcAshLiveAsset]) -> (settings: ArcJSON, messages: [String]) {
        guard let partsObj = settings.parts.objectValue, !partsObj.isEmpty else { return (settings, []) }
        var messages: [String] = []

        // Pick the scene asset this preset was made for: sha256 first, then name.
        var found: ArcAshLiveAsset? = nil
        if let a = presetAsset {
            if let sha = a.str("sha256"), !sha.isEmpty {
                found = liveAssets.first { $0.ref.sha256 == sha }
            }
            if found == nil, let name = a.str("name") {
                found = liveAssets.first { $0.displayName == name }
                if let t = found, let sha = a.str("sha256"), let have = t.ref.sha256, sha != have {
                    messages.append("Model file differs from the one this preset was made for (SHA-256 mismatch) — matched by part name.")
                }
            }
        }
        guard let target = found else {
            messages.append("No matching model in this scene — part settings are kept and apply when that model is loaded.")
            return (settings, messages)
        }
        let targetParts = ArcAshSceneModule.parts(of: target.node)
        let targetKeys = Set(targetParts.map { $0.key })
        var byName: [String: String] = [:]
        for p in targetParts where byName[p.name] == nil { byName[p.name] = p.key }
        let presetParts = presetAsset?.list("parts") ?? []

        var out: [String: ArcJSON] = [:]
        var direct = 0, remapped = 0, unmatched = 0
        for (k, v) in partsObj {
            if targetKeys.contains(k) { out[k] = v; direct += 1; continue }
            let name = presetParts.first { $0.str("key") == k }?.str("name") ?? k
            if let tk = byName[name], out[tk] == nil { out[tk] = v; remapped += 1 }
            else { out[k] = v; unmatched += 1 }
        }
        messages.append("Matched \(direct + remapped) of \(partsObj.count) parts on “\(target.displayName)”"
                        + (remapped > 0 ? " (\(remapped) by name)." : "."))
        if unmatched > 0 { messages.append("\(unmatched) part(s) had no counterpart and were left unapplied.") }
        var s = settings.objectValue ?? [:]
        s["parts"] = .object(out)
        return (.object(s), messages)
    }
}

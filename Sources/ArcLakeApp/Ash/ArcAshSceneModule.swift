import SwiftUI
import SceneKit

// ═══════════════════════════════════════════════════════════════════
// Scene module — imported 3D assets per scene tab.
//
// Files are referenced by name / size / SHA-256 (never inlined in the
// autosave). Restoring tries, in order: the local content-addressed
// cache → the bundled resource → the Documents/remote cache → the
// built-in demo download → the user's sync store (assets/<sha>).
// Anything that can't be resolved stays recorded as "unresolved" and is
// retried on the next open, so a missing file never erases the reference.
// ═══════════════════════════════════════════════════════════════════

public struct ArcAshPartInfo {
    public let key: String
    public let name: String
    public let bbox: [Double]     // [minX,minY,minZ,maxX,maxY,maxZ] world space
}

public struct ArcAshLiveAsset {
    public let nodeName: String
    public let displayName: String
    public let ref: ArcAshAssetRef
    public let node: SCNNode
}

@MainActor
final class ArcAshSceneModule: ArcAshModule {
    let moduleID = "scene"
    let moduleVersion = 1
    var isContent: Bool { true }

    private let labVM: ArcLabViewModel
    /// [{"tab": Int, "entry": ArcJSON}] — instances whose file couldn't be found.
    private var unresolved: [ArcJSON] = []
    /// Asset refs seen by the most recent capture() (feeds doc.assets).
    private(set) var lastRefs: [ArcAshAssetRef] = []
    private var shaCache: [String: String] = [:]
    private var shaInFlight = Set<String>()

    init(labVM: ArcLabViewModel) { self.labVM = labVM }

    // MARK: naming helpers
    static func isImportName(_ n: String?) -> Bool {
        guard let n else { return false }
        return n.hasPrefix("glb_import_") || n.hasPrefix("imported_")
    }
    static func displayName(_ n: String) -> String {
        for p in ["glb_import_", "imported_"] where n.hasPrefix(p) { return String(n.dropFirst(p.count)) }
        return n
    }

    // MARK: file identity
    private func lazySha(url: URL, key: String) -> String? {
        if let s = shaCache[key] { return s }
        if shaInFlight.insert(key).inserted {
            Task.detached(priority: .utility) {
                let h = ArcAshHash.sha256Hex(fileURL: url)
                await MainActor.run { [weak self] in
                    self?.shaInFlight.remove(key)
                    if let h { self?.shaCache[key] = h.sha }
                }
            }
        }
        return nil
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    func ref(forDisplayName name: String) -> ArcAshAssetRef {
        if MantisNavModel.builtInAssets.contains(where: { $0.resource == name }) {
            var sha: String? = nil
            var bytes = 0
            if let u = Bundle.main.url(forResource: name, withExtension: "glb") {
                bytes = fileSize(u)
                sha = lazySha(url: u, key: "bundled:" + name)
            }
            return ArcAshAssetRef(name: name, fileName: name + ".glb", ext: "glb", sha256: sha,
                                  bytes: bytes, source: "bundled", storage: "bundled")
        }
        if MantisNavModel.remoteAssets.contains(where: { $0.resource == name }) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let u = docs.appendingPathComponent(name + ".glb")
            var sha: String? = nil
            var bytes = 0
            if FileManager.default.fileExists(atPath: u.path) {
                bytes = fileSize(u)
                sha = lazySha(url: u, key: "remote:" + name)
            }
            return ArcAshAssetRef(name: name, fileName: name + ".glb", ext: "glb", sha256: sha,
                                  bytes: bytes, source: "remote-cache", storage: "reference")
        }
        if var r = ArcAshAssetIndex.shared.ref(forName: name) {
            if let sha = r.sha256 {
                if ArcAshStorage.isPushedAnywhere(sha: sha) { r.storage = "repo" }
                else if !ArcAshStorage.assetExists(sha: sha, ext: r.ext) { r.storage = "unavailable" }
            }
            return r
        }
        return ArcAshAssetRef(name: name, fileName: name, ext: "", sha256: nil, bytes: 0,
                              source: "imported", storage: "unavailable")
    }

    // MARK: live view of the scene (for the preset exporter UI)
    func liveAssets(activeTabOnly: Bool = true) -> [ArcAshLiveAsset] {
        let scenes = activeTabOnly ? [labVM.scene] : labVM.allTabScenes()
        var out: [ArcAshLiveAsset] = []
        var seen = Set<String>()
        for sc in scenes {
            for n in sc.rootNode.childNodes {
                guard let nm = n.name, Self.isImportName(nm), seen.insert(nm).inserted else { continue }
                let d = Self.displayName(nm)
                out.append(ArcAshLiveAsset(nodeName: nm, displayName: d, ref: ref(forDisplayName: d), node: n))
            }
        }
        return out
    }

    /// Mesh parts of an imported asset with world-space bounding boxes.
    static func parts(of root: SCNNode) -> [ArcAshPartInfo] {
        var seen: [String: Int] = [:]
        var out: [ArcAshPartInfo] = []
        root.enumerateChildNodes { child, _ in
            guard child.geometry != nil, let nm = child.name,
                  !nm.hasPrefix("arc_light_"), nm != "arcFluidCloud" else { return }
            let count = (seen[nm] ?? 0) + 1
            seen[nm] = count
            let key = count == 1 ? nm : "\(nm)#\(count)"
            let bb = child.boundingBox
            var lo = [Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude]
            var hi = [-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude]
            for xi in 0..<2 { for yi in 0..<2 { for zi in 0..<2 {
                let local = SCNVector3(xi == 0 ? bb.min.x : bb.max.x,
                                       yi == 0 ? bb.min.y : bb.max.y,
                                       zi == 0 ? bb.min.z : bb.max.z)
                let w = child.convertPosition(local, to: nil)
                lo[0] = min(lo[0], Float(w.x)); lo[1] = min(lo[1], Float(w.y)); lo[2] = min(lo[2], Float(w.z))
                hi[0] = max(hi[0], Float(w.x)); hi[1] = max(hi[1], Float(w.y)); hi[2] = max(hi[2], Float(w.z))
            } } }
            out.append(ArcAshPartInfo(key: key, name: nm,
                                      bbox: [Double(lo[0]), Double(lo[1]), Double(lo[2]),
                                             Double(hi[0]), Double(hi[1]), Double(hi[2])]))
        }
        return out
    }

    // MARK: transform
    /// 4-decimal rounding: float noise must not look like a user edit.
    private func r4(_ v: Float) -> Double { (Double(v) * 10000).rounded() / 10000 }

    private func transformJSON(_ n: SCNNode) -> ArcJSON {
        var b = ArcJB()
        b.vec("position", [r4(Float(n.position.x)), r4(Float(n.position.y)), r4(Float(n.position.z))])
        b.vec("orientation", [r4(Float(n.orientation.x)), r4(Float(n.orientation.y)),
                              r4(Float(n.orientation.z)), r4(Float(n.orientation.w))])
        b.vec("scale", [r4(Float(n.scale.x)), r4(Float(n.scale.y)), r4(Float(n.scale.z))])
        return b.json
    }
    private func applyTransform(_ e: ArcJSON, to n: SCNNode) {
        guard let t = e.dict("transform") else { return }
        if let p = t.list("position")?.compactMap({ $0.doubleValue }), p.count == 3 {
            n.position = SCNVector3(Float(p[0]), Float(p[1]), Float(p[2]))
        }
        if let q = t.list("orientation")?.compactMap({ $0.doubleValue }), q.count == 4 {
            n.orientation = SCNVector4(Float(q[0]), Float(q[1]), Float(q[2]), Float(q[3]))
        }
        if let s = t.list("scale")?.compactMap({ $0.doubleValue }), s.count == 3 {
            n.scale = SCNVector3(Float(s[0]), Float(s[1]), Float(s[2]))
        }
        if let h = e.flag("hidden") { n.isHidden = h }
    }

    // MARK: capture
    private var lastCapture: ArcJSON? = nil

    func capture() -> ArcJSON {
        // A Mantis flight moves the vehicle every frame — that is runtime state,
        // not an edit, so don't autosave (and sync) it while flying.
        if labVM.mantis.isActive, let cached = lastCapture { return cached }
        var refs: [ArcAshAssetRef] = []
        var refKeys = Set<String>()
        var tabs: [ArcJSON] = []
        let scenes = labVM.allTabScenes()
        for (i, sc) in scenes.enumerated() {
            var entries: [ArcJSON] = []
            var liveNames = Set<String>()
            for n in sc.rootNode.childNodes {
                guard let nm = n.name, Self.isImportName(nm) else { continue }
                liveNames.insert(nm)
                let d = Self.displayName(nm)
                let r = ref(forDisplayName: d)
                if refKeys.insert("\(r.name)|\(r.sha256 ?? "")").inserted { refs.append(r) }
                var b = ArcJB()
                b.str("nodeName", nm)
                b.str("name", d)
                b.str("ext", r.ext)
                if let sha = r.sha256 { b.str("sha256", sha) }
                b.num("bytes", r.bytes)
                b.str("source", r.source)
                b.set("transform", transformJSON(n))
                b.flag("hidden", n.isHidden)
                entries.append(b.json)
            }
            for u in unresolved {
                guard u.integer("tab") == i, let e = u["entry"], let nm = e.str("nodeName"),
                      !liveNames.contains(nm) else { continue }
                var copy = e.objectValue ?? [:]
                copy["unresolved"] = .bool(true)
                entries.append(.object(copy))
            }
            var tb = ArcJB()
            tb.num("index", i)
            if i < labVM.sceneTabs_data.count { tb.str("name", labVM.sceneTabs_data[i]) }
            tb.set("assets", .array(entries))
            tabs.append(tb.json)
        }
        lastRefs = refs
        let result: ArcJSON = .object(["global": .object([:]), "tabs": .array(tabs)])
        lastCapture = result
        return result
    }

    // MARK: apply
    func resetDefaults() {
        lastCapture = nil
        for sc in labVM.allTabScenes() {
            for n in sc.rootNode.childNodes where Self.isImportName(n.name) { n.removeFromParentNode() }
        }
        unresolved = []
        ArcSceneOutlinerVM.shared.scan(labVM.scene)
    }

    func apply(_ settings: ArcJSON) async {
        lastCapture = nil
        unresolved = []
        for t in settings.list("tabs") ?? [] {
            guard let idx = t.integer("index") else { continue }
            for e in t.list("assets") ?? [] {
                let scenes = labVM.allTabScenes()
                guard idx >= 0, idx < scenes.count else {
                    unresolved.append(.object(["tab": .n(idx), "entry": e]))
                    continue
                }
                let ok = await restore(entry: e, into: scenes[idx])
                if !ok { unresolved.append(.object(["tab": .n(idx), "entry": e])) }
            }
        }
        ArcSceneOutlinerVM.shared.scan(labVM.scene)
    }

    /// Re-attempts instances whose model file wasn't available earlier (e.g. after a sync pulled it).
    func retryUnresolved() async {
        guard !unresolved.isEmpty else { return }
        let pending = unresolved
        unresolved = []
        for u in pending {
            guard let idx = u.integer("tab"), let e = u["entry"] else { continue }
            let scenes = labVM.allTabScenes()
            guard idx >= 0, idx < scenes.count else { unresolved.append(u); continue }
            let ok = await restore(entry: e, into: scenes[idx])
            if !ok { unresolved.append(u) }
        }
        ArcSceneOutlinerVM.shared.scan(labVM.scene)
    }

    private func restore(entry e: ArcJSON, into scene: SCNScene) async -> Bool {
        guard let nodeName = e.str("nodeName"), !nodeName.isEmpty else { return true }
        if let existing = scene.rootNode.childNode(withName: nodeName, recursively: false) {
            applyTransform(e, to: existing)
            return true
        }
        guard let url = await resolveFile(e, nodeName: nodeName) else { return false }
        let loaded: SCNNode? = await Task.detached(priority: .userInitiated) {
            ArcGLBImporter().importGLB(url: url)
        }.value
        guard let node = loaded else { return false }
        node.name = nodeName
        applyTransform(e, to: node)
        scene.rootNode.addChildNode(node)
        return true
    }

    private func resolveFile(_ e: ArcJSON, nodeName: String) async -> URL? {
        let display = e.str("name") ?? Self.displayName(nodeName)
        let ext = (e.str("ext") ?? "glb").isEmpty ? "glb" : (e.str("ext") ?? "glb")
        let sha = e.str("sha256")
        // Only binary glTF can be re-imported automatically.
        guard ext == "glb" else { return nil }
        if let sha, ArcAshStorage.assetExists(sha: sha, ext: ext) {
            return ArcAshStorage.assetURL(sha: sha, ext: ext)
        }
        if MantisNavModel.builtInAssets.contains(where: { $0.resource == display }),
           let u = Bundle.main.url(forResource: display, withExtension: "glb") {
            return u
        }
        if let ra = MantisNavModel.remoteAssets.first(where: { $0.resource == display }) {
            if let u = try? await labVM.mantis.cachedRemoteURL(resource: ra.resource, remoteURL: ra.url) {
                return u
            }
        }
        if let sha {
            if await ArcAshSession.shared.fetchAssetFromRemote(sha: sha, ext: ext) {
                return ArcAshStorage.assetURL(sha: sha, ext: ext)
            }
        }
        return nil
    }
}

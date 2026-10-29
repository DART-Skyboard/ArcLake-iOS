import SwiftUI
import Combine
import Network
import UIKit

// ═══════════════════════════════════════════════════════════════════
// ArcAshSession — owns the current project (*.ash) and everything
// around it: capture/apply of every module, debounced + periodic +
// background autosave with crash-safe atomic writes, New / Open /
// Save / Save As, per-module presets, and the sync loop.
//
// Threading: this class is @MainActor (it touches SceneKit and the
// view models), but ALL network and heavy file work happens in
// nonisolated async functions (ArcAshSyncEngine / remotes), so the main
// thread is never blocked on I/O waits and no semaphores are used.
// ═══════════════════════════════════════════════════════════════════

public enum ArcAshSyncStatus: Equatable {
    case off(String)
    case idle
    case syncing
    case synced(Date)
    case offline
    case error(String)

    public var text: String {
        switch self {
        case .off(let s): return s
        case .idle: return "Waiting to sync"
        case .syncing: return "Syncing…"
        case .synced(let d):
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
            return "Synced " + f.localizedString(for: d, relativeTo: Date())
        case .offline: return "Offline — will sync when back online"
        case .error(let s): return s
        }
    }
    public var symbol: String {
        switch self {
        case .off: return "icloud.slash"
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .offline: return "wifi.slash"
        case .error: return "exclamationmark.icloud"
        }
    }
}

private final class ArcAshBGBox: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid
}

@MainActor
public final class ArcAshSession: ObservableObject {
    public static let shared = ArcAshSession()

    @Published public private(set) var document: ArcAshDocument
    @Published public private(set) var syncStatus: ArcAshSyncStatus = .off("Local only — sign in to sync")
    @Published public private(set) var lastSavedAt: Date? = nil
    @Published public private(set) var sessions: [ArcAshSessionSummary] = []
    @Published public var message: String? = nil
    @Published public private(set) var syncTarget: String = "On this device only"

    private weak var labVM: ArcLabViewModel?
    private weak var themeVM: ArcThemeViewModel?
    private weak var authVM: ArcAuthViewModel?

    private var modules: [any ArcAshModule] = []
    private var moduleByID: [String: any ArcAshModule] = [:]
    private var sceneModule: ArcAshSceneModule?
    /// Module envelopes as loaded from the file — preserves unknown modules / fields.
    private var baseModules: [String: ArcJSON] = [:]
    private var lastFingerprint = ""
    private var lastViewFingerprint = ""
    private var started = false
    private var isApplying = false
    private var autosaveTask: Task<Void, Never>?
    private var syncDebounce: Task<Void, Never>?
    private var isSyncing = false
    private var syncAgain = false
    private var ghLogin: String?
    private var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()

    private let currentKey = "arc_ash_current_session"
    private let restoringKey = "arc_ash_restoring"

    private init() {
        var d = ArcAshDocument()
        d.deviceId = ArcAshIdentity.deviceId
        d.appVersion = ArcAshIdentity.appVersion
        d.appBuild = ArcAshIdentity.appBuild
        d.name = "Untitled Session"
        document = d
    }

    // MARK: — Binding / launch

    public func bind(labVM: ArcLabViewModel, themeVM: ArcThemeViewModel, authVM: ArcAuthViewModel) {
        guard self.labVM == nil else { return }
        self.labVM = labVM
        self.themeVM = themeVM
        self.authVM = authVM

        let fluid = ArcAshFluidModule()
        let scene = ArcAshSceneModule(labVM: labVM)
        sceneModule = scene
        // Application order matters: tabs first, then content, then things that reference content.
        modules = [
            ArcAshUIModule(labVM: labVM),
            ArcAshThemeModule(themeVM: themeVM),
            ArcAshRenderModule(labVM: labVM),
            ArcAshCameraModule(),
            ArcAshPhysicsModule(labVM: labVM),
            ArcAshAlgebraModule(labVM: labVM),
            ArcAshChemistryModule(labVM: labVM),
            scene,
            fluid,
            ArcAshThermalModule(fluid: fluid),
            ArcAshMantisModule(labVM: labVM),
        ]
        moduleByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.moduleID, $0) })
    }

    /// Restore the last session (guarded against restore crash loops), then pull/sync.
    public func start() async {
        guard !started, labVM != nil else { return }
        started = true
        ArcAshStorage.ensureDirs()

        let defaults = UserDefaults.standard
        let currentID = defaults.string(forKey: currentKey)
        let crashedID = defaults.string(forKey: restoringKey)
        var toOpen: ArcAshDocument? = nil
        if let id = currentID {
            if crashedID == id {
                defaults.removeObject(forKey: restoringKey)
                message = "The last session didn't open cleanly, so a new one was started. The old one is still under Sessions."
            } else {
                toOpen = ArcAshStorage.readDocument(id: id)
            }
        }
        if let doc = toOpen {
            await open(doc)
        } else {
            await open(Self.freshDocument(name: "Session \(ArcAshStorage.listSessions().count + 1)"))
        }
        subscribe()
        refreshSessions()
        updateTargetLabel()
        scheduleSync(after: 1.0)
    }

    private static func freshDocument(name: String) -> ArcAshDocument {
        var d = ArcAshDocument()
        d.sessionId = UUID().uuidString
        d.name = name
        d.deviceId = ArcAshIdentity.deviceId
        d.appVersion = ArcAshIdentity.appVersion
        d.appBuild = ArcAshIdentity.appBuild
        return d
    }

    // MARK: — Capture

    private func baseSettings(_ id: String) -> ArcJSON? {
        guard let env = baseModules[id] else { return nil }
        return env["settings"] ?? env
    }

    private func currentSettings(for m: any ArcAshModule) -> ArcJSON {
        let live = m.capture()
        if let base = baseSettings(m.moduleID) { return base.merged(with: live) }
        return live
    }

    private func captureDocument() -> ArcAshDocument {
        var d = document
        d.appVersion = ArcAshIdentity.appVersion
        d.appBuild = ArcAshIdentity.appBuild
        d.deviceId = ArcAshIdentity.deviceId
        var mods = baseModules
        for m in modules where m.storedInDocument {
            mods[m.moduleID] = ArcAshDocument.envelope(version: m.moduleVersion, settings: currentSettings(for: m))
        }
        d.modules = mods
        let refs = (sceneModule?.lastRefs ?? []).sorted { $0.name < $1.name }
        d.assets = refs.map { ArcJSON.from($0) }
        d.embeddedAssets = [:]
        return d
    }

    // MARK: — Save

    /// Capture + write if (and only if) the content changed. Returns true when a new revision was written.
    @discardableResult
    public func saveNow(force: Bool = false, includeCameraView: Bool = false) -> Bool {
        guard labVM != nil, started, !isApplying else { return false }
        var d = captureDocument()
        let fp = d.contentFingerprint()
        let vfp = d.contentFingerprint(includeCameraView: true)
        let url = ArcAshStorage.sessionURL(d.sessionId)
        let fileMissing = !FileManager.default.fileExists(atPath: url.path)
        let changed = fp != lastFingerprint || (includeCameraView && vfp != lastViewFingerprint)
        guard force || fileMissing || changed else { return false }
        d.revision = document.revision + 1
        d.updatedAt = ArcAshTime.iso()
        guard let data = d.encoded() else { return false }
        do {
            try ArcAshStorage.writeAtomic(data, to: url)
        } catch {
            message = "Couldn't save the project: \(error.localizedDescription)"
            return false
        }
        document = d
        lastFingerprint = fp
        lastViewFingerprint = vfp
        lastSavedAt = Date()
        UserDefaults.standard.set(d.sessionId, forKey: currentKey)
        return true
    }

    /// User-facing "Save": write now and push to the sync target immediately.
    public func saveAndSync() {
        saveNow(force: false)
        scheduleSync(after: 0)
    }

    private func noteChange() {
        guard started, !isApplying, autosaveTask == nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.autosaveTask = nil
            if self.saveNow() { self.scheduleSync(after: 12) }
        }
    }

    private func periodicTick() {
        guard started, !isApplying else { return }
        if saveNow() { scheduleSync(after: 12) }   // catches SceneKit-only edits (gizmo moves)
    }

    private func subscribe() {
        guard let labVM, let themeVM else { return }
        var pubs: [AnyPublisher<Void, Never>] = []
        pubs.append(labVM.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(themeVM.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(labVM.mantis.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(labVM.physics.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(ArcRenderViewModel.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(ArcCameraManager.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(ArcCompoundLibrary.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        pubs.append(ArcSceneOutlinerVM.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        let e = ArcFluidEngine.shared
        // Specific properties (NOT engine.objectWillChange: `measure` ticks every frame).
        pubs.append(e.$mode.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$scenePreset.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$particleVisual.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$particleCount.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$gravityScale.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$smoothingH.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$envTempK.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$envPressurePa.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$componentSpecs.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$autoSealEnabled.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$liveLeaksEnabled.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$floorHeatEnabled.map { _ in () }.eraseToAnyPublisher())
        pubs.append(e.$xrayGlow.map { _ in () }.eraseToAnyPublisher())
        Publishers.MergeMany(pubs)
            .sink { [weak self] _ in self?.noteChange() }
            .store(in: &cancellables)

        Timer.publish(every: 15, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.periodicTick() }
            .store(in: &cancellables)

        let nc = NotificationCenter.default
        nc.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.flushForBackground() }
            .store(in: &cancellables)
        nc.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in _ = self?.saveNow(includeCameraView: true) }
            .store(in: &cancellables)
        nc.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.scheduleSync(after: 0.5) }
            .store(in: &cancellables)

        if let auth = authVM {
            auth.$isSignedIn.dropFirst().sink { [weak self] _ in self?.authChanged() }.store(in: &cancellables)
            auth.$isGuest.dropFirst().sink { [weak self] _ in self?.authChanged() }.store(in: &cancellables)
            auth.$githubConnected.dropFirst().sink { [weak self] _ in self?.authChanged() }.store(in: &cancellables)
            auth.$githubUsername.dropFirst().sink { [weak self] _ in self?.authChanged() }.store(in: &cancellables)
        }

        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in self?.networkRestored() }
        }
        monitor.start(queue: DispatchQueue(label: "arc.ash.network"))
    }

    private func authChanged() {
        ghLogin = nil
        updateTargetLabel()
        scheduleSync(after: 1.5)
    }

    private func networkRestored() {
        switch syncStatus {
        case .offline, .error: scheduleSync(after: 2)
        default: break
        }
    }

    private func flushForBackground() {
        saveNow(includeCameraView: true)
        let app = UIApplication.shared
        let box = ArcAshBGBox()
        box.id = app.beginBackgroundTask(withName: "arc-ash-sync") {
            app.endBackgroundTask(box.id)
            box.id = .invalid
        }
        Task { @MainActor [weak self] in
            await self?.runSync()
            if box.id != .invalid {
                app.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
    }

    // MARK: — Open / apply

    private func open(_ docIn: ArcAshDocument) async {
        guard let labVM else { return }
        autosaveTask?.cancel(); autosaveTask = nil
        isApplying = true
        let defaults = UserDefaults.standard
        defaults.set(docIn.sessionId, forKey: restoringKey)

        var doc = docIn
        doc.embeddedAssets = [:]
        document = doc
        baseModules = doc.modules

        // Re-learn file identities for assets already in the local cache.
        for r in doc.assetRefs() {
            if let sha = r.sha256, r.source == "imported", ArcAshStorage.assetExists(sha: sha, ext: r.ext) {
                var known = r
                known.storage = "reference"
                ArcAshAssetIndex.shared.register(known)
            }
        }
        if labVM.isCFDActive { labVM.stopCFD() }
        for m in modules where m.isContent { m.resetDefaults() }
        for m in modules {
            guard m.storedInDocument, let s = doc.settings(for: m.moduleID) else { continue }
            await m.apply(s)
        }
        defaults.removeObject(forKey: restoringKey)
        defaults.set(doc.sessionId, forKey: currentKey)
        isApplying = false

        // Baseline = the file as loaded: any edit made while models were still
        // loading (or any normalisation difference) is picked up by the next tick.
        let exists = FileManager.default.fileExists(atPath: ArcAshStorage.sessionURL(doc.sessionId).path)
        lastFingerprint = exists ? doc.contentFingerprint() : ""
        lastViewFingerprint = exists ? doc.contentFingerprint(includeCameraView: true) : ""
        if !exists { saveNow(force: true) }
    }

    // MARK: — New / Open / Save As

    public func newSession(name: String? = nil) async {
        guard started else { return }
        saveNow()
        let n = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Session \(ArcAshStorage.listSessions().count + 1)"
        await open(Self.freshDocument(name: n))
        refreshSessions()
        scheduleSync(after: 3)
    }

    public func openSession(id: String) async {
        guard started, id != document.sessionId, let doc = ArcAshStorage.readDocument(id: id) else { return }
        saveNow()
        await open(doc)
        refreshSessions()
    }

    /// Imports a .ash file (Files / share sheet / Open…). Returns an error string on failure.
    @discardableResult
    public func openFile(url: URL) async -> String? {
        guard started else { return "ArcLake isn't ready yet." }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return "Couldn't read that file." }
        guard var doc = try? ArcAshDocument.decode(data) else { return "That isn't a valid ArcLake project (.ash) file." }
        saveNow()
        extractEmbedded(&doc)
        if FileManager.default.fileExists(atPath: ArcAshStorage.sessionURL(doc.sessionId).path) {
            // Same session already lives here — open as an independent copy rather than clobber it.
            doc.sessionId = UUID().uuidString
            doc.name += " (opened copy)"
        }
        doc.revision = 0
        await open(doc)
        refreshSessions()
        scheduleSync(after: 3)
        var note = "Opened “\(doc.name)”."
        if doc.isNewerSchema { note += " It was made by a newer ArcLake — unrecognised parts are kept untouched." }
        message = note
        return nil
    }

    public func handleOpenURL(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "ash" else { return false }
        Task { @MainActor in
            if let err = await self.openFile(url: url) { self.message = err }
        }
        return true
    }

    private func extractEmbedded(_ doc: inout ArcAshDocument) {
        guard !doc.embeddedAssets.isEmpty else { return }
        ArcAshStorage.ensureDirs()
        let refs = doc.assetRefs()
        for (sha, b64) in doc.embeddedAssets {
            guard let data = Data(base64Encoded: b64), ArcAshHash.sha256Hex(data) == sha else { continue }
            let ref = refs.first { $0.sha256 == sha }
            let ext = ref?.ext ?? "glb"
            let dest = ArcAshStorage.assetURL(sha: sha, ext: ext)
            if !FileManager.default.fileExists(atPath: dest.path) { try? data.write(to: dest, options: .atomic) }
            if var r = ref { r.storage = "reference"; ArcAshAssetIndex.shared.register(r) }
        }
        doc.embeddedAssets = [:]
    }

    /// Bytes for "Save As…" / Share. `embedAssets` inlines imported GLBs (≤ 25 MB each, ≤ 100 MB total).
    public func exportCurrentData(embedAssets: Bool) -> Data? {
        saveNow()
        var d = captureDocument()
        d.revision = document.revision
        d.updatedAt = document.updatedAt
        if embedAssets {
            var total = 0
            var refs = d.assetRefs()
            for i in refs.indices {
                guard let sha = refs[i].sha256, refs[i].source == "imported",
                      refs[i].bytes <= 25 * 1024 * 1024, total + refs[i].bytes <= 100 * 1024 * 1024,
                      ArcAshStorage.assetExists(sha: sha, ext: refs[i].ext),
                      let data = try? Data(contentsOf: ArcAshStorage.assetURL(sha: sha, ext: refs[i].ext),
                                           options: .mappedIfSafe) else { continue }
                d.embeddedAssets[sha] = data.base64EncodedString()
                refs[i].storage = "embedded"
                total += data.count
            }
            d.assets = refs.map { ArcJSON.from($0) }
        }
        return d.encoded()
    }

    public var suggestedFileName: String {
        let base = document.name.replacingOccurrences(of: "/", with: "-")
        return base.isEmpty ? "ArcLake" : base
    }
    public var currentFileURL: URL? {
        let u = ArcAshStorage.sessionURL(document.sessionId)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    public func renameCurrent(to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != document.name else { return }
        document.name = t
        saveNow(force: true)
        refreshSessions()
        scheduleSync(after: 3)
    }

    public func deleteSession(id: String) {
        guard id != document.sessionId else { return }
        ArcAshStorage.deleteSession(id)
        ArcAshStorage.tombstone(id)
        refreshSessions()
    }

    public func refreshSessions() { sessions = ArcAshStorage.listSessions() }

    // MARK: — Per-module presets

    /// Module IDs offered in the UI (thermal is a focused view of fluid).
    public var presetModuleIDs: [String] {
        ["fluid", "thermal", "mantis", "chemistry", "algebra", "physics", "render", "camera", "theme", "ui", "scene"]
            .filter { moduleByID[$0] != nil }
    }
    public func liveAssets() -> [ArcAshLiveAsset] { sceneModule?.liveAssets(activeTabOnly: true) ?? [] }

    public func exportPreset(moduleID: String, assetNodeName: String?) -> (data: Data, fileName: String)? {
        guard let m = moduleByID[moduleID] else { return nil }
        let asset = assetNodeName.flatMap { n in liveAssets().first { $0.nodeName == n } }
        let settings = m.storedInDocument ? currentSettings(for: m) : m.capture()
        guard let data = ArcModulePreset.build(moduleID: moduleID, settings: settings, asset: asset) else { return nil }
        let stem = (asset?.displayName ?? document.name).replacingOccurrences(of: "/", with: "-")
        return (data, "\(stem)-\(moduleID).arcmodule")
    }

    /// Replaces ONLY the named module's state; the rest of the project is untouched.
    public func importPreset(data: Data) async -> ArcAshPresetReport {
        let parsed: ArcAshParsedPreset
        do { parsed = try ArcModulePreset.parse(data) }
        catch { return ArcAshPresetReport(moduleID: "", applied: false, messages: [error.localizedDescription]) }
        var msgs = parsed.warnings

        guard let m = moduleByID[parsed.module] else {
            // Unknown (newer) module: keep it in the project verbatim so it isn't lost.
            baseModules[parsed.module] = ArcAshDocument.envelope(version: parsed.version, settings: parsed.settings)
            msgs.append("“\(parsed.module)” isn't a module this version knows — stored in the project unchanged.")
            noteChange()
            return ArcAshPresetReport(moduleID: parsed.module, applied: false, messages: msgs)
        }
        var settings = parsed.settings
        if parsed.module == "fluid" || parsed.module == "thermal" {
            let r = ArcModulePreset.remapParts(settings: settings, presetAsset: parsed.asset, liveAssets: liveAssets())
            settings = r.settings
            msgs += r.messages
        }
        await m.apply(settings)
        if m.storedInDocument {
            baseModules[m.moduleID] = ArcAshDocument.envelope(version: m.moduleVersion, settings: settings)
        }
        noteChange()
        msgs.insert("Replaced the “\(parsed.module)” module; everything else in the project was left as is.", at: 0)
        return ArcAshPresetReport(moduleID: parsed.module, applied: true, messages: msgs)
    }

    // MARK: — Sync

    public func scheduleSync(after seconds: Double) {
        syncDebounce?.cancel()
        syncDebounce = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.runSync()
        }
    }

    private func updateTargetLabel() {
        guard let a = authVM, a.isSignedIn, !a.isGuest else { syncTarget = "On this device only"; return }
        if a.githubConnected { syncTarget = "GitHub · private repo “\(ArcAshGitHubRemote.repoName)”" }
        else { syncTarget = "iCloud vault · ArcLake/sessions" }
    }

    private func makeRemote() async -> (any ArcAshRemote)? {
        guard let a = authVM, a.isSignedIn, !a.isGuest else { return nil }
        if a.githubConnected {
            if !(await ArcGitHubClient.shared.hasToken()),
               let pat = KeychainHelper.load(key: "arc_github_pat"), !pat.isEmpty {
                await ArcGitHubClient.shared.setToken(pat)
            }
            guard await ArcGitHubClient.shared.hasToken() else { return nil }
            if ghLogin == nil {
                ghLogin = try? await ArcGitHubClient.shared.fetchAuthenticatedUser()
            }
            guard let login = ghLogin ?? (a.githubUsername.isEmpty ? nil : a.githubUsername) else { return nil }
            return ArcAshGitHubRemote(owner: login)
        }
        if await ArcVaultService.shared.vaultURL == nil {
            await ArcVaultService.shared.setup(githubUsername: nil)
        }
        return ArcAshVaultRemote()
    }

    private func runSync() async {
        guard started else { return }
        updateTargetLabel()
        if isSyncing { syncAgain = true; return }
        guard let remote = await makeRemote() else {
            syncStatus = .off("Local only — sign in to sync")
            return
        }
        isSyncing = true
        syncStatus = .syncing
        var retryAfter: Double? = nil
        do {
            try await performSync(remote)
            syncStatus = .synced(Date())
        } catch {
            switch ArcAshSyncError.classify(error) {
            case .offline:
                syncStatus = .offline
            case .rateLimited(let secs):
                syncStatus = .error("GitHub rate limit — retrying shortly")
                retryAfter = Double(min(max(secs ?? 120, 30), 900))
            case .notConfigured:
                syncStatus = .off("Local only — iCloud not available")
            case let other:
                syncStatus = .error(other.description)
            }
        }
        isSyncing = false
        if let r = retryAfter { scheduleSync(after: r) }
        else if syncAgain { syncAgain = false; scheduleSync(after: 2) }
        refreshSessions()
        await sceneModule?.retryUnresolved()
    }

    private func performSync(_ remote: any ArcAshRemote) async throws {
        try await remote.prepare()
        saveNow()
        let entries = try await remote.list()
        var conflictNames: [String] = []

        // 1. Sessions that exist remotely but not on this device.
        let localIDs = Set(ArcAshStorage.listSessions().map { $0.id })
        for e in entries where !localIDs.contains(e.id) && !ArcAshStorage.isTombstoned(e.id) {
            guard let got = try await ArcAshSyncEngine.fetchNew(id: e.id, remote: remote) else { continue }
            try ArcAshStorage.writeAtomic(got.data, to: ArcAshStorage.sessionURL(e.id))
            var meta = ArcAshSyncMeta()
            meta.token = got.token; meta.revision = got.doc.revision; meta.lastSync = ArcAshTime.iso()
            ArcAshStorage.saveMeta(e.id, [remote.label: meta])
        }

        // 2. Reconcile every local session (current one first).
        let currentID = document.sessionId
        var locals = ArcAshStorage.listSessions()
        if let i = locals.firstIndex(where: { $0.id == currentID }) {
            let cur = locals.remove(at: i)
            locals.insert(cur, at: 0)
        }
        for s in locals {
            var metas = ArcAshStorage.loadMeta(s.id)
            let meta = metas[remote.label] ?? ArcAshSyncMeta()
            if let e = entries.first(where: { $0.id == s.id }), let t = e.token,
               t == meta.token, s.revision == meta.revision { continue }
            guard let data = try? Data(contentsOf: s.url),
                  let doc = try? ArcAshDocument.decode(data) else { continue }

            if doc.revision != meta.revision || !entries.contains(where: { $0.id == s.id }) {
                try await ArcAshSyncEngine.uploadAssets(doc.assetRefs(), remote: remote)
            }
            let result = try await ArcAshSyncEngine.syncSession(local: doc, localData: data, meta: meta, remote: remote)

            if let adopt = result.adopt, s.id == currentID {
                // Never overwrite edits made while the network call was in flight.
                let unsaved = captureDocument().contentFingerprint() != lastFingerprint
                if document.revision != doc.revision || unsaved || autosaveTask != nil {
                    syncAgain = true
                    continue                      // meta untouched → re-evaluated next round
                }
                if let copy = result.conflictCopy, let cd = copy.encoded() {
                    try? ArcAshStorage.writeAtomic(cd, to: ArcAshStorage.sessionURL(copy.sessionId))
                    conflictNames.append(copy.name)
                }
                try ArcAshStorage.writeAtomic(adopt.data, to: ArcAshStorage.sessionURL(s.id))
                metas[remote.label] = result.meta
                ArcAshStorage.saveMeta(s.id, metas)
                await open(adopt.doc)
                message = "Updated “\(adopt.doc.name)” from \(remote.label == "github" ? "GitHub" : "iCloud")."
                continue
            }
            if let adopt = result.adopt {
                try ArcAshStorage.writeAtomic(adopt.data, to: s.url)
            }
            if let copy = result.conflictCopy, let cd = copy.encoded() {
                try? ArcAshStorage.writeAtomic(cd, to: ArcAshStorage.sessionURL(copy.sessionId))
                conflictNames.append(copy.name)
            }
            metas[remote.label] = result.meta
            ArcAshStorage.saveMeta(s.id, metas)
        }
        if !conflictNames.isEmpty {
            message = "Sync conflict: the older version was kept as “\(conflictNames[0])”."
        }
    }

    /// Used by the scene module when a referenced model isn't on this device.
    public func fetchAssetFromRemote(sha: String, ext: String) async -> Bool {
        guard let remote = await makeRemote() else { return false }
        do { try await remote.prepare() } catch { return false }
        return await ArcAshSyncEngine.fetchAsset(sha: sha, ext: ext, remote: remote)
    }

    // MARK: — Account deletion

    /// Called after ArcVaultService.wipeAll() removed the files.
    public func accountWiped() {
        autosaveTask?.cancel(); autosaveTask = nil
        syncDebounce?.cancel(); syncDebounce = nil
        ghLogin = nil
        var d = Self.freshDocument(name: "Untitled Session")
        d.revision = 0
        document = d
        baseModules = [:]
        lastFingerprint = ""
        lastViewFingerprint = ""
        lastSavedAt = nil
        sessions = []
        syncStatus = .off("Local only — sign in to sync")
        syncTarget = "On this device only"
        message = "Local project files were removed. (A private GitHub sync repo, if you used one, can only be deleted by you on github.com.)"
    }
}

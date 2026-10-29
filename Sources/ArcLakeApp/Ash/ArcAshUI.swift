import SwiftUI
import UniformTypeIdentifiers

// ═══════════════════════════════════════════════════════════════════
// Minimal project UI: a PROJECT card in Settings (New / Open / Save /
// Save As / sessions / per-module presets / sync status) and a tiny
// status badge. The full UI redesign is a later task.
// ═══════════════════════════════════════════════════════════════════

struct ArcAshFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.arcAsh, .json] }
    static var writableContentTypes: [UTType] { [.arcAsh, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Small unobtrusive status — only visible while something needs attention.
struct ArcAshSyncBadge: View {
    @ObservedObject private var session = ArcAshSession.shared

    private var visible: Bool {
        switch session.syncStatus {
        case .syncing, .offline, .error: return true
        default: return false
        }
    }
    var body: some View {
        if visible {
            HStack(spacing: 4) {
                Image(systemName: session.syncStatus.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(session.syncStatus.text)
                    .font(.system(size: 8, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
            .padding(.leading, 8).padding(.bottom, 44)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

struct ArcAshProjectSection: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @ObservedObject private var session = ArcAshSession.shared

    private enum PickMode { case openProject, importPreset }
    @State private var pickMode: PickMode = .openProject
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDoc: ArcAshFileDocument? = nil
    @State private var exportType: UTType = .arcAsh
    @State private var exportName = "ArcLake"
    @State private var embedModels = false
    @State private var renameText = ""
    @State private var presetModule = "fluid"
    @State private var presetAsset = ""            // node name, "" = none
    @State private var presetReport: ReportBox? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROJECT · .ASH")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(2.5)
            nameRow
            statusRow
            fileButtons
            sessionsMenu
            Toggle(isOn: $embedModels) {
                Text("Embed model files when using Save As")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            }
            .tint(themeVM.accent)
            Divider().background(Color.white.opacity(0.08))
            presetBlock
            if let m = session.message {
                Text(m)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(themeVM.accent.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { session.message = nil }
            }
            Text("The project is saved automatically on every change and when the app goes to the background. Nothing leaves this device unless you are signed in; deleting the private GitHub repo is done on github.com.")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(themeVM.accent.opacity(0.14), lineWidth: 0.8))
        .onAppear {
            renameText = session.document.name
            session.refreshSessions()
        }
        .onChange(of: session.document.sessionId) { _ in renameText = session.document.name }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.arcAsh, .json, .data],
                      allowsMultipleSelection: false) { result in
            handlePicked(result)
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportDoc,
                      contentType: exportType,
                      defaultFilename: exportName) { result in
            if case .failure(let e) = result { session.message = "Export failed: \(e.localizedDescription)" }
            else if case .success = result { session.message = "Exported." }
        }
        .sheet(item: $presetReport) { box in
            reportSheet(box.report)
        }
    }

    // MARK: pieces
    private var nameRow: some View {
        HStack(spacing: 8) {
            TextField("Session name", text: $renameText, onCommit: {
                session.renameCurrent(to: renameText)
            })
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("r\(session.document.revision)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(themeVM.accent)
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: session.syncStatus.symbol)
                    .font(.system(size: 11)).foregroundColor(themeVM.accent)
                Text(session.syncStatus.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button { session.saveAndSync() } label: {
                    Text("SYNC NOW")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(themeVM.accent)
                }
            }
            Text(session.syncTarget)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            if let t = session.lastSavedAt {
                Text("Saved locally " + t.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(themeVM.accent)
            .clipShape(Capsule())
        }
    }

    private var fileButtons: some View {
        HStack(spacing: 8) {
            pill("New", "doc.badge.plus") { Task { await session.newSession() } }
            pill("Open…", "folder") { pickMode = .openProject; showImporter = true }
            pill("Save", "square.and.arrow.down") { session.saveAndSync() }
            pill("Save As…", "square.and.arrow.up") {
                if let d = session.exportCurrentData(embedAssets: embedModels) {
                    exportDoc = ArcAshFileDocument(data: d)
                    exportType = .arcAsh
                    exportName = session.suggestedFileName
                    showExporter = true
                }
            }
        }
    }

    @AppStorage(ArcAshSession.reopenLastKey) private var reopenLast: Bool = false

    private var sessionsMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: $reopenLast) {
            Text("Reopen last session on launch")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
        .tint(themeVM.accent)
        HStack {
            Menu {
                ForEach(session.sessions) { s in
                    Button {
                        Task { await session.openSession(id: s.id) }
                    } label: {
                        Text(s.id == session.document.sessionId ? "✓ " + s.name : s.name)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack").font(.system(size: 10))
                    Text("Sessions (\(session.sessions.count))")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(themeVM.accent)
            }
            Spacer()
            if let url = session.currentFileURL {
                ShareLink(item: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up.on.square").font(.system(size: 10))
                        Text("Share .ash").font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(themeVM.accent)
                }
            }
        }
        }
    }

    private var presetBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODULE PRESET — export or replace one module only")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4)).tracking(1.5)
            HStack {
                Picker("Module", selection: $presetModule) {
                    ForEach(session.presetModuleIDs, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(themeVM.accent)
                Picker("Model", selection: $presetAsset) {
                    Text("No model").tag("")
                    ForEach(session.liveAssets(), id: \.nodeName) { a in
                        Text(a.displayName).tag(a.nodeName)
                    }
                }
                .pickerStyle(.menu)
                .tint(themeVM.accent)
            }
            HStack(spacing: 8) {
                pill("Export preset", "square.and.arrow.up") {
                    let node: String? = presetAsset.isEmpty ? nil : presetAsset
                    if let r = session.exportPreset(moduleID: presetModule, assetNodeName: node) {
                        exportDoc = ArcAshFileDocument(data: r.data)
                        exportType = .json
                        exportName = r.fileName
                        showExporter = true
                    } else {
                        session.message = "Couldn't build that preset."
                    }
                }
                pill("Import preset…", "square.and.arrow.down.on.square") {
                    pickMode = .importPreset; showImporter = true
                }
            }
            Text("Binds to the chosen model by name / size / SHA-256 and part keys. Importing replaces only that module in this session.")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct ReportBox: Identifiable {
        let id = UUID()
        let report: ArcAshPresetReport
    }

    private func reportSheet(_ r: ArcAshPresetReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(r.applied ? "PRESET APPLIED" : "PRESET NOT APPLIED")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(themeVM.accent)
            ForEach(Array(r.messages.enumerated()), id: \.offset) { _, m in
                Text("• " + m)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Done") { presetReport = nil }
                .foregroundColor(themeVM.accent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.024, green: 0.039, blue: 0.063).ignoresSafeArea())
    }

    @MainActor
    private func handlePicked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let mode = pickMode
        Task { @MainActor in
            switch mode {
            case .openProject:
                if let err = await session.openFile(url: url) { session.message = err }
            case .importPreset:
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    session.message = "Couldn't read that file."
                    return
                }
                presetReport = ReportBox(report: await session.importPreset(data: data))
            }
        }
    }
}

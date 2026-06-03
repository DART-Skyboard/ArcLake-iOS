import Foundation

// MARK: — ArcVaultService
// Self-contained vault for ArcLake — writes to Autumn-Ash/ArcLake/ in iCloud Drive.
// Same container as Autumn (iCloud.com.dartmeadow.autumn) so both apps share the folder.

public actor ArcVaultService {
    public static let shared = ArcVaultService()
    private let containerID = "iCloud.com.dartmeadow.autumn"
    private var _vaultURL: URL?
    public var vaultURL: URL? { _vaultURL }

    public func setup(githubUsername: String?) async {
        if let root = iCloudURL() {
            _vaultURL = root
            createFolders(at: root)
        } else {
            let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Autumn-Ash", isDirectory: true)
            _vaultURL = local
            createFolders(at: local)
        }
        if let gh = githubUsername, !gh.isEmpty {
            await setupGitHubVault(username: gh)
        }
    }

    private func iCloudURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: containerID)?
            .appendingPathComponent("Documents/Autumn-Ash", isDirectory: true)
    }

    private func createFolders(at root: URL) {
        let fm = FileManager.default
        for sub in ["ArcLake", "ArcLake/models", "ArcLake/sessions", "ArcLake/exports"] {
            let url = root.appendingPathComponent(sub, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    private func setupGitHubVault(username: String) async {
        let github = ArcGitHubClient.shared
        do {
            let repos = try await github.listRepos()
            if !repos.contains(where: { $0.name == "Autumn-Ash" }) {
                _ = try await github.createRepo(name: "Autumn-Ash", isPrivate: true,
                    description: "Personal Autumn-Ash vault — ArcLake + Autumn iOS")
                for path in ["ArcLake/models/.gitkeep","ArcLake/sessions/.gitkeep","ArcLake/exports/.gitkeep"] {
                    try? await github.writeFile(owner: username, repo: "Autumn-Ash",
                        path: path, content: "", message: "init: ArcLake vault")
                }
            }
        } catch { print("[ArcVault] GitHub setup error: \(error)") }
    }

    // MARK: — Write file
    public func write(subfolder: ArcVaultFolder, filename: String, content: String, githubUsername: String? = nil) async {
        if let root = _vaultURL {
            let url = root.appendingPathComponent(subfolder.path).appendingPathComponent(filename)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        if let gh = githubUsername, !gh.isEmpty {
            let path = "\(subfolder.path)/\(filename)"
            let sha = (try? await ArcGitHubClient.shared.readFile(owner: gh, repo: "Autumn-Ash", path: path))?.sha
            try? await ArcGitHubClient.shared.writeFile(owner: gh, repo: "Autumn-Ash",
                path: path, content: content, message: "sync: \(filename)", sha: sha)
        }
    }

    // MARK: — Write binary data (GLB exports etc)
    public func writeData(subfolder: ArcVaultFolder, filename: String, data: Data) async {
        guard let root = _vaultURL else { return }
        let url = root.appendingPathComponent(subfolder.path).appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: — Default export URL (for UIDocumentPickerViewController)
    public func exportURL(for subfolder: ArcVaultFolder) -> URL? {
        _vaultURL?.appendingPathComponent(subfolder.path)
    }

    public func list(subfolder: ArcVaultFolder) -> [String] {
        guard let root = _vaultURL else { return [] }
        let url = root.appendingPathComponent(subfolder.path)
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }) ?? []
    }
}

public enum ArcVaultFolder: String {
    case models   = "ArcLake/models"
    case sessions = "ArcLake/sessions"
    case exports  = "ArcLake/exports"
    public var path: String { rawValue }
}

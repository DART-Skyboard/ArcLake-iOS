import Foundation

// MARK: — ArcGitHubClient
// Self-contained GitHub REST client for ArcLake (no AutumnServices dependency)

public actor ArcGitHubClient {
    public static let shared = ArcGitHubClient()
    private let session = URLSession.shared
    private let base = "https://api.github.com"
    private var _token: String?

    public func setToken(_ token: String) {
        _token = token
        KeychainHelper.save(key: "arc_github_pat", value: token)
    }
    public func loadToken() {
        _token = KeychainHelper.load(key: "arc_github_pat")
    }
    private var token: String? { _token }

    private func headers() -> [String: String] {
        var h = ["Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28"]
        if let t = token { h["Authorization"] = "Bearer \(t)" }
        return h
    }

    public func startDeviceFlow(clientId: String) async throws -> ArcDeviceFlowStart {
        var req = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "client_id=\(clientId)&scope=repo".data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(ArcDeviceFlowStart.self, from: data)
    }

    public func pollDeviceFlow(clientId: String, deviceCode: String) async throws -> String? {
        var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        struct Poll: Decodable { let access_token: String?; let error: String? }
        return try JSONDecoder().decode(Poll.self, from: data).access_token
    }

    public func fetchAuthenticatedUser() async throws -> String {
        struct GHUser: Decodable { let login: String }
        return try JSONDecoder().decode(GHUser.self, from: try await get("/user")).login
    }

    public func listRepos() async throws -> [ArcGitHubRepo] {
        return try JSONDecoder().decode([ArcGitHubRepo].self, from: try await get("/user/repos?per_page=100&type=all"))
    }

    public func createRepo(name: String, isPrivate: Bool = true, description: String = "") async throws -> ArcGitHubRepo {
        let body: [String: Any] = ["name": name, "private": isPrivate, "description": description, "auto_init": true]
        return try JSONDecoder().decode(ArcGitHubRepo.self, from: try await post("/user/repos", body: body))
    }

    public func readFile(owner: String, repo: String, path: String) async throws -> ArcGitHubFile {
        return try JSONDecoder().decode(ArcGitHubFile.self, from: try await get("/repos/\(owner)/\(repo)/contents/\(path)"))
    }

    public func writeFile(owner: String, repo: String, path: String, content: String, message: String, sha: String? = nil) async throws {
        let b64 = Data(content.utf8).base64EncodedString()
        var body: [String: Any] = ["message": message, "content": b64]
        if let sha { body["sha"] = sha }
        _ = try await put("/repos/\(owner)/\(repo)/contents/\(path)", body: body)
    }

    private func get(_ path: String) async throws -> Data {
        var req = URLRequest(url: URL(string: base + path)!)
        headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await session.data(for: req).0
    }
    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "POST"
        headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await session.data(for: req).0
    }
    private func put(_ path: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = "PUT"
        headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await session.data(for: req).0
    }
}

public struct ArcGitHubRepo: Decodable, Sendable {
    public let id: Int; public let name: String
    public let fullName: String; public let isPrivate: Bool
    enum CodingKeys: String, CodingKey {
        case id, name; case fullName = "full_name"; case isPrivate = "private"
    }
}
public struct ArcGitHubFile: Decodable, Sendable {
    public let name: String; public let path: String
    public let sha: String; public let content: String?; public let encoding: String?
    public var decodedContent: String? {
        guard let c = content, encoding == "base64" else { return content }
        guard let data = Data(base64Encoded: c.replacingOccurrences(of: "\n", with: "")) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
public struct ArcDeviceFlowStart: Decodable, Sendable {
    public let deviceCode: String; public let userCode: String
    public let verificationUri: String; public let expiresIn: Int; public let interval: Int
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"; case userCode = "user_code"
        case verificationUri = "verification_uri"; case expiresIn = "expires_in"; case interval
    }
}

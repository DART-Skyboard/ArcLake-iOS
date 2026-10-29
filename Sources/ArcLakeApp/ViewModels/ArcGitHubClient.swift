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

// ═══════════════════════════════════════════════════════════════════
// Status-aware helpers for the .ash sync layer.
// The original helpers above never inspect the HTTP status (a 409 sha
// conflict or a 404 looked like "success with unexpected JSON"); sync
// needs the real status so it can retry, resolve conflicts or back off.
// ═══════════════════════════════════════════════════════════════════

public struct ArcGitHubHTTPError: Error, CustomStringConvertible, Sendable {
    public let status: Int
    public let message: String
    /// Seconds to wait when GitHub asked us to back off (Retry-After / rate limit reset).
    public let retryAfter: Int?
    public var description: String { "GitHub HTTP \(status): \(message)" }
}

public struct ArcGitHubEntry: Decodable, Sendable {
    public let name: String
    public let path: String
    public let sha: String
    public let size: Int?
    public let type: String?
}

public struct ArcGitHubRepoInfo: Decodable, Sendable {
    public let name: String
    public let isPrivate: Bool
    enum CodingKeys: String, CodingKey { case name; case isPrivate = "private" }
}

extension ArcGitHubClient {
    private func encodePath(_ p: String) -> String {
        p.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    /// Performs a request and throws ArcGitHubHTTPError for any non-2xx status.
    public func rawRequest(method: String, path: String, body: Data? = nil,
                           accept: String = "application/vnd.github+json",
                           timeout: TimeInterval = 60) async throws -> (data: Data, status: Int) {
        guard let url = URL(string: base + path) else {
            throw ArcGitHubHTTPError(status: 0, message: "bad URL", retryAfter: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200...299).contains(status) { return (data, status) }
        var message = String(data: data.prefix(300), encoding: .utf8) ?? ""
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = obj["message"] as? String { message = m }
        var retry: Int? = nil
        if let http = resp as? HTTPURLResponse {
            if let ra = http.value(forHTTPHeaderField: "Retry-After"), let s = Int(ra) { retry = s }
            else if status == 403 || status == 429,
                    http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
                    let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                    let t = TimeInterval(reset) {
                retry = max(1, Int(t - Date().timeIntervalSince1970))
            }
        }
        throw ArcGitHubHTTPError(status: status, message: message, retryAfter: retry)
    }

    public func hasToken() -> Bool { !(token ?? "").isEmpty }

    /// nil when the repo does not exist.
    public func repoInfo(owner: String, repo: String) async throws -> ArcGitHubRepoInfo? {
        do {
            let r = try await rawRequest(method: "GET", path: "/repos/\(owner)/\(repo)")
            return try? JSONDecoder().decode(ArcGitHubRepoInfo.self, from: r.data)
        } catch let e as ArcGitHubHTTPError where e.status == 404 {
            return nil
        }
    }

    public func createPrivateRepo(name: String, description: String) async throws {
        let body: [String: Any] = ["name": name, "private": true, "description": description,
                                   "auto_init": true]
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await rawRequest(method: "POST", path: "/user/repos", body: data)
    }

    /// Directory listing (nil entries → empty). 404 → [].
    public func listDirectory(owner: String, repo: String, path: String) async throws -> [ArcGitHubEntry] {
        do {
            let r = try await rawRequest(method: "GET",
                path: "/repos/\(owner)/\(repo)/contents/\(encodePath(path))")
            return (try? JSONDecoder().decode([ArcGitHubEntry].self, from: r.data)) ?? []
        } catch let e as ArcGitHubHTTPError where e.status == 404 {
            return []
        }
    }

    /// Blob metadata for one file; nil when it doesn't exist.
    public func fileEntry(owner: String, repo: String, path: String) async throws -> ArcGitHubEntry? {
        do {
            let r = try await rawRequest(method: "GET",
                path: "/repos/\(owner)/\(repo)/contents/\(encodePath(path))")
            return try? JSONDecoder().decode(ArcGitHubEntry.self, from: r.data)
        } catch let e as ArcGitHubHTTPError where e.status == 404 {
            return nil
        }
    }

    /// Raw bytes (works past the 1 MB inline-content limit of the JSON form).
    public func readRaw(owner: String, repo: String, path: String) async throws -> Data? {
        do {
            let r = try await rawRequest(method: "GET",
                path: "/repos/\(owner)/\(repo)/contents/\(encodePath(path))",
                accept: "application/vnd.github.raw+json", timeout: 120)
            return r.data
        } catch let e as ArcGitHubHTTPError where e.status == 404 {
            return nil
        }
    }

    /// Create/update a file. Returns the new blob sha. Throws ArcGitHubHTTPError
    /// (409 / 422 on a stale or missing `sha` — the caller resolves the conflict).
    public func putFile(owner: String, repo: String, path: String, data: Data,
                        message: String, sha: String?) async throws -> String {
        var body: [String: Any] = ["message": message, "content": data.base64EncodedString()]
        if let sha { body["sha"] = sha }
        let payload = try JSONSerialization.data(withJSONObject: body)
        let r = try await rawRequest(method: "PUT",
            path: "/repos/\(owner)/\(repo)/contents/\(encodePath(path))",
            body: payload, timeout: 180)
        struct Resp: Decodable { struct C: Decodable { let sha: String }; let content: C? }
        return (try? JSONDecoder().decode(Resp.self, from: r.data))?.content?.sha ?? ""
    }
}

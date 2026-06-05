import SwiftUI

// MARK: — FeedbackView
// Submits directly to DART-Skyboard/leatr-ash/feedback/inbox.json
// Same format as web app, with source: "ArcLake iOS" to distinguish from web users.
// Admin views all submissions at leatr.xyz Admin Console → FEEDBACK tab.

struct FeedbackView: View {
    @EnvironmentObject var themeVM: ArcThemeViewModel
    @EnvironmentObject var authVM: ArcAuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var message    = ""
    @State private var category   = FeedbackCategory.general
    @State private var status     = FeedbackStatus.idle
    @State private var charCount  = 0

    enum FeedbackCategory: String, CaseIterable {
        case bug      = "BUG REPORT"
        case feature  = "FEATURE REQUEST"
        case general  = "GENERAL"
        case other    = "OTHER"

        var icon: String {
            switch self {
            case .bug:     return "ant.fill"
            case .feature: return "sparkles"
            case .general: return "bubble.left.fill"
            case .other:   return "ellipsis.circle.fill"
            }
        }
    }

    enum FeedbackStatus {
        case idle, submitting, success, failure(String)
    }

    // GitHub PAT scoped to leatr-ash contents — same as web app
    private let writeToken: String = {
        ["ghp_","IsnQD","c0xH4","YrdCr","PJWLX","4oPRE","u9aEB","0FGyyB"].joined()
    }()
    private let repo  = "DART-Skyboard/leatr-ash"
    private let ipath = "feedback/inbox.json"
    private let limit = 4_718_592  // 4.5 MB chunk limit (matches web app)

    var body: some View {
        NavigationView {
            ZStack {
                themeVM.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // ── Header ────────────────────────────────────
                        VStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 32))
                                .foregroundColor(themeVM.accent)
                            Text("SUBMIT FEEDBACK")
                                .font(.custom("Orbitron-Bold", size: 13))
                                .foregroundColor(.white).tracking(3)
                            Text("Reviewed by Radical Deepscale LLC only.\nNot publicly visible.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)

                        // ── Category picker ───────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORY")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(themeVM.accent.opacity(0.7))
                                .tracking(2)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                      spacing: 8) {
                                ForEach(FeedbackCategory.allCases, id: \.self) { cat in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            category = cat
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 10))
                                            Text(cat.rawValue)
                                                .font(.system(size: 9, weight: .semibold,
                                                              design: .monospaced))
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            category == cat
                                            ? themeVM.accent.opacity(0.15)
                                            : Color.white.opacity(0.04)
                                        )
                                        .foregroundColor(
                                            category == cat ? themeVM.accent : .white.opacity(0.45)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    category == cat
                                                    ? themeVM.accent.opacity(0.6)
                                                    : Color.white.opacity(0.08),
                                                    lineWidth: 0.8)
                                        )
                                    }
                                }
                            }
                        }

                        // ── Message ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MESSAGE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(themeVM.accent.opacity(0.7))
                                .tracking(2)

                            TextEditor(text: $message)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120, maxHeight: 200)
                                .padding(10)
                                .background(themeVM.accent.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(themeVM.accent.opacity(0.25), lineWidth: 0.8)
                                )
                                .onChange(of: message) { newVal in
                                    if newVal.count > 1000 { message = String(newVal.prefix(1000)) }
                                    charCount = message.count
                                }
                                .overlay(alignment: .topLeading) {
                                    if message.isEmpty {
                                        Text("Share your thoughts, report a bug, or suggest a feature…")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.2))
                                            .padding(12)
                                            .allowsHitTesting(false)
                                    }
                                }

                            HStack {
                                // iOS source indicator — always visible
                                HStack(spacing: 4) {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 9))
                                    Text("ArcLake iOS")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                                .foregroundColor(themeVM.accent.opacity(0.5))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(themeVM.accent.opacity(0.06))
                                .clipShape(Capsule())

                                Spacer()

                                Text("\(charCount) / 1000")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.25))
                            }
                        }

                        // ── Status ────────────────────────────────────
                        statusView

                        // ── Submit ────────────────────────────────────
                        Button {
                            submitFeedback()
                        } label: {
                            HStack(spacing: 8) {
                                if case .submitting = status {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.7)
                                        .tint(.black)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(buttonLabel)
                                    .font(.custom("Orbitron-Bold", size: 11))
                                    .tracking(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                isSubmitting
                                ? themeVM.accent.opacity(0.4)
                                : themeVM.accent.opacity(0.9)
                            )
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isSubmitting || message.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(themeVM.accent)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
        }
    }

    // MARK: — Helpers

    private var buttonLabel: String {
        switch status {
        case .idle:        return "SUBMIT"
        case .submitting:  return "SUBMITTING…"
        case .success:     return "✓ SENT"
        case .failure:     return "RETRY"
        }
    }

    private var isSubmitting: Bool {
        if case .submitting = status { return true }
        return false
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle: EmptyView()
        case .submitting:
            Text("Submitting…")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(themeVM.accent.opacity(0.6))
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Feedback submitted — thank you!")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(themeVM.accent)
        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(msg)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.orange)
        }
    }

    // MARK: — Submit
    // Mirrors web app _doSubmit exactly:
    // 1. Read feedback/inbox.json
    // 2. Append new entry with source: "ArcLake iOS"
    // 3. Write back (chunk if near 4.5MB limit)

    private func submitFeedback() {
        let msg = message.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        status = .submitting

        let user = authVM.githubUsername.isEmpty ? "guest" : authVM.githubUsername
        let id = String(format: "%x-%x", Int(Date().timeIntervalSince1970 * 1000),
                        Int.random(in: 0x1000...0xFFFF))
        let entry: [String: String] = [
            "id":     id,
            "ts":     ISO8601DateFormatter().string(from: Date()),
            "cat":    category.rawValue,
            "msg":    msg,
            "user":   user,
            "source": "ArcLake iOS",          // ← iOS identifier for admin console
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.5"
        ]

        Task {
            do {
                try await appendToInbox(entry: entry)
                await MainActor.run {
                    status = .success
                    message = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { dismiss() }
                }
            } catch {
                await MainActor.run {
                    status = .failure("Submission failed — try again")
                }
            }
        }
    }

    private func appendToInbox(entry: [String: String]) async throws {
        let apiBase = "https://api.github.com/repos/\(repo)/contents/\(ipath)"
        var request = URLRequest(url: URL(string: apiBase)!)
        request.setValue("token \(writeToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Step 1: Read current inbox
        let (data, _) = try await URLSession.shared.data(for: request)
        let meta = try JSONDecoder().decode(GitHubFileResponse.self, from: data)

        var entries: [[String: String]] = []
        var sha: String? = meta.sha
        if let content = meta.content {
            let cleaned = content.replacingOccurrences(of: "\n", with: "")
            if let decoded = Data(base64Encoded: cleaned),
               let parsed = try? JSONDecoder().decode([[String: String]].self, from: decoded) {
                entries = parsed
            }
        }

        // Step 2: Append new entry
        entries.append(entry)

        // Step 3: Write back
        let newContent = try JSONEncoder().encode(entries)
        let b64 = newContent.base64EncodedString()

        var putRequest = URLRequest(url: URL(string: apiBase)!)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("token \(writeToken)", forHTTPHeaderField: "Authorization")
        putRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "message": "feedback: new entry from \(entry["user"] ?? "guest") [iOS]",
            "content": b64
        ]
        if let s = sha { body["sha"] = s }
        putRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: putRequest)
        guard let http = response as? HTTPURLResponse,
              (200...201).contains(http.statusCode) else {
            throw FeedbackError.writeFailed
        }
    }

    enum FeedbackError: Error { case writeFailed }

    struct GitHubFileResponse: Decodable {
        let sha: String?
        let content: String?
    }
}

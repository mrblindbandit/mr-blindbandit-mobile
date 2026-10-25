import SwiftUI
import ClerkKit

/// Client for the site's username routes. A 404/405/501 means the route isn't live yet, which the
/// UI reports as "not available yet" instead of an error.
enum UsernameAPI {
    enum Failure: Error { case unavailable, server(String) }
    struct Availability: Decodable { let available: Bool; let reason: String? }
    struct SearchResult: Decodable, Identifiable, Hashable {
        let username: String
        let display_name: String?
        var id: String { username }
        enum CodingKeys: String, CodingKey { case username, display_name, displayName, handle }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            username = try c.decodeIfPresent(String.self, forKey: .username) ?? c.decode(String.self, forKey: .handle)
            display_name = try c.decodeIfPresent(String.self, forKey: .display_name) ?? c.decodeIfPresent(String.self, forKey: .displayName)
        }
    }

    static let base = URL(string: "https://mrblindbandit.net/api/")!

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
    }

    static func isValidFormat(_ u: String) -> Bool {
        u.range(of: "^[a-z0-9_.]{3,24}$", options: .regularExpression) != nil
    }

    private static func send(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard !StoreScreenshotMode.isActive, let token = await clerkTokenWithTimeout() else {
            throw Failure.server("Sign in to manage your username.")
        }
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://mrblindbandit.net", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.server("Couldn't reach Blindbandit. Check your connection.") }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if [404, 405, 501].contains(code) { throw Failure.unavailable }
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String ?? $0["message"] as? String }
            throw Failure.server(message ?? "Something went wrong (\(code)).")
        }
        return data
    }

    /// Site responses are `{ "success": true, "data": ... }`; returns the `data` payload as JSON.
    static func payload(_ data: Data) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let inner = obj["data"],
              JSONSerialization.isValidJSONObject(inner) || inner is [Any] else { return data }
        return (try? JSONSerialization.data(withJSONObject: inner)) ?? data
    }

    static func available(_ username: String) async throws -> Availability {
        let q = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? username
        return try JSONDecoder().decode(Availability.self, from: payload(try await send("users/username-available?u=\(q)")))
    }

    static func save(_ username: String) async throws {
        _ = try await send("me/username", method: "PATCH", body: ["username": username])
        UserDefaults.standard.set(username, forKey: "bbUsername")
    }

    static func search(_ query: String) async throws -> [SearchResult] {
        let q = normalize(query).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        let data = payload(try await send("users/search?q=\(q)"))
        if let wrapped = try? JSONDecoder().decode([String: [SearchResult]].self, from: data),
           let list = wrapped["results"] ?? wrapped["users"] ?? wrapped["data"] { return list }
        return try JSONDecoder().decode([SearchResult].self, from: data)
    }
}

/// Username picker with a live availability check. Used in onboarding and Settings → Edit username.
struct UsernameEditor: View {
    var onFinished: (() -> Void)? = nil
    @State private var text = UserDefaults.standard.string(forKey: "bbUsername") ?? ""
    @State private var status = ""
    @State private var available: Bool?
    @State private var saving = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("username", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .accessibilityLabel("Username")
                    .accessibilityHint("3 to 24 letters, numbers, dots or underscores")
                    .onChange(of: text) { _, value in schedule(value) }
                if !status.isEmpty {
                    Label(status, systemImage: available == true ? "checkmark.circle.fill" : available == false ? "xmark.circle.fill" : "info.circle")
                        .foregroundStyle(available == true ? .green : available == false ? .red : .secondary)
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Pick your username")
            } footer: {
                Text("People find you for calls and messages by @username.")
            }
            Section {
                Button(saving ? "Saving…" : "Save username") { Task { await save() } }
                    .disabled(saving || available != true)
                if let onFinished {
                    Button("Skip for now") { onFinished() }
                        .accessibilityHint("You can pick a username later in Settings")
                }
            }
        }
    }

    private func schedule(_ raw: String) {
        checkTask?.cancel()
        let u = UsernameAPI.normalize(raw)
        available = nil
        guard !u.isEmpty else { status = ""; return }
        guard UsernameAPI.isValidFormat(u) else {
            available = false; status = "Use 3 to 24 letters, numbers, dots or underscores."; return
        }
        status = "Checking @\(u)…"
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                let result = try await UsernameAPI.available(u)
                available = result.available
                status = result.available ? "@\(u) is available" : (result.reason ?? "@\(u) is taken")
            } catch UsernameAPI.Failure.unavailable {
                available = nil; status = "Usernames are not available yet. You can pick one in Settings once they are."
            } catch UsernameAPI.Failure.server(let message) {
                available = nil; status = message
            } catch { available = nil; status = "Couldn't check that username." }
            UIAccessibility.post(notification: .announcement, argument: status)
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let u = UsernameAPI.normalize(text)
        do {
            try await UsernameAPI.save(u)
            status = "Saved. You're @\(u)."
            UIAccessibility.post(notification: .announcement, argument: status)
            onFinished?()
        } catch UsernameAPI.Failure.unavailable {
            status = "Usernames are not available yet."
        } catch UsernameAPI.Failure.server(let message) {
            status = message
        } catch { status = "Couldn't save your username." }
    }
}

/// Searches members by @username for new calls and messages. Falls back to typing the exact
/// username when search isn't live yet.
struct UsernameSearchField: View {
    let label: String
    @Binding var text: String
    @State private var results: [UsernameAPI.SearchResult] = []
    @State private var note = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        TextField(label, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityHint("Type a username to search Blindbandit members")
            .onChange(of: text) { _, value in search(value) }
        ForEach(results) { r in
            Button {
                text = r.username; results = []
            } label: {
                VStack(alignment: .leading) {
                    Text("@\(r.username)").foregroundStyle(.primary)
                    if let name = r.display_name, !name.isEmpty { Text(name).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .accessibilityLabel("Choose @\(r.username)\(r.display_name.map { ", \($0)" } ?? "")")
        }
        if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
    }

    private func search(_ raw: String) {
        task?.cancel()
        let q = UsernameAPI.normalize(raw)
        guard q.count >= 2, !results.contains(where: { $0.username == q }) else { results = []; note = ""; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                results = try await UsernameAPI.search(q)
                note = results.isEmpty ? "No members match @\(q)." : ""
            } catch UsernameAPI.Failure.unavailable {
                results = []; note = "Username search is not available yet. Type the exact username."
            } catch { results = []; note = "" }
        }
    }
}

/// Back-compat entry: opens the native social profile (not a web view).
struct ProfileView: View {
    var body: some View {
        NativeProfileView(handle: "", isMe: true)
    }
}

/// Runs `operation` but gives up after `seconds`, even if the operation ignores cancellation
/// (e.g. a Clerk token refresh that never resolves). Returns nil on timeout.
func withHardTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        let work = Task {
            let value = try? await operation()
            if gate.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() { work.cancel(); continuation.resume(returning: nil) }
        }
    }
}

final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Clerk session token with a hard 8 s limit so no screen can wait on Clerk forever.
func clerkTokenWithTimeout() async -> String? {
    let token: String?? = await withHardTimeout(seconds: 3.5) { @MainActor in try await Clerk.shared.auth.getToken() }
    guard let value = token ?? nil, !value.isEmpty else { return nil }
    return value
}

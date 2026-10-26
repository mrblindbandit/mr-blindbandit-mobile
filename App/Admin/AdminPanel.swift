import SwiftUI

// MARK: - Owner / admin gate

/// Shows Admin only for the Blindbandit owner account.
/// Prefer server role when present; hardcode known owner handles/ids as fallback.
enum AdminGate {
    /// Owner handles that always see Admin (case-insensitive).
    static let ownerHandles: Set<String> = ["kheck"]
    /// Known owner profile ids (from live API).
    static let ownerProfileIDs: Set<String> = ["profile_mr_blindbandit"]

    static func isAdmin(handle: String, profileID: String, role: String? = nil) -> Bool {
        if let role {
            let r = role.lowercased()
            if r == "owner" || r == "admin" || r == "moderator" { return true }
        }
        let h = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        if ownerHandles.contains(h) { return true }
        if !profileID.isEmpty && ownerProfileIDs.contains(profileID) { return true }
        return false
    }
}

// MARK: - Admin API

@MainActor
enum AdminAPI {

    /// Prefer live `/v1/social/admin/…`; fall through to `/api/v1/admin/…` when batch ea112272 is live.
    private static func requestAdmin(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        do {
            return try await BlindbanditAPI.request(path, method: method, body: body)
        } catch let err as CommunicationsError {
            if case .notFound(_) = err, path.hasPrefix("v1/social/admin/") {
                let alias = "api/v1/admin/" + String(path.dropFirst("v1/social/admin/".count))
                return try await BlindbanditAPI.request(alias, method: method, body: body)
            }
            throw err
        }
    }

    static func overview() async throws -> AdminOverview {
        let data = try await requestAdmin("v1/social/admin/overview")
        return try BlindbanditAPI.decode(AdminOverview.self, from: data)
    }

    static func reports(limit: Int = 50) async throws -> [AdminReport] {
        let data = try await requestAdmin("v1/social/admin/reports?limit=\(limit)")
        struct Page: Decodable { let items: [AdminReport]? }
        if let page = try? BlindbanditAPI.decode(Page.self, from: data), let items = page.items {
            return items
        }
        // Some responses return a bare array under data
        if let items = try? BlindbanditAPI.decode([AdminReport].self, from: data) { return items }
        return []
    }

    static func users(limit: Int = 50) async throws -> [AdminUserRow] {
        let data = try await requestAdmin("v1/social/admin/users?limit=\(limit)")
        struct Page: Decodable { let items: [AdminUserRow]? }
        if let page = try? BlindbanditAPI.decode(Page.self, from: data), let items = page.items {
            return items
        }
        return (try? BlindbanditAPI.decode([AdminUserRow].self, from: data)) ?? []
    }

    static func verify(userID: String) async throws {
        _ = try await requestAdmin(
            "v1/social/admin/users/\(BlindbanditAPI.escape(userID))/verify",
            method: "POST",
            body: [:]
        )
    }

    static func unverify(userID: String) async throws {
        _ = try await requestAdmin(
            "v1/social/admin/users/\(BlindbanditAPI.escape(userID))/unverify",
            method: "POST",
            body: [:]
        )
    }

    static func ban(userID: String, reason: String = "") async throws {
        var body: [String: Any] = [:]
        if !reason.isEmpty { body["reason"] = reason }
        _ = try await requestAdmin(
            "v1/social/admin/users/\(BlindbanditAPI.escape(userID))/ban",
            method: "POST",
            body: body
        )
    }

    static func reinstate(userID: String) async throws {
        _ = try await requestAdmin(
            "v1/social/admin/users/\(BlindbanditAPI.escape(userID))/reinstate",
            method: "POST",
            body: [:]
        )
    }

    static func hidePost(id: String) async throws {
        _ = try await requestAdmin(
            "v1/social/admin/posts/\(BlindbanditAPI.escape(id))/hide",
            method: "POST",
            body: [:]
        )
    }

    static func deletePost(id: String) async throws {
        _ = try await requestAdmin(
            "v1/social/admin/posts/\(BlindbanditAPI.escape(id))",
            method: "DELETE"
        )
    }

    static func resolveReport(id: String, status: String, note: String = "") async throws {
        var body: [String: Any] = ["status": status]
        if !note.isEmpty { body["note"] = note }
        _ = try await requestAdmin(
            "v1/social/admin/reports/\(BlindbanditAPI.escape(id))/resolve",
            method: "POST",
            body: body
        )
    }

    /// Resolve a profile by @handle via public full endpoint (for Verify people search).
    static func lookupProfile(handle: String) async throws -> SocialProfileFull {
        try await BitesAPI.profileFull(handle: handle)
    }

    // MARK: Fat overnight Admin — Call RTC + Agora flags + ops

    static func callRtc() async throws -> CallRtcStatus {
        let data = try await requestAdmin("v1/social/admin/call-rtc")
        return try BlindbanditAPI.decode(CallRtcStatus.self, from: data)
    }

    static func setCallRtc(provider: String) async throws -> CallRtcStatus {
        let data = try await requestAdmin(
            "v1/social/admin/call-rtc",
            method: "PUT",
            body: ["provider": provider]
        )
        if let s = try? BlindbanditAPI.decode(CallRtcStatus.self, from: data) { return s }
        return try await callRtc()
    }

    static func agoraFlags() async throws -> AgoraFlagsPayload {
        let data = try await requestAdmin("v1/social/admin/agora-flags")
        if let p = try? BlindbanditAPI.decode(AgoraFlagsPayload.self, from: data) { return p }
        // Some responses nest under flags only
        struct Wrap: Decodable { let flags: [String: FlexibleJSON]? }
        if let w = try? BlindbanditAPI.decode(Wrap.self, from: data) {
            return AgoraFlagsPayload(flags: w.flags ?? [:], note: nil, customer_rest_configured: nil)
        }
        return AgoraFlagsPayload(flags: [:], note: nil, customer_rest_configured: nil)
    }

    static func setAgoraFlags(_ flags: [String: Bool]) async throws -> AgoraFlagsPayload {
        var bodyFlags: [String: Any] = [:]
        for (k, v) in flags { bodyFlags[k] = v }
        let data = try await requestAdmin(
            "v1/social/admin/agora-flags",
            method: "PUT",
            body: ["flags": bodyFlags]
        )
        if let p = try? BlindbanditAPI.decode(AgoraFlagsPayload.self, from: data) { return p }
        return try await agoraFlags()
    }

    static func broadcast(title: String, body: String) async throws -> String {
        let data = try await requestAdmin(
            "v1/social/admin/broadcast",
            method: "POST",
            body: ["title": title, "body": body]
        )
        struct R: Decodable { let recipients_attempted: Int?; let message: String? }
        if let r = try? BlindbanditAPI.decode(R.self, from: data) {
            if let n = r.recipients_attempted { return "Published. Attempted recipients: \(n)" }
            return r.message ?? "Broadcast sent."
        }
        return "Broadcast sent."
    }

    static func callAnalytics() async throws -> String {
        let data = try await requestAdmin("v1/social/admin/call-analytics?limit=40")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func deviceStats() async throws -> String {
        let data = try await requestAdmin("v1/social/admin/device-stats")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func auditLog() async throws -> String {
        let data = try await requestAdmin("v1/social/admin/audit?limit=80")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func pendingAds() async throws -> [AdminAdRow] {
        let data = try await requestAdmin("v1/social/admin/ads?limit=50")
        struct Page: Decodable { let items: [AdminAdRow]? }
        if let page = try? BlindbanditAPI.decode(Page.self, from: data), let items = page.items { return items }
        return (try? BlindbanditAPI.decode([AdminAdRow].self, from: data)) ?? []
    }

    static func reviewAd(id: String, approve: Bool) async throws {
        _ = try await requestAdmin(
            "v1/social/admin/ads/\(BlindbanditAPI.escape(id))/review",
            method: "POST",
            body: ["approve": approve]
        )
    }

    static func pendingVerification() async throws -> [AdminVerifyRow] {
        let data = try await requestAdmin("v1/social/admin/verification?status=pending&limit=50")
        struct Page: Decodable { let items: [AdminVerifyRow]? }
        if let page = try? BlindbanditAPI.decode(Page.self, from: data), let items = page.items { return items }
        return (try? BlindbanditAPI.decode([AdminVerifyRow].self, from: data)) ?? []
    }

    static func reviewVerification(id: String, approve: Bool) async throws {
        // Prefer social admin path; fall back handled by requestAdmin for older aliases.
        do {
            _ = try await BlindbanditAPI.request(
                "v1/social/verification/\(BlindbanditAPI.escape(id))/review",
                method: "POST",
                body: ["approve": approve]
            )
        } catch {
            _ = try await requestAdmin(
                "v1/social/admin/verification/\(BlindbanditAPI.escape(id))/review",
                method: "POST",
                body: ["approve": approve]
            )
        }
    }

    static func globalFlags() async throws -> [String: Bool] {
        let data = try await requestAdmin("v1/social/admin/global-flags")
        struct Wrap: Decodable { let flags: [String: FlexibleJSON]? }
        guard let w = try? BlindbanditAPI.decode(Wrap.self, from: data) else { return [:] }
        var out: [String: Bool] = [:]
        for (k, v) in w.flags ?? [:] {
            if case .bool(let b) = v { out[k] = b }
        }
        return out
    }

    static func setGlobalFlags(_ flags: [String: Bool]) async throws {
        var body: [String: Any] = [:]
        for (k, v) in flags { body[k] = v }
        _ = try await requestAdmin("v1/social/admin/global-flags", method: "PUT", body: ["flags": body])
    }

    static func pinPost(id: String, pin: Bool) async throws {
        if pin {
            _ = try await requestAdmin("v1/social/admin/posts/\(BlindbanditAPI.escape(id))/pin", method: "POST", body: [:])
        } else {
            _ = try await requestAdmin("v1/social/admin/posts/\(BlindbanditAPI.escape(id))/pin", method: "DELETE")
        }
    }

    // MARK: - Fat catalog helpers (50+ tools)

    static func rawGet(_ path: String) async throws -> Data {
        if path.hasPrefix("v1/social/admin/") || path.hasPrefix("api/v1/admin/") {
            return try await requestAdmin(path)
        }
        return try await BlindbanditAPI.request(path)
    }

    static func prettyGet(_ path: String) async throws -> String {
        let data = try await rawGet(path)
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: pretty, encoding: .utf8) {
            return s
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @discardableResult
    static func putJSON(_ path: String, body: [String: Any]) async throws -> String {
        let data: Data
        if path.hasPrefix("v1/social/admin/") {
            data = try await requestAdmin(path, method: "PUT", body: body)
        } else {
            data = try await BlindbanditAPI.request(path, method: "PUT", body: body)
        }
        return String(data: data, encoding: .utf8) ?? "OK"
    }

    @discardableResult
    static func postJSON(_ path: String, body: [String: Any]) async throws -> String {
        let data: Data
        if path.hasPrefix("v1/social/admin/") {
            data = try await requestAdmin(path, method: "POST", body: body)
        } else {
            data = try await BlindbanditAPI.request(path, method: "POST", body: body)
        }
        return String(data: data, encoding: .utf8) ?? "OK"
    }

    /// Unified user moderation actions → `/v1/social/admin/users/:id/:action` (or Sites batch aliases).
    static func userAction(action: String, target: String, reason: String?, extra: [String: Any] = [:]) async throws -> String {
        var body: [String: Any] = extra
        if let reason, !reason.isEmpty { body["reason"] = reason }
        let id = BlindbanditAPI.escape(target.trimmingCharacters(in: CharacterSet(charactersIn: "@")))
        let pathMap: [String: (String, String)] = [
            // action -> (suffix or full relative, method)
            "verify": ("verify", "POST"),
            "unverify": ("unverify", "POST"),
            "ban": ("ban", "POST"),
            "suspend": ("suspend", "POST"),
            "reinstate": ("reinstate", "POST"),
            "mute_posts": ("mute-posts", "POST"),
            "unmute_posts": ("unmute", "POST"),
            "mute_messages": ("mute-messages", "POST"),
            "disable_calls": ("disable-calls", "POST"),
            "enable_calls": ("enable-calls", "POST"),
            "shadow": ("shadow", "POST"),
            "rate_limit": ("rate-limit", "POST"),
            "revoke_push": ("revoke-push", "POST"),
            "force_disconnect": ("force-disconnect", "POST"),
            "monetize_approve": ("monetize", "POST"),
            "monetize_reject": ("monetize", "POST"),
            "wipe_sessions": ("wipe-sessions", "POST"),
        ]
        guard let (suffix, method) = pathMap[action] else {
            throw CommunicationsError.server("Unknown admin action \(action)")
        }
        if action == "monetize_approve" { body["approve"] = true }
        if action == "monetize_reject" { body["approve"] = false }
        if action == "unmute_posts" {
            // unmute clears mute+shadow via reinstate-like unmute endpoint
        }
        let data = try await requestAdmin(
            "v1/social/admin/users/\(id)/\(suffix)",
            method: method,
            body: body.isEmpty ? [:] : body
        )
        return String(data: data, encoding: .utf8) ?? "OK"
    }

    static func postAction(action: String, postId: String) async throws -> String {
        let id = BlindbanditAPI.escape(postId)
        switch action {
        case "hide":
            try await hidePost(id: postId); return "Hidden"
        case "unhide":
            let data = try await requestAdmin("v1/social/admin/posts/\(id)/unhide", method: "POST", body: [:])
            return String(data: data, encoding: .utf8) ?? "Unhidden"
        case "delete":
            try await deletePost(id: postId); return "Deleted"
        case "pin":
            try await pinPost(id: postId, pin: true); return "Pinned"
        case "unpin":
            try await pinPost(id: postId, pin: false); return "Unpinned"
        default:
            throw CommunicationsError.server("Unknown post action \(action)")
        }
    }

    static func testPush(target: String, title: String, body: String) async throws -> String {
        let id = BlindbanditAPI.escape(target.trimmingCharacters(in: CharacterSet(charactersIn: "@")))
        let data = try await requestAdmin(
            "v1/social/admin/users/\(id)/test-push",
            method: "POST",
            body: ["title": title, "body": body]
        )
        return String(data: data, encoding: .utf8) ?? "Sent"
    }

    static func exportUser(target: String) async throws -> String {
        let id = BlindbanditAPI.escape(target.trimmingCharacters(in: CharacterSet(charactersIn: "@")))
        return try await prettyGet("v1/social/admin/users/\(id)/export")
    }

    static func hideBite(biteId: String, remove: Bool) async throws -> String {
        let id = BlindbanditAPI.escape(biteId)
        let data = try await requestAdmin(
            "v1/social/admin/bites/\(id)/hide",
            method: "POST",
            body: ["remove": remove]
        )
        return String(data: data, encoding: .utf8) ?? "OK"
    }
}

// MARK: - Fat Admin models

struct CallRtcStatus: Decodable {
    var provider: String?
    var livekit: ProviderReady?
    var agora: AgoraReady?
    var defaults: Defaults?

    struct ProviderReady: Decodable { var configured: Bool?; var url: String? }
    struct AgoraReady: Decodable {
        var configured: Bool?
        var customer_rest: Bool?
        var flags: [String: FlexibleJSON]?
        var docs: String?
    }
    struct Defaults: Decodable { var provider: String? }

    var providerLabel: String { (provider ?? "livekit").lowercased() }
    var statusLine: String {
        let lk = livekit?.configured == true ? "Ready" : "Unset"
        let ag = agora?.configured == true ? "Ready" : "Unset"
        let rest = agora?.customer_rest == true ? "Ready" : "Unset"
        return "Provider: \(providerLabel) · LiveKit \(lk) · Agora \(ag) · Customer REST \(rest)"
    }
}

struct AgoraFlagsPayload: Decodable {
    var flags: [String: FlexibleJSON]
    var note: String?
    var customer_rest_configured: Bool?

    var boolFlags: [(String, Bool)] {
        flags.keys.sorted().compactMap { k in
            guard case .bool(let b) = flags[k] else {
                // region etc. skip for toggles
                return nil
            }
            return (k, b)
        }
    }
}

struct AdminAdRow: Identifiable, Decodable {
    let id: String
    var title: String?
    var body: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
    }
    enum CodingKeys: String, CodingKey { case id, title, body }
}

struct AdminVerifyRow: Identifiable, Decodable {
    let id: String
    var handle: String?
    var display_name: String?
    var evidence: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        handle = try? c.decodeIfPresent(String.self, forKey: .handle)
        display_name = try? c.decodeIfPresent(String.self, forKey: .display_name)
        evidence = try? c.decodeIfPresent(String.self, forKey: .evidence)
    }
    enum CodingKeys: String, CodingKey { case id, handle, display_name, evidence }
}

/// Loose JSON value for flag maps.
enum FlexibleJSON: Decodable {
    case bool(Bool), string(String), number(Double), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .null
    }
}

// MARK: - Admin panel (native, VoiceOver-first)

struct AdminPanelView: View {
    /// Fat Social Admin Control Center (50+ tools + Call RTC LiveKit↔Agora).
    var body: some View {
        AdminFatControlCenterView()
    }
}

struct AdminVerifyPeopleView: View {
    @State private var query = ""
    @State private var profile: SocialProfileFull?
    @State private var note = ""
    @State private var busy = false
    @State private var searchError = ""

    var body: some View {
        Form {
            Section {
                TextField("Username without @", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Username to verify")
                Button("Look up") { Task { await lookup() } }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            } footer: {
                Text("Verified badge matches the seal on @kheck and @celyneheck14. It shows on profile, Bites, chats, and people.")
            }

            if !searchError.isEmpty {
                Section { Text(searchError).foregroundStyle(.red) }
            }

            if let profile {
                Section("Profile") {
                    HStack(spacing: 12) {
                        ProfileAvatar(
                            urlString: profile.avatar_url,
                            displayName: profile.display_name,
                            size: 48,
                            verified: profile.verified,
                            decorative: true
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(profile.display_name).font(.headline)
                                if profile.verified { VerifiedBadge() }
                            }
                            Text("@\(profile.handle)").foregroundStyle(.secondary)
                            Text(profile.verified ? "Currently verified" : "Not verified")
                                .font(.caption)
                                .foregroundStyle(profile.verified ? .green : .secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(profile.accessibilitySummary)
                }

                Section {
                    if profile.verified {
                        Button(role: .destructive) {
                            Task { await setVerified(false, id: profile.id) }
                        } label: {
                            Label(busy ? "Working…" : "Unverify @\(profile.handle)", systemImage: "checkmark.seal")
                        }
                        .disabled(busy)
                        .accessibilityHint("Removes the verified badge on the server")
                    } else {
                        Button {
                            Task { await setVerified(true, id: profile.id) }
                        } label: {
                            Label(busy ? "Working…" : "Verify @\(profile.handle)", systemImage: "checkmark.seal.fill")
                        }
                        .disabled(busy)
                        .accessibilityHint("Grants the verified badge like Mr. Blindbandit and Celyne")
                    }
                }

                if !note.isEmpty {
                    Section { Text(note).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Verify people")
    }

    private func lookup() async {
        let h = query.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespaces))
        guard !h.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            profile = try await AdminAPI.lookupProfile(handle: h)
            searchError = ""
            note = ""
            UIAccessibility.post(notification: .announcement, argument: "Found \(profile?.display_name ?? h)")
        } catch {
            profile = nil
            searchError = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }

    private func setVerified(_ on: Bool, id: String) async {
        busy = true
        defer { busy = false }
        do {
            if on { try await AdminAPI.verify(userID: id) }
            else { try await AdminAPI.unverify(userID: id) }
            // Refresh
            if let h = profile?.handle {
                profile = try await AdminAPI.lookupProfile(handle: h)
            }
            note = on ? "Verified. Badge will show on profile, Bites, and people lists." : "Verification removed."
            UIAccessibility.post(notification: .announcement, argument: note)
        } catch {
            note = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }
}

// MARK: - Report queue

struct AdminReportsView: View {
    @State private var reports: [AdminReport] = []
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        List {
            if loading && reports.isEmpty {
                ProgressView("Loading reports")
            } else if !error.isEmpty && reports.isEmpty {
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { Task { await load() } }
            } else if reports.isEmpty {
                Text("No open reports.").foregroundStyle(.secondary)
            }
            ForEach(reports) { r in
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.reason ?? "Report").font(.headline)
                    Text("\(r.target_type ?? "?") · \(r.target_id ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let d = r.details, !d.isEmpty { Text(d).font(.subheadline) }
                    HStack {
                        Button("Resolve") { Task { await resolve(r, status: "resolved") } }
                        Button("Dismiss") { Task { await resolve(r, status: "dismissed") } }
                        if let tid = r.target_id, (r.target_type == "post" || r.target_type == nil) {
                            Button("Hide Bite", role: .destructive) {
                                Task {
                                    try? await AdminAPI.hidePost(id: tid)
                                    UIAccessibility.post(notification: .announcement, argument: "Bite hidden")
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Reports")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            reports = try await AdminAPI.reports()
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resolve(_ r: AdminReport, status: String) async {
        do {
            try await AdminAPI.resolveReport(id: r.id, status: status)
            reports.removeAll { $0.id == r.id }
            UIAccessibility.post(notification: .announcement, argument: "Report \(status)")
        } catch {
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }
}

// MARK: - Ban / reinstate

struct AdminUsersModerationView: View {
    @State private var query = ""
    @State private var profile: SocialProfileFull?
    @State private var reason = ""
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Look up") { Task { await lookup() } }
            }
            if let profile {
                Section("@\(profile.handle)") {
                    Text(profile.display_name)
                    TextField("Ban reason (optional)", text: $reason)
                    Button("Ban user", role: .destructive) {
                        Task {
                            do {
                                try await AdminAPI.ban(userID: profile.id, reason: reason)
                                note = "Banned @\(profile.handle)"
                                UIAccessibility.post(notification: .announcement, argument: note)
                            } catch {
                                note = error.localizedDescription
                            }
                        }
                    }
                    Button("Reinstate") {
                        Task {
                            do {
                                try await AdminAPI.reinstate(userID: profile.id)
                                note = "Reinstated @\(profile.handle)"
                                UIAccessibility.post(notification: .announcement, argument: note)
                            } catch {
                                note = error.localizedDescription
                            }
                        }
                    }
                }
            }
            if !note.isEmpty { Section { Text(note) } }
        }
        .navigationTitle("Users")
    }

    private func lookup() async {
        let h = query.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespaces))
        guard !h.isEmpty else { return }
        do {
            profile = try await AdminAPI.lookupProfile(handle: h)
            note = ""
        } catch {
            profile = nil
            note = error.localizedDescription
        }
    }
}

struct AdminHideBiteView: View {
    @State private var postID = ""
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                TextField("Bite or post id", text: $postID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Hide") {
                    Task {
                        do {
                            try await AdminAPI.hidePost(id: postID.trimmingCharacters(in: .whitespaces))
                            note = "Hidden"
                            UIAccessibility.post(notification: .announcement, argument: "Bite hidden")
                        } catch { note = error.localizedDescription }
                    }
                }
                Button("Delete permanently", role: .destructive) {
                    Task {
                        do {
                            try await AdminAPI.deletePost(id: postID.trimmingCharacters(in: .whitespaces))
                            note = "Deleted"
                            UIAccessibility.post(notification: .announcement, argument: "Bite deleted")
                        } catch { note = error.localizedDescription }
                    }
                }
            }
            if !note.isEmpty { Section { Text(note) } }
        }
        .navigationTitle("Hide Bite")
    }
}


// MARK: - Call RTC

struct AdminCallRtcView: View {
    @State private var status: CallRtcStatus?
    @State private var note = ""
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        Form {
            Section("Current provider") {
                if let status {
                    Text(status.statusLine)
                        .accessibilityLabel(status.statusLine)
                    LabeledContent("Active", value: status.providerLabel.uppercased())
                } else if error.isEmpty {
                    ProgressView("Loading Call RTC")
                } else {
                    Text(error).foregroundStyle(.secondary)
                }
                if !note.isEmpty {
                    Text(note).foregroundStyle(.secondary)
                        .accessibilityLabel(note)
                }
            }
            Section("Switch provider") {
                Button {
                    Task { await setProvider("livekit") }
                } label: {
                    Label("Use LiveKit", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(busy)
                .accessibilityLabel("Use LiveKit")
                .accessibilityHint("Set preferred call provider to LiveKit")

                Button {
                    Task { await setProvider("agora") }
                } label: {
                    Label("Use Agora", systemImage: "waveform.badge.mic")
                }
                .disabled(busy)
                .accessibilityLabel("Use Agora")
                .accessibilityHint("Set preferred call provider to Agora")
            }
            Section {
                Text("Existing calls keep their original provider. New compatible apps follow this preference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Call RTC")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do {
            status = try await AdminAPI.callRtc()
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setProvider(_ provider: String) async {
        busy = true
        defer { busy = false }
        do {
            status = try await AdminAPI.setCallRtc(provider: provider)
            note = "Switched to \(provider)."
            error = ""
            AppHaptics.success()
        } catch {
            note = error.localizedDescription
            AppHaptics.error()
        }
    }
}

// MARK: - Agora flags

struct AdminAgoraFlagsView: View {
    @State private var flags: [(String, Bool)] = []
    @State private var note = ""
    @State private var busy = false
    @State private var error = ""

    private let restNeeds: Set<String> = [
        "agora_cloud_recording", "agora_rtmp_push", "agora_media_pull", "agora_stt"
    ]

    var body: some View {
        Form {
            if !note.isEmpty {
                Section { Text(note).foregroundStyle(.secondary).accessibilityLabel(note) }
            }
            if !error.isEmpty {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("Feature flags") {
                if flags.isEmpty && error.isEmpty {
                    ProgressView("Loading Agora flags")
                }
                ForEach(flags, id: \.0) { item in
                    Toggle(isOn: Binding(
                        get: { flags.first(where: { $0.0 == item.0 })?.1 ?? false },
                        set: { newVal in Task { await setFlag(item.0, newVal) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                            if restNeeds.contains(item.0) {
                                Text("Needs console enable + Customer REST billing")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(busy)
                    .accessibilityLabel(item.0)
                    .accessibilityHint(restNeeds.contains(item.0) ? "Paid stub may need customer REST" : "Toggle Agora feature")
                }
            }
        }
        .navigationTitle("Agora features")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do {
            let p = try await AdminAPI.agoraFlags()
            flags = p.boolFlags
            if let n = p.note, !n.isEmpty { note = n }
            else if p.customer_rest_configured == false {
                note = "Cloud Recording / RTMP / STT REST need AGORA_CUSTOMER_ID + AGORA_CUSTOMER_SECRET."
            }
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setFlag(_ key: String, _ on: Bool) async {
        busy = true
        defer { busy = false }
        var map = Dictionary(uniqueKeysWithValues: flags)
        map[key] = on
        do {
            let p = try await AdminAPI.setAgoraFlags(map)
            flags = p.boolFlags
            note = p.note ?? "Flags saved."
            error = ""
            AppHaptics.selection()
        } catch {
            self.error = error.localizedDescription
            await refresh()
        }
    }
}

// MARK: - Broadcast / JSON ops / ads / verify queue / pin / global flags

struct AdminBroadcastView: View {
    @State private var title = ""
    @State private var bodyText = ""
    @State private var status = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("Message") {
                TextField("Title", text: $title)
                    .accessibilityLabel("Broadcast title")
                TextEditor(text: $bodyText).frame(minHeight: 120)
                    .accessibilityLabel("Broadcast body")
            }
            Section {
                Button("Send broadcast") {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            status = try await AdminAPI.broadcast(title: title, body: bodyText)
                            AppHaptics.success()
                        } catch {
                            status = error.localizedDescription
                            AppHaptics.error()
                        }
                    }
                }
                .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                if !status.isEmpty { Text(status).foregroundStyle(.secondary).accessibilityLabel(status) }
            }
        }
        .navigationTitle("Push broadcast")
    }
}

struct AdminJsonOpsView: View {
    let title: String
    let loader: () async throws -> String
    @State private var text = ""
    @State private var error = ""
    var body: some View {
        ScrollView {
            Text(error.isEmpty ? text : error)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        do { text = try await loader(); error = "" }
        catch { self.error = error.localizedDescription }
    }
}

struct AdminAdsQueueView: View {
    @State private var items: [AdminAdRow] = []
    @State private var status = ""
    var body: some View {
        List {
            if !status.isEmpty { Section { Text(status).foregroundStyle(.secondary) } }
            ForEach(items) { ad in
                Section {
                    Text(ad.title ?? "Ad").font(.headline)
                    if let b = ad.body { Text(b).font(.caption) }
                    HStack {
                        Button("Approve") { Task { await review(ad, true) } }
                        Button("Reject", role: .destructive) { Task { await review(ad, false) } }
                    }
                }
            }
            if items.isEmpty { Text("No pending ads.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Ads queue")
        .task { await refresh() }
        .refreshable { await refresh() }
    }
    private func refresh() async {
        do { items = try await AdminAPI.pendingAds(); status = "" }
        catch { status = error.localizedDescription }
    }
    private func review(_ ad: AdminAdRow, _ ok: Bool) async {
        do {
            try await AdminAPI.reviewAd(id: ad.id, approve: ok)
            status = ok ? "Approved." : "Rejected."
            await refresh()
        } catch { status = error.localizedDescription }
    }
}

struct AdminPendingVerifyQueueView: View {
    @State private var items: [AdminVerifyRow] = []
    @State private var status = ""
    var body: some View {
        List {
            if !status.isEmpty { Section { Text(status).foregroundStyle(.secondary) } }
            ForEach(items) { v in
                Section {
                    Text("@\(v.handle ?? "") \(v.display_name ?? "")").font(.headline)
                    if let e = v.evidence, !e.isEmpty { Text(e).font(.caption) }
                    HStack {
                        Button("Approve") { Task { await review(v, true) } }
                        Button("Reject", role: .destructive) { Task { await review(v, false) } }
                    }
                }
            }
            if items.isEmpty { Text("Verification queue empty.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Verification queue")
        .task { await refresh() }
        .refreshable { await refresh() }
    }
    private func refresh() async {
        do { items = try await AdminAPI.pendingVerification(); status = "" }
        catch { status = error.localizedDescription }
    }
    private func review(_ v: AdminVerifyRow, _ ok: Bool) async {
        do {
            try await AdminAPI.reviewVerification(id: v.id, approve: ok)
            status = ok ? "Approved." : "Rejected."
            await refresh()
        } catch { status = error.localizedDescription }
    }
}

struct AdminPinPostView: View {
    @State private var postID = ""
    @State private var status = ""
    var body: some View {
        Form {
            TextField("Post id", text: $postID)
                .accessibilityLabel("Post id to pin")
            Button("Pin post") {
                Task {
                    do { try await AdminAPI.pinPost(id: postID.trimmingCharacters(in: .whitespaces), pin: true); status = "Pinned." }
                    catch { status = error.localizedDescription }
                }
            }
            Button("Unpin post", role: .destructive) {
                Task {
                    do { try await AdminAPI.pinPost(id: postID.trimmingCharacters(in: .whitespaces), pin: false); status = "Unpinned." }
                    catch { status = error.localizedDescription }
                }
            }
            if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
        }
        .navigationTitle("Pin post")
    }
}

struct AdminGlobalFlagsView: View {
    @State private var flags: [(String, Bool)] = []
    @State private var status = ""
    @State private var busy = false
    var body: some View {
        Form {
            if !status.isEmpty { Section { Text(status).foregroundStyle(.secondary) } }
            Section("Flags") {
                if flags.isEmpty { ProgressView("Loading") }
                ForEach(flags, id: \.0) { item in
                    Toggle(item.0, isOn: Binding(
                        get: { flags.first(where: { $0.0 == item.0 })?.1 ?? false },
                        set: { v in Task { await set(item.0, v) } }
                    ))
                    .disabled(busy)
                }
            }
        }
        .navigationTitle("Global flags")
        .task { await refresh() }
        .refreshable { await refresh() }
    }
    private func refresh() async {
        do {
            let m = try await AdminAPI.globalFlags()
            flags = m.keys.sorted().map { ($0, m[$0] ?? false) }
            status = flags.isEmpty ? "No flags returned." : ""
        } catch { status = error.localizedDescription }
    }
    private func set(_ key: String, _ on: Bool) async {
        busy = true
        defer { busy = false }
        var map = Dictionary(uniqueKeysWithValues: flags)
        map[key] = on
        do {
            try await AdminAPI.setGlobalFlags(map)
            flags = map.keys.sorted().map { ($0, map[$0] ?? false) }
            status = "Saved."
        } catch {
            status = error.localizedDescription
            await refresh()
        }
    }
}

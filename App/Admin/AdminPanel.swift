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
}

// MARK: - Admin panel (native, VoiceOver-first)

struct AdminPanelView: View {
    @EnvironmentObject private var communications: ProductionCommunicationsService
    @State private var overview: AdminOverview?
    @State private var error = ""

    var body: some View {
        List {
            if !AdminGate.isAdmin(handle: communications.myHandle, profileID: communications.myProfileID) {
                Section {
                    Text("Admin is only available on the owner account.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Quick stats") {
                    if let o = overview {
                        LabeledContent("Users", value: "\(o.usersCount)")
                        LabeledContent("Posts", value: "\(o.postsCount)")
                        LabeledContent("Open reports", value: "\(o.openReportsCount)")
                    } else if error.isEmpty {
                        ProgressView("Loading stats")
                    } else {
                        Text(error).foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadOverview() } }
                    }
                }

                Section("Moderation") {
                    NavigationLink {
                        AdminVerifyPeopleView()
                    } label: {
                        Label("Verify people", systemImage: "checkmark.seal.fill")
                    }
                    .accessibilityHint("Search by username and grant or remove the verified badge")

                    NavigationLink {
                        AdminReportsView()
                    } label: {
                        Label("Report queue", systemImage: "flag.fill")
                    }

                    NavigationLink {
                        AdminUsersModerationView()
                    } label: {
                        Label("Users · ban / reinstate", systemImage: "person.crop.circle.badge.exclamationmark")
                    }

                    NavigationLink {
                        AdminHideBiteView()
                    } label: {
                        Label("Hide or remove a Bite", systemImage: "eye.slash")
                    }
                }
            }
        }
        .navigationTitle("Admin")
        .task { await loadOverview() }
        .refreshable { await loadOverview() }
    }

    private func loadOverview() async {
        do {
            overview = try await AdminAPI.overview()
            error = ""
        } catch {
            // Overview may 403 for non-admin tokens even if gate matched hardcoded handle.
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Verify people (P0 for owner)

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

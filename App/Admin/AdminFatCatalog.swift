import SwiftUI

/// Fat Social Admin Control Center — 50+ distinct owner-only admin tools.
/// Gate: `AdminGate` / Profile → Admin (@kheck).
struct AdminFatTool: Identifiable {
    let id: String
    let category: String
    let title: String
    let subtitle: String
}

enum AdminFatCatalog {
    static let tools: [AdminFatTool] = [
        .init(id: "call_rtc_status", category: "Call RTC", title: "Call RTC status", subtitle: "Show LiveKit/Agora provider and readiness"),
        .init(id: "call_rtc_livekit", category: "Call RTC", title: "Use LiveKit", subtitle: "Switch preferred call provider to LiveKit"),
        .init(id: "call_rtc_agora", category: "Call RTC", title: "Use Agora", subtitle: "Switch preferred call provider to Agora"),
        .init(id: "agora_flags", category: "Call RTC", title: "Agora feature flags", subtitle: "Toggle Agora recording/RTMP/STT/dual-stream stubs"),
        .init(id: "agora_extras_recording", category: "Call RTC", title: "Agora cloud recording stub", subtitle: "POST agora extras recording (blocked until REST)"),
        .init(id: "agora_extras_rtmp", category: "Call RTC", title: "Agora RTMP push stub", subtitle: "POST agora extras rtmp"),
        .init(id: "agora_extras_stt", category: "Call RTC", title: "Agora STT stub", subtitle: "POST agora extras stt"),
        .init(id: "call_analytics", category: "Call RTC", title: "Call analytics", subtitle: "GET call analytics for ops"),
        .init(id: "overview", category: "Overview", title: "Admin overview", subtitle: "Dashboard counters for profiles/posts/reports"),
        .init(id: "user_search", category: "Users", title: "User search", subtitle: "Search social profiles by handle/email"),
        .init(id: "verify_user", category: "Users", title: "Force verify", subtitle: "Grant verified badge by user id/handle"),
        .init(id: "unverify_user", category: "Users", title: "Revoke verify", subtitle: "Remove verified badge"),
        .init(id: "verification_queue", category: "Users", title: "Verification queue", subtitle: "Approve/reject pending verification requests"),
        .init(id: "ban_user", category: "Users", title: "Hard ban", subtitle: "Permanently ban a social account"),
        .init(id: "suspend_user", category: "Users", title: "Suspend 7 days", subtitle: "Temporarily suspend an account"),
        .init(id: "reinstate_user", category: "Users", title: "Reinstate", subtitle: "Unban or unsuspend"),
        .init(id: "mute_posts", category: "Users", title: "Mute posting", subtitle: "Mute posts for a user"),
        .init(id: "unmute_posts", category: "Users", title: "Unmute posting", subtitle: "Clear mute + shadow"),
        .init(id: "mute_messages", category: "Users", title: "Mute messages", subtitle: "Mute DMs for a user"),
        .init(id: "disable_calls", category: "Users", title: "Disable calls", subtitle: "Block placing/receiving calls"),
        .init(id: "enable_calls", category: "Users", title: "Enable calls", subtitle: "Re-enable calls"),
        .init(id: "shadow_restrict", category: "Users", title: "Shadow restrict", subtitle: "Shadowban + mute posts"),
        .init(id: "rate_limit", category: "Users", title: "Rate-limit multiplier", subtitle: "Raise rate-limit multiplier 1–20"),
        .init(id: "inspect_devices", category: "Users", title: "Inspect devices", subtitle: "Redacted push devices for a profile"),
        .init(id: "revoke_push", category: "Users", title: "Revoke push tokens", subtitle: "Wipe all push tokens for a user"),
        .init(id: "force_disconnect", category: "Users", title: "Force disconnect calls", subtitle: "End active calls for a profile"),
        .init(id: "monetize_approve", category: "Users", title: "Approve monetization", subtitle: "Approve creator monetization"),
        .init(id: "monetize_reject", category: "Users", title: "Reject monetization", subtitle: "Reject creator monetization"),
        .init(id: "test_push", category: "Users", title: "Test push", subtitle: "Send admin test notification"),
        .init(id: "wipe_sessions", category: "Users", title: "Wipe sessions", subtitle: "Force sign-out / revoke sessions (admin)"),
        .init(id: "export_user", category: "Users", title: "Export user data", subtitle: "Admin export JSON for a profile"),
        .init(id: "reports_queue", category: "Content", title: "Report queue", subtitle: "Open reports · resolve/dismiss/escalate"),
        .init(id: "hide_post", category: "Content", title: "Hide post", subtitle: "Hide a post from public feeds"),
        .init(id: "unhide_post", category: "Content", title: "Unhide post", subtitle: "Restore a hidden post"),
        .init(id: "delete_post", category: "Content", title: "Delete post", subtitle: "Admin-delete a post"),
        .init(id: "pin_post", category: "Content", title: "Pin post", subtitle: "Pin a post in feed"),
        .init(id: "unpin_post", category: "Content", title: "Unpin post", subtitle: "Unpin a feed post"),
        .init(id: "hide_bite", category: "Content", title: "Hide / remove Bite", subtitle: "Hide or remove a BanditBite by id"),
        .init(id: "feed_moderation", category: "Content", title: "Feed moderation list", subtitle: "GET feed moderation controls"),
        .init(id: "content_search", category: "Content", title: "Content search", subtitle: "Admin search posts/bites by query"),
        .init(id: "hashtag_blocklist", category: "Content", title: "Hashtag blocklist", subtitle: "GET/PUT blocked hashtags"),
        .init(id: "nsfw_filter", category: "Content", title: "NSFW filter toggle", subtitle: "Global NSFW filter killswitch"),
        .init(id: "trending", category: "Content", title: "Trending / hashtags", subtitle: "Trending controls snapshot"),
        .init(id: "appeals", category: "Content", title: "Appeals queue", subtitle: "Appeals stub queue"),
        .init(id: "ads_queue", category: "Ads", title: "Ads marketplace queue", subtitle: "Approve/reject pending ads"),
        .init(id: "ads_placements", category: "Ads", title: "AdSense placements", subtitle: "Ops ads placements manager"),
        .init(id: "broadcast_compose", category: "Comms", title: "Push broadcast", subtitle: "Compose and send system broadcast"),
        .init(id: "broadcast_history", category: "Comms", title: "Broadcast history", subtitle: "Recent broadcast attempts"),
        .init(id: "label_announcement", category: "Comms", title: "Label announcement", subtitle: "Create portal/label announcement"),
        .init(id: "inapp_notification", category: "Comms", title: "In-app notification", subtitle: "Create notification for one user"),
        .init(id: "device_stats", category: "Ops", title: "Device / install stats", subtitle: "Install and device counters"),
        .init(id: "social_audit", category: "Ops", title: "Social admin audit", subtitle: "Social admin action audit log"),
        .init(id: "platform_audit", category: "Ops", title: "Platform audit", subtitle: "Ops platform audit log"),
        .init(id: "ops_dashboard", category: "Ops", title: "Ops dashboard", subtitle: "Admin ops dashboard overview"),
        .init(id: "ops_settings", category: "Ops", title: "System settings", subtitle: "Maintenance, signup freeze, invite-only, ads"),
        .init(id: "maintenance_mode", category: "Ops", title: "Maintenance mode", subtitle: "Toggle maintenance_mode"),
        .init(id: "signup_freeze", category: "Ops", title: "Signup freeze", subtitle: "Close signups (signup_open=false)"),
        .init(id: "invite_only", category: "Ops", title: "Invite-only mode", subtitle: "Toggle invite_only"),
        .init(id: "global_flags", category: "Ops", title: "Global feature flags", subtitle: "Social global killswitches"),
        .init(id: "feature_killswitches", category: "Ops", title: "Feature killswitches", subtitle: "Alias UI over global flags / app-config"),
        .init(id: "automod", category: "Ops", title: "Automod policy", subtitle: "GET/PUT automod rules stub"),
        .init(id: "app_config", category: "Ops", title: "Remote app config", subtitle: "PUT remote app configuration"),
        .init(id: "infra_status", category: "Ops", title: "Infra status", subtitle: "Planned infra leftovers"),
        .init(id: "role_history", category: "Ops", title: "Role change history", subtitle: "List/record platform role changes"),
        .init(id: "trust_cases", category: "Ops", title: "Trust & safety cases", subtitle: "List/create/close trust cases"),
        .init(id: "creator_payouts", category: "Ops", title: "Creator payouts", subtitle: "Ops payouts queue + resolve"),
        .init(id: "platform_users", category: "Ops", title: "Platform user manager", subtitle: "List/search platform accounts"),
        .init(id: "platform_sync", category: "Ops", title: "Sync platform users", subtitle: "Backfill platform_accounts from social"),
        .init(id: "invite_codes", category: "Ops", title: "Invite codes", subtitle: "Mint/list invite codes"),
        .init(id: "invite_mods", category: "Ops", title: "Invite moderators", subtitle: "Invite staff/mod label accounts"),
        .init(id: "moderation_bundle", category: "Ops", title: "Moderation bundle", subtitle: "Reports/comments/bites/appeals bundle"),
    ]
    static var count: Int { tools.count }
}

struct AdminFatControlCenterView: View {
    @State private var query = ""
    @State private var rtc: CallRtcStatus?
    @State private var rtcNote = ""
    @State private var rtcBusy = false

    private var filtered: [AdminFatTool] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return AdminFatCatalog.tools }
        return AdminFatCatalog.tools.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) || $0.category.lowercased().contains(q) || $0.id.contains(q)
        }
    }

    private var grouped: [(String, [AdminFatTool])] {
        var order: [String] = []
        var map: [String: [AdminFatTool]] = [:]
        for t in filtered {
            if map[t.category] == nil { order.append(t.category); map[t.category] = [] }
            map[t.category, default: []].append(t)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Text("\(AdminFatCatalog.count) admin tools. Owner-only — server still enforces social_admin / ops roles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(AdminFatCatalog.count) admin tools")
                TextField("Filter tools", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Filter admin tools")
            }

            Section("Call RTC · LiveKit ↔ Agora") {
                if let rtc {
                    Text(rtc.statusLine)
                        .font(.footnote)
                        .accessibilityLabel(rtc.statusLine)
                } else {
                    Text("Pull to refresh for provider status.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !rtcNote.isEmpty {
                    Text(rtcNote).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        Task { await setRtc("livekit") }
                    } label: {
                        Label("Use LiveKit", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(rtcBusy)
                    .accessibilityLabel("Use LiveKit")

                    Button {
                        Task { await setRtc("agora") }
                    } label: {
                        Label("Use Agora", systemImage: "waveform.badge.mic")
                    }
                    .disabled(rtcBusy)
                    .accessibilityLabel("Use Agora")
                }
                NavigationLink {
                    AdminCallRtcView()
                } label: {
                    Label("Call RTC details", systemImage: "phone.connection")
                }
                NavigationLink {
                    AdminAgoraFlagsView()
                } label: {
                    Label("Agora feature flags", systemImage: "switch.2")
                }
            }

            ForEach(grouped, id: \.0) { cat, tools in
                Section("\(cat) (\(tools.count))") {
                    ForEach(tools) { tool in
                        NavigationLink {
                            AdminFatToolRouter(tool: tool)
                                .navigationTitle(tool.title)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title).font(.headline)
                                Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel(tool.title)
                        .accessibilityHint(tool.subtitle)
                    }
                }
            }
        }
        .navigationTitle("Admin")
        .task { await refreshRtc() }
        .refreshable { await refreshRtc() }
    }

    private func refreshRtc() async {
        do { rtc = try await AdminAPI.callRtc(); rtcNote = "" }
        catch { rtcNote = error.localizedDescription }
    }

    private func setRtc(_ provider: String) async {
        rtcBusy = true
        defer { rtcBusy = false }
        do {
            rtc = try await AdminAPI.setCallRtc(provider: provider)
            rtcNote = "Switched to \(provider)."
            AppHaptics.success()
        } catch {
            rtcNote = error.localizedDescription
            AppHaptics.error()
        }
    }
}


/// Routes each catalog tool id to a working admin screen (forms call AdminAPI).
struct AdminFatToolRouter: View {
    let tool: AdminFatTool

    var body: some View {
        switch tool.id {
        case "call_rtc_status", "call_rtc_livekit", "call_rtc_agora":
            AdminCallRtcView()
        case "agora_flags", "agora_extras_recording", "agora_extras_rtmp", "agora_extras_stt":
            AdminAgoraFlagsView()
        case "call_analytics":
            AdminJsonOpsView(title: "Call analytics", loader: { try await AdminAPI.callAnalytics() })
        case "overview":
            AdminFatOverviewView()
        case "user_search":
            AdminUsersModerationView()
        case "verify_user":
            AdminUserActionView(title: "Force verify", action: "verify", needsReason: false)
        case "unverify_user":
            AdminUserActionView(title: "Revoke verify", action: "unverify", needsReason: false)
        case "verification_queue":
            AdminPendingVerifyQueueView()
        case "ban_user":
            AdminUserActionView(title: "Hard ban", action: "ban", needsReason: true)
        case "suspend_user":
            AdminUserActionView(title: "Suspend 7 days", action: "suspend", needsReason: true)
        case "reinstate_user":
            AdminUserActionView(title: "Reinstate", action: "reinstate", needsReason: false)
        case "mute_posts":
            AdminUserActionView(title: "Mute posting", action: "mute_posts", needsReason: true)
        case "unmute_posts":
            AdminUserActionView(title: "Unmute posting", action: "unmute_posts", needsReason: false)
        case "mute_messages":
            AdminUserActionView(title: "Mute messages", action: "mute_messages", needsReason: true)
        case "disable_calls":
            AdminUserActionView(title: "Disable calls", action: "disable_calls", needsReason: true)
        case "enable_calls":
            AdminUserActionView(title: "Enable calls", action: "enable_calls", needsReason: false)
        case "shadow_restrict":
            AdminUserActionView(title: "Shadow restrict", action: "shadow", needsReason: true)
        case "rate_limit":
            AdminRateLimitView()
        case "inspect_devices":
            AdminFatInspectDevicesView()
        case "revoke_push":
            AdminUserActionView(title: "Revoke push tokens", action: "revoke_push", needsReason: false)
        case "force_disconnect":
            AdminUserActionView(title: "Force disconnect calls", action: "force_disconnect", needsReason: false)
        case "monetize_approve":
            AdminUserActionView(title: "Approve monetization", action: "monetize_approve", needsReason: false)
        case "monetize_reject":
            AdminUserActionView(title: "Reject monetization", action: "monetize_reject", needsReason: true)
        case "test_push":
            AdminTestPushView()
        case "wipe_sessions":
            AdminUserActionView(title: "Wipe sessions", action: "wipe_sessions", needsReason: true)
        case "export_user":
            AdminExportUserView()
        case "reports_queue":
            AdminReportsView()
        case "hide_post":
            AdminPostActionView(title: "Hide post", action: "hide")
        case "unhide_post":
            AdminPostActionView(title: "Unhide post", action: "unhide")
        case "delete_post":
            AdminPostActionView(title: "Delete post", action: "delete")
        case "pin_post":
            AdminPostActionView(title: "Pin post", action: "pin")
        case "unpin_post":
            AdminPostActionView(title: "Unpin post", action: "unpin")
        case "hide_bite":
            AdminFatHideBiteView()
        case "feed_moderation":
            AdminFeedModerationView()
        case "content_search":
            AdminContentSearchView()
        case "hashtag_blocklist":
            AdminHashtagBlocklistView()
        case "nsfw_filter":
            AdminNsfwFilterView()
        case "trending":
            AdminTrendingView()
        case "appeals":
            AdminAppealsView()
        case "ads_queue":
            AdminAdsQueueView()
        case "ads_placements":
            AdminOpsJsonView(title: "Ad placements", path: "v1/admin/ops/ads/placements")
        case "broadcast_compose":
            AdminBroadcastView()
        case "broadcast_history":
            AdminJsonOpsView(title: "Broadcast history", loader: { try await AdminAPI.prettyGet("v1/social/admin/broadcast/history") })
        case "label_announcement":
            AdminLabelAnnouncementView()
        case "inapp_notification":
            AdminInAppNotificationView()
        case "device_stats":
            AdminJsonOpsView(title: "Device stats", loader: { try await AdminAPI.deviceStats() })
        case "social_audit":
            AdminJsonOpsView(title: "Audit log", loader: { try await AdminAPI.auditLog() })
        case "platform_audit":
            AdminOpsJsonView(title: "Platform audit", path: "v1/admin/ops/audit")
        case "ops_dashboard":
            AdminOpsJsonView(title: "Ops dashboard", path: "v1/admin/ops/dashboard")
        case "ops_settings", "maintenance_mode", "signup_freeze", "invite_only":
            AdminOpsSettingsView(focus: tool.id)
        case "global_flags", "feature_killswitches":
            AdminGlobalFlagsView()
        case "automod":
            AdminAutomodView()
        case "app_config":
            AdminAppConfigView()
        case "infra_status":
            AdminOpsJsonView(title: "Infra status", path: "v1/admin/ops/infra/status")
        case "role_history":
            AdminOpsJsonView(title: "Role history", path: "v1/admin/ops/roles/history")
        case "trust_cases":
            AdminTrustCasesView()
        case "creator_payouts":
            AdminOpsJsonView(title: "Creator payouts", path: "v1/admin/ops/payouts")
        case "platform_users":
            AdminPlatformUsersView()
        case "platform_sync":
            AdminPlatformSyncView()
        case "invite_codes":
            AdminInviteCodesView()
        case "invite_mods":
            AdminInviteModsView()
        case "moderation_bundle":
            AdminOpsJsonView(title: "Moderation bundle", path: "v1/admin/ops/moderation/bundle")
        default:
            Text("Unknown tool: \(tool.id)").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared form helpers

struct AdminUserActionView: View {
    let title: String
    let action: String
    let needsReason: Bool
    @State private var target = ""
    @State private var reason = ""
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("User id or @handle", text: $target)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("User id or handle")
                if needsReason {
                    TextField("Reason", text: $reason)
                        .accessibilityLabel("Reason")
                }
            }
            Section {
                Button(title) { Task { await run() } }
                    .disabled(busy || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(title)
            }
            if !note.isEmpty {
                Section { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func run() async {
        busy = true
        defer { busy = false }
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            note = try await AdminAPI.userAction(action: action, target: t, reason: r.isEmpty ? nil : r)
            AppHaptics.success()
        } catch {
            note = error.localizedDescription
            AppHaptics.error()
        }
    }
}

struct AdminPostActionView: View {
    let title: String
    let action: String
    @State private var postId = ""
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("Post id", text: $postId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Post id")
            }
            Section {
                Button(title) { Task { await run() } }
                    .disabled(busy || postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(title)
            }
            if !note.isEmpty {
                Section { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func run() async {
        busy = true
        defer { busy = false }
        let id = postId.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            note = try await AdminAPI.postAction(action: action, postId: id)
            AppHaptics.success()
        } catch {
            note = error.localizedDescription
            AppHaptics.error()
        }
    }
}

struct AdminRateLimitView: View {
    @State private var target = ""
    @State private var multiplier = "2"
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("User id or @handle", text: $target)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Multiplier 1–20", text: $multiplier)
                .keyboardType(.numberPad)
            Button("Apply rate limit") { Task { await run() } }
                .disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        let m = Int(multiplier) ?? 2
        do {
            note = try await AdminAPI.userAction(action: "rate_limit", target: target.trimmingCharacters(in: .whitespacesAndNewlines), reason: nil, extra: ["multiplier": m])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminTestPushView: View {
    @State private var target = ""
    @State private var title = "Admin test"
    @State private var bodyText = "Push delivery check"
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("User id or @handle", text: $target).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Title", text: $title)
            TextField("Body", text: $bodyText)
            Button("Send test push") { Task { await run() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.testPush(target: target.trimmingCharacters(in: .whitespacesAndNewlines), title: title, body: bodyText)
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminExportUserView: View {
    @State private var target = ""
    @State private var payload = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("User id or @handle", text: $target).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Export") { Task { await run() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
            if !payload.isEmpty {
                Section("Export JSON") {
                    Text(payload).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            payload = try await AdminAPI.exportUser(target: target.trimmingCharacters(in: .whitespacesAndNewlines))
            note = "OK"
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminFatHideBiteView: View {
    @State private var biteId = ""
    @State private var remove = false
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("Bite id", text: $biteId).textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("Remove (vs hide)", isOn: $remove)
            Button("Apply") { Task { await run() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.hideBite(biteId: biteId.trimmingCharacters(in: .whitespacesAndNewlines), remove: remove)
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminFeedModerationView: View {
    @State private var text = "Loading…"
    var body: some View {
        ScrollView {
            Text(text).font(.system(.caption, design: .monospaced)).padding().textSelection(.enabled)
        }
        .task {
            do { text = try await AdminAPI.prettyGet("v1/social/admin/feed") }
            catch { text = error.localizedDescription }
        }
    }
}

struct AdminContentSearchView: View {
    @State private var q = ""
    @State private var text = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("Search query", text: $q)
            Button("Search") { Task { await run() } }.disabled(busy || q.isEmpty)
            if !text.isEmpty {
                Section { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            text = try await AdminAPI.prettyGet("v1/social/admin/content-search?q=\(BlindbanditAPI.escape(q))")
        } catch { text = error.localizedDescription }
    }
}

struct AdminHashtagBlocklistView: View {
    @State private var tags = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("Blocked hashtags (comma or newline)") {
                TextEditor(text: $tags).frame(minHeight: 120)
            }
            Button("Load") { Task { await load() } }
            Button("Save blocklist") { Task { await save() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
        .task { await load() }
    }
    private func load() async {
        do {
            let raw = try await AdminAPI.prettyGet("v1/social/admin/hashtag-blocklist")
            tags = raw
            note = "Loaded"
        } catch { note = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        let list = tags.split(whereSeparator: { $0 == "," || $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            note = try await AdminAPI.putJSON("v1/social/admin/hashtag-blocklist", body: ["tags": list])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminNsfwFilterView: View {
    @State private var enabled = false
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            Toggle("NSFW filter enabled", isOn: $enabled)
            Button("Save") { Task { await save() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
        .task {
            do {
                let data = try await AdminAPI.rawGet("v1/social/admin/nsfw-filter")
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    enabled = (obj["enabled"] as? Bool) ?? (obj["nsfw_filter"] as? Bool) ?? false
                }
            } catch { note = error.localizedDescription }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.putJSON("v1/social/admin/nsfw-filter", body: ["enabled": enabled])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminTrendingView: View {
    @State private var text = "Loading…"
    var body: some View {
        ScrollView { Text(text).font(.system(.caption, design: .monospaced)).padding().textSelection(.enabled) }
            .task {
                do { text = try await AdminAPI.prettyGet("v1/social/admin/trending") }
                catch { text = error.localizedDescription }
            }
    }
}

struct AdminAppealsView: View {
    @State private var text = "Loading…"
    var body: some View {
        ScrollView { Text(text).font(.system(.caption, design: .monospaced)).padding().textSelection(.enabled) }
            .task {
                do { text = try await AdminAPI.prettyGet("v1/social/admin/appeals") }
                catch { text = error.localizedDescription }
            }
    }
}

struct AdminOpsJsonView: View {
    let title: String
    let path: String
    @State private var text = "Loading…"
    var body: some View {
        ScrollView { Text(text).font(.system(.caption, design: .monospaced)).padding().textSelection(.enabled) }
            .navigationTitle(title)
            .task {
                do { text = try await AdminAPI.prettyGet(path) }
                catch { text = error.localizedDescription }
            }
            .refreshable {
                do { text = try await AdminAPI.prettyGet(path) }
                catch { text = error.localizedDescription }
            }
    }
}

struct AdminOpsSettingsView: View {
    let focus: String
    @State private var maintenance = false
    @State private var signupOpen = true
    @State private var inviteOnly = false
    @State private var adsEnabled = true
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            Toggle("Maintenance mode", isOn: $maintenance)
            Toggle("Signups open", isOn: $signupOpen)
            Toggle("Invite only", isOn: $inviteOnly)
            Toggle("Ads enabled", isOn: $adsEnabled)
            Button("Save system settings") { Task { await save() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
        .task { await load() }
    }
    private func load() async {
        do {
            let data = try await AdminAPI.rawGet("v1/admin/ops/settings")
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let s = (obj["settings"] as? [String: Any]) ?? obj
                maintenance = (s["maintenance_mode"] as? Bool) ?? false
                signupOpen = (s["signup_open"] as? Bool) ?? true
                inviteOnly = (s["invite_only"] as? Bool) ?? false
                adsEnabled = (s["ads_enabled"] as? Bool) ?? true
                if focus == "maintenance_mode" { /* highlight via toggles */ }
                if focus == "signup_freeze" { signupOpen = false }
            }
            note = "Loaded"
        } catch { note = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.putJSON("v1/admin/ops/settings", body: [
                "maintenance_mode": maintenance,
                "signup_open": signupOpen,
                "invite_only": inviteOnly,
                "ads_enabled": adsEnabled
            ])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminAutomodView: View {
    @State private var text = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("Automod policy JSON") {
                TextEditor(text: $text).frame(minHeight: 180).font(.system(.caption, design: .monospaced))
            }
            Button("Load") { Task { await load() } }
            Button("Save") { Task { await save() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
        .task { await load() }
    }
    private func load() async {
        do { text = try await AdminAPI.prettyGet("v1/social/admin/automod"); note = "Loaded" }
        catch { note = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            note = "Invalid JSON"; return
        }
        do {
            note = try await AdminAPI.putJSON("v1/social/admin/automod", body: obj)
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminAppConfigView: View {
    @State private var text = "{\n  \n}"
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextEditor(text: $text).frame(minHeight: 160).font(.system(.caption, design: .monospaced))
            Button("Load") { Task { await load() } }
            Button("PUT app-config") { Task { await save() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
        .task { await load() }
    }
    private func load() async {
        do { text = try await AdminAPI.prettyGet("v1/social/admin/app-config"); note = "Loaded" }
        catch { note = error.localizedDescription }
    }
    private func save() async {
        busy = true; defer { busy = false }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            note = "Invalid JSON"; return
        }
        do {
            note = try await AdminAPI.putJSON("v1/social/admin/app-config", body: obj)
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminTrustCasesView: View {
    @State private var text = "Loading…"
    @State private var subject = ""
    @State private var summary = ""
    @State private var note = ""
    var body: some View {
        Form {
            Section("Open cases") {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Section("Create case") {
                TextField("Subject user id", text: $subject)
                TextField("Summary", text: $summary)
                Button("Create") { Task { await create() } }
            }
            if !note.isEmpty { Section { Text(note).font(.footnote) } }
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        do { text = try await AdminAPI.prettyGet("v1/admin/ops/trust-cases") }
        catch { text = error.localizedDescription }
    }
    private func create() async {
        do {
            note = try await AdminAPI.postJSON("v1/admin/ops/trust-cases", body: ["subject_user_id": subject, "summary": summary])
            await load()
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminPlatformUsersView: View {
    @State private var q = ""
    @State private var text = ""
    var body: some View {
        Form {
            TextField("Search", text: $q)
            Button("Search") { Task { await run() } }
            if !text.isEmpty { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
        }
    }
    private func run() async {
        let path = q.isEmpty ? "v1/admin/ops/users" : "v1/admin/ops/users?q=\(BlindbanditAPI.escape(q))"
        do { text = try await AdminAPI.prettyGet(path) }
        catch { text = error.localizedDescription }
    }
}

struct AdminPlatformSyncView: View {
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            Button("Sync platform users from social") { Task { await run() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.postJSON("v1/admin/ops/users/sync", body: [:])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminInviteCodesView: View {
    @State private var text = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            Button("List codes") { Task { await load() } }
            Button("Mint invite code") { Task { await mint() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
            if !text.isEmpty { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
        }
        .task { await load() }
    }
    private func load() async {
        do { text = try await AdminAPI.prettyGet("v1/social/admin/invite-codes") }
        catch { text = error.localizedDescription }
    }
    private func mint() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.postJSON("v1/social/admin/invite-codes", body: ["count": 1])
            await load()
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminInviteModsView: View {
    @State private var email = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
            Button("Invite moderator") { Task { await run() } }.disabled(busy || email.isEmpty)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.postJSON("v1/admin/ops/invites", body: ["email": email, "role": "moderator"])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminLabelAnnouncementView: View {
    @State private var title = ""
    @State private var bodyText = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Body", text: $bodyText, axis: .vertical).lineLimit(3...8)
            Button("Create announcement") { Task { await run() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.postJSON("v1/admin/ops/announcements", body: ["title": title, "body": bodyText])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}

struct AdminInAppNotificationView: View {
    @State private var userId = ""
    @State private var title = ""
    @State private var bodyText = ""
    @State private var note = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("User id", text: $userId).textInputAutocapitalization(.never)
            TextField("Title", text: $title)
            TextField("Body", text: $bodyText)
            Button("Send in-app notification") { Task { await run() } }.disabled(busy)
            if !note.isEmpty { Text(note).font(.footnote) }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        do {
            note = try await AdminAPI.postJSON("v1/admin/ops/notifications", body: ["user_id": userId, "title": title, "body": bodyText])
            AppHaptics.success()
        } catch { note = error.localizedDescription; AppHaptics.error() }
    }
}


struct AdminFatOverviewView: View {
    @State private var text = "Loading…"
    var body: some View {
        List {
            Section {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Section("Shortcuts") {
                NavigationLink("Verify people") { AdminVerifyPeopleView() }
                NavigationLink("Reports") { AdminReportsView() }
                NavigationLink("Users moderation") { AdminUsersModerationView() }
            }
        }
        .task {
            do {
                let o = try await AdminAPI.overview()
                text = String(describing: o)
            } catch {
                do { text = try await AdminAPI.prettyGet("v1/social/admin/overview") }
                catch { text = error.localizedDescription }
            }
        }
    }
}

struct AdminFatInspectDevicesView: View {
    @State private var target = ""
    @State private var text = ""
    @State private var busy = false
    var body: some View {
        Form {
            TextField("User id or @handle", text: $target)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Inspect devices") { Task { await run() } }.disabled(busy)
            if !text.isEmpty {
                Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }
    }
    private func run() async {
        busy = true; defer { busy = false }
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            text = try await AdminAPI.prettyGet("v1/social/admin/users/\(BlindbanditAPI.escape(t))/devices")
        } catch { text = error.localizedDescription }
    }
}

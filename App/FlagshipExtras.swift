import SwiftUI
import UIKit

// MARK: - People search (native discovery)

struct PeopleSearchView: View {
    @State private var query = ""
    @State private var results: [BiteAuthor] = []
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        List {
            Section {
                TextField("Search people by username", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search people")
                    .onSubmit { Task { await search() } }
            }
            if loading {
                ProgressView("Searching")
            } else if !error.isEmpty {
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { Task { await search() } }
            } else if results.isEmpty && !query.isEmpty {
                ContentUnavailableView("No people found", systemImage: "person.slash", description: Text("Try another username."))
            } else {
                ForEach(results) { person in
                    NavigationLink {
                        NativeProfileView(handle: person.handle)
                    } label: {
                        HStack(spacing: 12) {
                            ProfileAvatar(urlString: person.avatar_url, displayName: person.display_name, size: 40, verified: person.verified, decorative: true)
                            VStack(alignment: .leading) {
                                HStack(spacing: 4) {
                                    Text(person.display_name).font(.headline)
                                    if person.verified { VerifiedBadge() }
                                }
                                Text("@\(person.handle)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(person.verified ? "\(person.display_name), Verified, @\(person.handle)" : "\(person.display_name), @\(person.handle)")
                }
            }
        }
        .navigationTitle("Search people")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Search") { Task { await search() } }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            results = try await DiscoveryAPI.searchPeople(q)
            error = ""
        } catch {
            self.error = error.localizedDescription
            results = []
        }
    }
}

@MainActor
enum DiscoveryAPI {
    static func searchPeople(_ q: String) async throws -> [BiteAuthor] {
        let encoded = BlindbanditAPI.escape(q)
        let paths = [
            "api/v1/users/search?q=\(encoded)&limit=30",
            "v1/social/search/people?q=\(encoded)&limit=30"
        ]
        var last: Error?
        for path in paths {
            do {
                let data = try await BlindbanditAPI.request(path)
                if let page = try? BlindbanditAPI.decode(SocialListPage.self, from: data) {
                    return page.items
                }
                struct Alt: Decodable { let users: [BiteAuthor]?; let items: [BiteAuthor]? }
                if let alt = try? BlindbanditAPI.decode(Alt.self, from: data) {
                    return alt.items ?? alt.users ?? []
                }
            } catch {
                last = error
            }
        }
        throw last ?? CommunicationsError.server("Search unavailable")
    }
}

// MARK: - Notifications inbox (native)

struct NotificationsInboxView: View {
    @State private var items: [AppNotificationItem] = []
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        List {
            if loading && items.isEmpty {
                ProgressView("Loading notifications")
            } else if !error.isEmpty && items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load notifications", systemImage: "bell.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if items.isEmpty {
                ContentUnavailableView("You’re all caught up", systemImage: "bell", description: Text("Likes, comments, follows, and mentions land here."))
            } else {
                ForEach(items) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title).font(.headline)
                        if let body = n.body, !body.isEmpty {
                            Text(body).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(n.relativeTime).font(.caption).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Notifications")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = try await NotificationsAPI.fetch()
            error = ""
        } catch {
            if items.isEmpty { self.error = error.localizedDescription }
        }
    }
}

struct AppNotificationItem: Identifiable, Decodable, Equatable {
    let id: String
    var title: String
    var body: String?
    var created_at: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title))
            ?? (try? c.decode(String.self, forKey: .type))
            ?? "Notification"
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        if let d = try? c.decode(Double.self, forKey: .created_at) { created_at = d }
        else if let i = try? c.decode(Int.self, forKey: .created_at) { created_at = Double(i) }
        else { created_at = 0 }
    }

    enum CodingKeys: String, CodingKey { case id, title, body, type, created_at }

    var relativeTime: String {
        let seconds = created_at > 1_000_000_000_000 ? created_at / 1000 : created_at
        guard seconds > 0 else { return "" }
        return Date(timeIntervalSince1970: seconds).formatted(.relative(presentation: .named))
    }
}

@MainActor
enum NotificationsAPI {
    static func fetch() async throws -> [AppNotificationItem] {
        let paths = ["api/v1/notifications?limit=50", "v1/social/notifications?limit=50"]
        var last: Error?
        for path in paths {
            do {
                let data = try await BlindbanditAPI.request(path)
                struct Page: Decodable { let items: [AppNotificationItem] }
                if let page = try? BlindbanditAPI.decode(Page.self, from: data) { return page.items }
                if let arr = try? BlindbanditAPI.decode([AppNotificationItem].self, from: data) { return arr }
            } catch { last = error }
        }
        throw last ?? CommunicationsError.server("Notifications unavailable")
    }
}

// MARK: - Messaging polish: search / pin / mute

@MainActor
enum ChatListPrefs {
    private static let pinnedKey = "chats.pinned.v1"
    private static let mutedKey = "chats.muted.v1"

    static var pinned: [String] {
        get { UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: pinnedKey) }
    }

    static var muted: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: mutedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: mutedKey) }
    }

    static func togglePin(_ id: String) {
        var p = pinned
        if let i = p.firstIndex(of: id) { p.remove(at: i) } else { p.insert(id, at: 0) }
        pinned = p
        AppHaptics.selection()
    }

    static func toggleMute(_ id: String) {
        var m = muted
        if m.contains(id) { m.remove(id) } else { m.insert(id) }
        muted = m
        AppHaptics.selection()
    }

    static func isPinned(_ id: String) -> Bool { pinned.contains(id) }
    static func isMuted(_ id: String) -> Bool { muted.contains(id) }
}

struct ChatSearchBar: View {
    @Binding var query: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search chats", text: $query)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search chats")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ThreadMutePinMenu: View {
    let threadID: String
    var body: some View {
        Menu {
            Button {
                ChatListPrefs.togglePin(threadID)
            } label: {
                Label(ChatListPrefs.isPinned(threadID) ? "Unpin chat" : "Pin chat", systemImage: "pin")
            }
            Button {
                ChatListPrefs.toggleMute(threadID)
            } label: {
                Label(ChatListPrefs.isMuted(threadID) ? "Unmute" : "Mute notifications", systemImage: "bell.slash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Chat options")
    }
}

// MARK: - Call polish

struct InCallActionBar: View {
    var muted: Binding<Bool>
    var speakerOn: Binding<Bool>
    var cameraOn: Binding<Bool>
    var onHangUp: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            callButton(icon: muted.wrappedValue ? "mic.slash.fill" : "mic.fill",
                       label: muted.wrappedValue ? "Unmute" : "Mute",
                       active: muted.wrappedValue) { muted.wrappedValue.toggle(); AppHaptics.medium() }
            callButton(icon: speakerOn.wrappedValue ? "speaker.wave.3.fill" : "speaker.fill",
                       label: speakerOn.wrappedValue ? "Speaker on" : "Speaker",
                       active: speakerOn.wrappedValue) { speakerOn.wrappedValue.toggle(); AppHaptics.selection() }
            callButton(icon: cameraOn.wrappedValue ? "video.fill" : "video.slash.fill",
                       label: cameraOn.wrappedValue ? "Camera on" : "Camera off",
                       active: cameraOn.wrappedValue) { cameraOn.wrappedValue.toggle(); AppHaptics.selection() }
            callButton(icon: "phone.down.fill", label: "End call", active: true, tint: .red, onHangUp)
        }
        .padding()
        .accessibilityElement(children: .contain)
    }

    private func callButton(icon: String, label: String, active: Bool, tint: Color = .primary, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(active ? tint.opacity(0.2) : Color.secondary.opacity(0.15), in: Circle())
                    .foregroundStyle(tint == .red ? .red : .primary)
                Text(label).font(.caption2)
            }
        }
        .accessibilityLabel(label)
        .buttonStyle(.plain)
    }
}

struct CallHistoryRowPolish: View {
    let handle: String
    let direction: String
    let when: Date
    let missed: Bool

    var body: some View {
        HStack {
            Image(systemName: missed ? "phone.down.fill" : (direction == "out" ? "phone.arrow.up.right.fill" : "phone.arrow.down.left.fill"))
                .foregroundStyle(missed ? .red : Brand.goldDeep)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("@\(handle)").font(.headline)
                Text(missed ? "Missed" : (direction == "out" ? "Outgoing" : "Incoming"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(when, style: .relative).font(.caption).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(missed ? "Missed call" : (direction == "out" ? "Outgoing call" : "Incoming call")) with @\(handle), \(when.formatted(.relative(presentation: .named)))")
    }
}

// MARK: - Offline banner / retry

struct OfflineBanner: View {
    var message: String = "You’re offline. Showing cached content."
    var onRetry: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text(message).font(.footnote)
            Spacer()
            if let onRetry {
                Button("Retry", action: onRetry).font(.footnote.weight(.semibold))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - AI helpers: summarize / rewrite / translate / caption / persona

enum AIQuickActions {
    static func summarizePrompt(_ text: String) -> String {
        "Summarize this conversation in plain sentences under 80 words for a VoiceOver user. No markdown.\n\n\(text)"
    }
    static func rewritePrompt(_ text: String, tone: String) -> String {
        "Rewrite the following to sound \(tone). Keep meaning. Plain sentences, no markdown.\n\n\(text)"
    }
    static func translatePrompt(_ text: String, lang: String) -> String {
        "Translate to \(lang). Plain text only.\n\n\(text)"
    }
    static func captionPrompt(description: String) -> String {
        "Suggest 3 short Blindbandit-style captions for: \(description). One per line, no numbering."
    }
}

enum AIPersonaMode: String, CaseIterable, Identifiable {
    case friend, bandit, concise, coach
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friend: return "Friendly"
        case .bandit: return "Blind Bandit"
        case .concise: return "Concise"
        case .coach: return "Coach"
        }
    }
    var promptAddon: String {
        switch self {
        case .friend: return "Stay warm and casual."
        case .bandit: return "Channel Blind Bandit energy: confident, music-scene aware, supportive of blind creators, never corny."
        case .concise: return "Keep every answer under 40 words unless asked for detail."
        case .coach: return "Be a practical coach: clear next steps, encouraging, no fluff."
        }
    }
    static var current: AIPersonaMode {
        AIPersonaMode(rawValue: UserDefaults.standard.string(forKey: SettingsKey.aiPersonaMode) ?? "friend") ?? .friend
    }
}

struct AIQuickActionsSheet: View {
    let sourceText: String
    var onAsk: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.aiTranslateDefault) private var lang = "Cebuano"

    var body: some View {
        NavigationStack {
            List {
                Button("Summarize") { onAsk(AIQuickActions.summarizePrompt(sourceText)); dismiss() }
                Button("Rewrite — clearer") { onAsk(AIQuickActions.rewritePrompt(sourceText, tone: "clearer and simpler")); dismiss() }
                Button("Rewrite — warmer") { onAsk(AIQuickActions.rewritePrompt(sourceText, tone: "warmer and friendlier")); dismiss() }
                Button("Translate to \(lang)") { onAsk(AIQuickActions.translatePrompt(sourceText, lang: lang)); dismiss() }
                Button("Caption ideas") { onAsk(AIQuickActions.captionPrompt(description: sourceText)); dismiss() }
                Button("Search the web about this") {
                    onAsk("Search the web for current info about: \(sourceText.prefix(200))")
                    dismiss()
                }
            }
            .navigationTitle("AI actions")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Profile share / block / report extras

struct ProfileShareBlockBar: View {
    let handle: String
    let displayName: String
    @State private var showReport = false
    @State private var note = ""
    @State private var blocked = false

    var body: some View {
        HStack {
            ShareLink(item: "https://mrblindbandit.net/@\(handle)") {
                Label("Share profile", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                blocked = true
                ProfileBlockStore.block(handle)
                AppHaptics.warning()
                UIAccessibility.post(notification: .announcement, argument: "Blocked @\(handle)")
            } label: {
                Label(blocked ? "Blocked" : "Block", systemImage: "hand.raised")
            }
            .disabled(blocked)
            Button { showReport = true } label: {
                Label("Report", systemImage: "flag")
            }
        }
        .buttonStyle(.bordered)
        .alert("Report @\(handle)", isPresented: $showReport) {
            TextField("What’s wrong?", text: $note)
            Button("Submit") {
                Task {
                    try? await BitesAPI.report(targetType: "user", targetID: handle, reason: "user_report", details: note)
                    UIAccessibility.post(notification: .announcement, argument: "Report sent")
                    note = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

enum ProfileBlockStore {
    private static let key = "profiles.blocked.v1"
    static func block(_ handle: String) {
        var s = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        s.insert(handle.lowercased())
        UserDefaults.standard.set(Array(s), forKey: key)
    }
    static func isBlocked(_ handle: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(handle.lowercased())
    }
}

// MARK: - Typing indicator / read receipts chrome

struct TypingIndicatorDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            if reduceMotion {
                Text("Typing…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(0..<3, id: \.self) { i in
                    Circle().frame(width: 6, height: 6).opacity(0.4 + Double(i) * 0.2)
                }
                Text("Typing").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Typing")
    }
}

struct ReadReceiptToggleRow: View {
    @AppStorage(SettingsKey.sendReadReceipts) private var send = true
    var body: some View {
        Toggle("Send read receipts", isOn: $send)
            .accessibilityHint("When off, others won’t see when you read their messages")
    }
}

import Foundation

/// One row from GET /v1/social/calls/history.
struct BlindbanditCallRecord: Identifiable, Decodable, Equatable {
    let id: String
    let kind: String
    let status: String
    let created_at: Double
    let ended_at: Double?
    let direction: String
    let other: BlindbanditConversation.Other?

    var isVideo: Bool { kind == "video" }
    var isIncoming: Bool { direction == "incoming" }
    var startedAt: Date { Date(timeIntervalSince1970: created_at / 1000) }

    /// Seconds the call lasted, when the server recorded an end time.
    var durationSeconds: Int? {
        guard let ended_at, ended_at > created_at else { return nil }
        return Int((ended_at - created_at) / 1000)
    }

    /// Plain-language state. A call still 'ringing' more than a minute later was never answered,
    /// so we show it as missed (incoming) or not answered (outgoing) instead of claiming it rings.
    var stateLabel: String {
        let stale = Date().timeIntervalSince(startedAt) > 60
        switch status {
        case "ringing" where stale: return isIncoming ? "Missed" : "Not answered"
        case "ringing": return isIncoming ? "Ringing" : "Calling"
        case "active": return "In progress"
        case "missed": return isIncoming ? "Missed" : "Not answered"
        case "declined": return "Declined"
        case "cancelled", "canceled": return "Cancelled"
        case "ended":
            if let d = durationSeconds, d > 0 { return isIncoming ? "Incoming" : "Outgoing" }
            return isIncoming ? "Missed" : "Not answered"
        default: return status.capitalized
        }
    }

    var isMissed: Bool { isIncoming && ["Missed"].contains(stateLabel) }
}

struct BlindbanditBlockedProfile: Identifiable, Decodable, Equatable {
    let handle: String
    let display_name: String?
    var id: String { handle }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? (try? c.decode(String.self, forKey: .blocked_handle)) ?? ""
        display_name = try? c.decodeIfPresent(String.self, forKey: .display_name)
    }

    enum CodingKeys: String, CodingKey { case handle, blocked_handle, display_name }
}

struct BlindbanditSocialNotification: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let detail: String
    let created_at: Double
    let isRead: Bool
    let link: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        let type = (try? c.decode(String.self, forKey: .type)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? (type.isEmpty ? "Notification" : type.replacingOccurrences(of: "_", with: " ").capitalized)
        detail = (try? c.decode(String.self, forKey: .body)) ?? (try? c.decode(String.self, forKey: .message)) ?? ""
        created_at = (try? c.decode(Double.self, forKey: .created_at)) ?? 0
        let readAt = try? c.decodeIfPresent(Double.self, forKey: .read_at)
        isRead = readAt != nil || FlexibleBool.decode(c, .read) == true
        link = (try? c.decodeIfPresent(String.self, forKey: .deep_link)) ?? (try? c.decodeIfPresent(String.self, forKey: .url))
    }

    enum CodingKeys: String, CodingKey { case id, type, title, body, message, created_at, read_at, read, deep_link, url }
}

struct PendingMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    let handle: String
    let body: String
    var created = Date()
}

/// Small preferences kept only on this iPhone (no server copy exists for these).
enum LocalComms {
    private static let defaults = UserDefaults.standard

    static var lastRead: [String: Double] {
        get { defaults.dictionary(forKey: "comms.lastRead") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "comms.lastRead") }
    }

    static var pinned: Set<String> {
        get { Set(defaults.stringArray(forKey: "comms.pinned") ?? []) }
        set { defaults.set(Array(newValue), forKey: "comms.pinned") }
    }

    /// Conversation id -> mute end time (seconds since 1970). 0 means "until I turn it back on".
    static var muteUntil: [String: Double] {
        get {
            var map = defaults.dictionary(forKey: "comms.muteUntil") as? [String: Double] ?? [:]
            // Migrate the 1.8 "muted forever" list.
            if let legacy = defaults.stringArray(forKey: "comms.muted"), !legacy.isEmpty {
                for id in legacy where map[id] == nil { map[id] = 0 }
                defaults.removeObject(forKey: "comms.muted")
                defaults.set(map, forKey: "comms.muteUntil")
            }
            return map
        }
        set { defaults.set(newValue, forKey: "comms.muteUntil") }
    }

    /// Conversations muted right now (expired timers are ignored).
    static var muted: Set<String> {
        get { activeMutes(muteUntil, now: Date()) }
        set {
            var map = muteUntil
            for id in map.keys where !newValue.contains(id) { map[id] = nil }
            for id in newValue where map[id] == nil { map[id] = 0 }
            muteUntil = map
        }
    }

    static func activeMutes(_ map: [String: Double], now: Date) -> Set<String> {
        Set(map.filter { $0.value == 0 || $0.value > now.timeIntervalSince1970 }.keys)
    }

    static func mute(_ id: String, for duration: TimeInterval?) {
        var map = muteUntil
        map[id] = duration.map { Date().addingTimeInterval($0).timeIntervalSince1970 } ?? 0
        muteUntil = map
    }

    static func unmute(_ id: String) {
        var map = muteUntil
        map[id] = nil
        muteUntil = map
    }

    /// Removes expired timers and returns the ids that just expired.
    static func expireMutes(now: Date = Date()) -> [String] {
        var map = muteUntil
        let expired = map.filter { $0.value != 0 && $0.value <= now.timeIntervalSince1970 }.map(\.key)
        for id in expired { map[id] = nil }
        if !expired.isEmpty { muteUntil = map }
        return expired
    }

    /// Conversation id -> updated_at when archived or deleted for me. It reappears when a newer message arrives.
    static var archivedAt: [String: Double] {
        get { defaults.dictionary(forKey: "comms.archivedAt") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "comms.archivedAt") }
    }

    static var deletedAt: [String: Double] {
        get { defaults.dictionary(forKey: "comms.deletedAt") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "comms.deletedAt") }
    }

    /// Message ids hidden on this phone only ("Delete for me").
    static var hiddenMessages: Set<String> {
        get { Set(defaults.stringArray(forKey: "comms.hiddenMessages") ?? []) }
        set { defaults.set(Array(newValue), forKey: "comms.hiddenMessages") }
    }

    /// Message id -> my reaction emoji, kept on this phone and sent to the server when the route exists.
    static var reactions: [String: String] {
        get { defaults.dictionary(forKey: "comms.reactions") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "comms.reactions") }
    }

    static var favorites: [String] {
        get { defaults.stringArray(forKey: "comms.favorites") ?? [] }
        set { defaults.set(newValue, forKey: "comms.favorites") }
    }

    static var recents: [String] {
        get { defaults.stringArray(forKey: "comms.recents") ?? [] }
        set { defaults.set(Array(newValue.prefix(8)), forKey: "comms.recents") }
    }

    static func recordRecent(_ handle: String) {
        recents = [handle] + recents.filter { $0 != handle }
    }

    static func draft(for conversationID: String) -> String {
        (defaults.dictionary(forKey: "comms.drafts") as? [String: String])?[conversationID] ?? ""
    }

    static func setDraft(_ text: String, for conversationID: String) {
        var all = defaults.dictionary(forKey: "comms.drafts") as? [String: String] ?? [:]
        all[conversationID] = text.isEmpty ? nil : text
        defaults.set(all, forKey: "comms.drafts")
    }

    static var pending: [PendingMessage] {
        get {
            guard let data = defaults.data(forKey: "comms.pending") else { return [] }
            return (try? JSONDecoder().decode([PendingMessage].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "comms.pending") }
    }
}

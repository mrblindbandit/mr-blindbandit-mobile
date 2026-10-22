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

    static var muted: Set<String> {
        get { Set(defaults.stringArray(forKey: "comms.muted") ?? []) }
        set { defaults.set(Array(newValue), forKey: "comms.muted") }
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

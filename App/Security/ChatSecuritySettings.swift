import Foundation

/// Which chat a security route applies to.
enum ChatRef: Hashable, Codable {
    case dm(conversationID: String, handle: String)
    case group(id: String)

    var key: String {
        switch self {
        case .dm(let cid, _): return "dm:\(cid)"
        case .group(let id): return "group:\(id)"
        }
    }

    /// Path prefix under /v1/social for this chat.
    var basePath: String {
        switch self {
        case .dm(let cid, _): return "v1/social/messages/\(ChatRef.escape(cid))"
        case .group(let id): return "v1/social/groups/\(ChatRef.escape(id))"
        }
    }

    func messagePath(_ mid: String) -> String {
        switch self {
        case .dm: return "\(basePath)/\(ChatRef.escape(mid))"
        case .group: return "\(basePath)/messages/\(ChatRef.escape(mid))"
        }
    }

    var isGroup: Bool { if case .group = self { return true }; return false }

    static func escape(_ v: String) -> String {
        v.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? v
    }
}

/// Per-chat settings (site contract §4). Every field decodes leniently so older/newer servers never crash the app.
struct ChatSecuritySettings: Codable, Equatable {
    struct Security: Codable, Equatable {
        var screenshot_alerts = true
        var block_link_previews = false
        var strip_photo_metadata = false
        var allow_view_once = true
    }
    struct Mine: Codable, Equatable {
        var hide_previews = false
        var read_receipts = true
        var typing = true
        var chat_lock = false
        var flag_secure = false
        var translate = true
        var mute_sound = false
    }
    struct Group: Codable, Equatable {
        var slow_mode_seconds = 0
        var admins_only_post = false
        var require_approval = false
    }

    var e2ee = true
    var disappearing_seconds = 0
    var no_store = false
    var security = Security()
    var my = Mine()
    var group: Group?
    var updated_by: String?
    var updated_at: Double?

    static let timerOptions: [(seconds: Int, label: String)] = [
        (0, "Off"), (30, "30 seconds"), (300, "5 minutes"), (3600, "1 hour"), (28800, "8 hours"),
        (86400, "24 hours"), (604800, "7 days"), (7776000, "90 days")
    ]

    static func timerLabel(_ seconds: Int) -> String {
        timerOptions.first { $0.seconds == seconds }?.label ?? "\(seconds) seconds"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        e2ee = c.lenientBool(.e2ee) ?? true
        disappearing_seconds = (try? c.decode(Int.self, forKey: .disappearing_seconds)) ?? 0
        no_store = c.lenientBool(.no_store) ?? false
        security = (try? c.decode(Security.self, forKey: .security)) ?? Security()
        my = (try? c.decode(Mine.self, forKey: .my)) ?? Mine()
        group = try? c.decode(Group.self, forKey: .group)
        updated_by = try? c.decode(String.self, forKey: .updated_by)
        updated_at = try? c.decode(Double.self, forKey: .updated_at)
    }
}

extension ChatSecuritySettings.Security {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenshot_alerts = c.lenientBool(.screenshot_alerts) ?? true
        block_link_previews = c.lenientBool(.block_link_previews) ?? false
        strip_photo_metadata = c.lenientBool(.strip_photo_metadata) ?? false
        allow_view_once = c.lenientBool(.allow_view_once) ?? true
    }
}

extension ChatSecuritySettings.Mine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hide_previews = c.lenientBool(.hide_previews) ?? false
        read_receipts = c.lenientBool(.read_receipts) ?? true
        typing = c.lenientBool(.typing) ?? true
        chat_lock = c.lenientBool(.chat_lock) ?? false
        flag_secure = c.lenientBool(.flag_secure) ?? false
        translate = c.lenientBool(.translate) ?? true
        mute_sound = c.lenientBool(.mute_sound) ?? false
    }
}

extension ChatSecuritySettings.Group {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slow_mode_seconds = (try? c.decode(Int.self, forKey: .slow_mode_seconds)) ?? 0
        admins_only_post = c.lenientBool(.admins_only_post) ?? false
        require_approval = c.lenientBool(.require_approval) ?? false
    }
}

extension KeyedDecodingContainer {
    func lenientBool(_ key: Key) -> Bool? {
        if let b = try? decode(Bool.self, forKey: key) { return b }
        if let i = try? decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? decode(String.self, forKey: key) { return ["1", "true", "yes"].contains(s.lowercased()) }
        return nil
    }
}

/// Remembers which server routes answered 404 so the UI can show "Needs server update" instead of failing repeatedly.
/// Entries expire after 6 hours so features light up once the site deploys.
final class ServerFeatures: @unchecked Sendable {
    static let shared = ServerFeatures()
    static let needsUpdateText = "Needs server update"

    enum Feature: String, CaseIterable {
        case keys, settings, clearServer, unsend, viewOnce, securityEvents, export, deleteMine, relay, attachments
        case sessions, inviteLinks, joinRequests, edit, envelopeFetch, keyWrap, reportEvidence
    }

    private let lock = NSLock()
    static let needsUpdateText = "Needs server update"
    private var missing: [String: Date] = [:]
    private let defaults: UserDefaults
    private let ttl: TimeInterval

    init(defaults: UserDefaults = .standard, ttl: TimeInterval = 6 * 3600) {
        self.defaults = defaults
        self.ttl = ttl
        let stored = defaults.dictionary(forKey: "bb.serverFeatures.missing") as? [String: Double] ?? [:]
        missing = stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func isAvailable(_ f: Feature, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let at = missing[f.rawValue] else { return true }
        return now.timeIntervalSince(at) > ttl
    }

    func markMissing(_ f: Feature, now: Date = Date()) { update { $0[f.rawValue] = now } }
    func markAvailable(_ f: Feature) { update { $0[f.rawValue] = nil } }

    private func update(_ body: (inout [String: Date]) -> Void) {
        lock.lock()
        body(&missing)
        let snapshot = missing.mapValues { $0.timeIntervalSince1970 }
        lock.unlock()
        defaults.set(snapshot, forKey: "bb.serverFeatures.missing")
    }
}

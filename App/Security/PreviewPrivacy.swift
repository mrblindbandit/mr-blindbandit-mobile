import Foundation

/// Shares per-chat "Hide notification previews" and "Mute notification sound" with the
/// Notification Service Extension through the App Group. The extension never sees decrypted
/// bodies when hide is on — only a generic "Message" (or sender-only title).
enum PreviewPrivacy {
    static let appGroup = "group.net.mrblindbandit.app"

    private static var suite: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Writes prefs under every id the push payload might use (chat.key, raw conversation/group id).
    static func sync(chat: ChatRef, hidePreviews: Bool, muteSound: Bool) {
        let keys = storageKeys(for: chat)
        guard let suite else { return }
        for k in keys {
            suite.set(hidePreviews, forKey: "hidePreviews." + k)
            suite.set(muteSound, forKey: "muteSound." + k)
        }
        suite.synchronize()
    }

    static func hidePreviews(userInfo info: [AnyHashable: Any]) -> Bool {
        lookup(prefix: "hidePreviews.", info: info)
    }

    static func muteSound(userInfo info: [AnyHashable: Any]) -> Bool {
        lookup(prefix: "muteSound.", info: info)
    }

    private static func lookup(prefix: String, info: [AnyHashable: Any]) -> Bool {
        guard let suite else { return false }
        for k in candidateKeys(info) where suite.bool(forKey: prefix + k) { return true }
        return false
    }

    private static func storageKeys(for chat: ChatRef) -> [String] {
        switch chat {
        case .dm(let cid, _):
            return Array(Set([chat.key, cid, "dm:\(cid)"]))
        case .group(let id):
            return Array(Set([chat.key, id, "group:\(id)"]))
        }
    }

    private static func candidateKeys(_ info: [AnyHashable: Any]) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let s, !s.isEmpty else { return }
            out.append(s)
        }
        add(info["chat_id"] as? String)
        add(info["conversation_id"] as? String)
        add(info["conversationId"] as? String)
        add(info["thread_id"] as? String)
        if let c = info["conversation_id"] as? String ?? info["conversationId"] as? String {
            add("dm:\(c)")
        }
        if let g = info["group_id"] as? String ?? info["groupId"] as? String {
            add(g)
            add("group:\(g)")
        }
        return out
    }
}

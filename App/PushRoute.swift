import Foundation
import SwiftUI

/// Where a tapped notification (or a VoIP push) should take the user. Parsing is pure so it is unit tested.
enum PushRoute: Equatable {
    /// A direct-message thread. `id` is the conversation id; `handle` is the fallback when the payload has no id.
    case conversation(id: String?, handle: String?)
    case group(id: String)
    case call(id: String)
    case article(URL)
    case web(URL)

    var isArticle: Bool { if case .article = self { return true } else { return false } }

    /// Parses an APNs/FCM payload. Understands both the live server payload
    /// (`deep_link: "/mobile/messages/?c=<id>"`) and the 1.9 contract
    /// (`conversation_id`, `from_handle`, `group_id`, `call_id`, `deep_link: "/mobile/messages/?id=<id>"`).
    static func parse(_ raw: [AnyHashable: Any]) -> PushRoute? {
        let info = flatten(raw)
        func str(_ keys: String...) -> String? {
            for key in keys {
                if let s = info[key] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s.trimmingCharacters(in: .whitespaces) }
                if let n = info[key] as? NSNumber { return n.stringValue }
            }
            return nil
        }
        let type = (str("type", "category", "kind") ?? "").lowercased()
        let senderHandle = str("from_handle", "sender_handle", "handle", "fromHandle", "senderHandle").map(BlindbanditHandle.normalize)
        let conversationID = str("conversation_id", "conversationId", "conversationID", "c", "thread_id", "threadId")
        // Links: deep_link / url / link, relative paths or full first-party URLs.
        for key in ["deep_link", "deepLink", "url", "link"] {
            guard let link = str(key) else { continue }
            let url = URL(string: link, relativeTo: URL(string: "https://mrblindbandit.net"))?.absoluteURL
            if let url, let route = parse(url: url) {
                if case .web = route, url.host?.lowercased().hasSuffix("mrblindbandit.net") != true, key != "url" { continue }
                if case .conversation(let id, nil) = route, let senderHandle { return .conversation(id: id, handle: senderHandle) }
                return route
            }
        }
        if let slug = str("article_slug", "slug"), let url = URL(string: "mrblindbandit://article/\(slug)") {
            return .article(url)
        }
        if let callID = str("call_id", "callId"), type.contains("call") || conversationID == nil {
            return .call(id: callID)
        }
        if let groupID = str("group_id", "groupId"), conversationID == nil || type.contains("group") {
            return .group(id: groupID)
        }
        if let conversationID {
            return .conversation(id: conversationID, handle: senderHandle)
        }
        // aps.thread-id is a grouping key; only trust it when it looks like an id.
        if let thread = str("thread-id"), thread.count >= 8, !thread.contains(" ") {
            let id = thread.hasPrefix("conversation:") || thread.hasPrefix("dm:") ? String(thread.split(separator: ":", maxSplits: 1)[1]) : thread
            return .conversation(id: id, handle: senderHandle)
        }
        if let senderHandle, !senderHandle.isEmpty, !type.contains("call") {
            return .conversation(id: nil, handle: senderHandle)
        }
        return nil
    }

    /// Merges nested `aps`, `data`, `payload`, `custom` and JSON-string payloads into one flat dictionary
    /// (top-level keys win), so every server shape is read the same way.
    static func flatten(_ info: [AnyHashable: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        func merge(_ dict: [AnyHashable: Any], depth: Int) {
            guard depth < 4 else { return }
            for (k, v) in dict { if let key = k as? String, out[key] == nil, !(v is [AnyHashable: Any]) { out[key] = v } }
            for key in ["data", "payload", "custom", "extra", "aps", "message", "meta"] {
                if let nested = dict[key] as? [AnyHashable: Any] { merge(nested, depth: depth + 1) }
                else if let text = dict[key] as? String, text.hasPrefix("{"),
                        let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] { merge(obj, depth: depth + 1) }
            }
        }
        merge(info, depth: 0)
        return out
    }

    /// Key names only (never values) for debugging push routing.
    static func keySummary(_ info: [AnyHashable: Any]) -> String {
        flatten(info).keys.sorted().joined(separator: ",")
    }

    /// Parses a first-party link such as https://mrblindbandit.net/mobile/messages/?id=… or mrblindbandit://messages/….
    static func parse(url: URL) -> PushRoute? {
        if let article = ChronicleDeepLink.articleURL(from: url) { return .article(article) }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        func query(_ names: String...) -> String? {
            for name in names {
                if let v = components?.queryItems?.first(where: { $0.name == name })?.value, !v.isEmpty { return v }
            }
            return nil
        }
        var path = url.path
        if url.scheme == "mrblindbandit" { path = "/mobile/" + (url.host ?? "") + url.path }
        let segments = path.split(separator: "/").map(String.init)
        let trailing = segments.count >= 3 ? segments[2] : nil
        if path.hasPrefix("/mobile/messages") || path.hasPrefix("/messages") || path.hasPrefix("/mobile/inbox") {
            let id = query("id", "c", "conversation_id") ?? trailing
            let handle = query("handle", "from_handle").map(BlindbanditHandle.normalize)
            return .conversation(id: id, handle: handle)
        }
        if path.hasPrefix("/mobile/groups") || path.hasPrefix("/groups") {
            guard let id = query("id", "group_id") ?? trailing else { return nil }
            return .group(id: id)
        }
        if path.hasPrefix("/mobile/calls") || path.hasPrefix("/calls") {
            guard let id = query("id", "call_id") ?? trailing else { return nil }
            return .call(id: id)
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return .web(url) }
        return nil
    }
}

/// Holds a tapped-notification route until the UI that can show it exists. On a cold start the
/// app may still be signing in or waiting for Face ID; the route survives until MainTabs consumes it.
@MainActor
final class PendingRouter: ObservableObject {
    static let shared = PendingRouter()
    @Published var pending: PushRoute?

    func consume() -> PushRoute? {
        defer { pending = nil }
        return pending
    }
}

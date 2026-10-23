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
    static func parse(_ info: [AnyHashable: Any]) -> PushRoute? {
        func str(_ key: String) -> String? {
            if let s = info[key] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
            if let n = info[key] as? NSNumber { return n.stringValue }
            return nil
        }
        let type = (str("type") ?? str("category") ?? "").lowercased()
        if let raw = str("url"), let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            if let route = parse(url: url) { return route }
        }
        if let slug = str("article_slug") ?? str("slug"), let url = URL(string: "mrblindbandit://article/\(slug)") {
            return .article(url)
        }
        if let callID = str("call_id"), type.contains("call") || str("conversation_id") == nil {
            return .call(id: callID)
        }
        if let groupID = str("group_id"), str("conversation_id") == nil {
            return .group(id: groupID)
        }
        if let conversation = str("conversation_id") {
            return .conversation(id: conversation, handle: str("from_handle").map(BlindbanditHandle.normalize))
        }
        if let link = str("deep_link"), let url = URL(string: link, relativeTo: URL(string: "https://mrblindbandit.net")) {
            if let route = parse(url: url.absoluteURL) {
                if case .conversation(let id, nil) = route, let handle = str("from_handle") {
                    return .conversation(id: id, handle: BlindbanditHandle.normalize(handle))
                }
                return route
            }
        }
        if let handle = str("from_handle"), type.contains("message") || type.isEmpty {
            return .conversation(id: nil, handle: BlindbanditHandle.normalize(handle))
        }
        return nil
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

import Foundation

/// Maps an admin button to a route that exists on the Blindbandit platform API.
/// Actions with no route are reported and are not sent.
struct AdminRoutePlan: Equatable {
    var method: String
    var path: String
    var body: [String: String]
    /// Human explanation when the live API has no such action. Nil means the request is real.
    var unavailableReason: String?

    static func userAction(action: String, userId: String, reason: String? = nil, until: Int? = nil, multiplier: Int? = nil, title: String? = nil, message: String? = nil) -> AdminRoutePlan {
        let id = userId.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let base = "v1/social/admin/users/\(id)"
        switch action {
        case "verify":
            return AdminRoutePlan(method: "POST", path: "\(base)/verify", body: [:], unavailableReason: nil)
        case "unverify":
            return AdminRoutePlan(method: "POST", path: "\(base)/unverify", body: [:], unavailableReason: nil)
        case "ban":
            return AdminRoutePlan(method: "POST", path: "\(base)/ban", body: reason.map { ["reason": $0] } ?? [:], unavailableReason: nil)
        case "suspend":
            let end = until ?? Int(Date().timeIntervalSince1970) + 7 * 86400
            var body = ["until": String(end)]
            if let reason, !reason.isEmpty { body["reason"] = reason }
            return AdminRoutePlan(method: "POST", path: "\(base)/suspend", body: body, unavailableReason: nil)
        case "reinstate":
            return AdminRoutePlan(method: "POST", path: "\(base)/reinstate", body: [:], unavailableReason: nil)
        case "mute_posts":
            return restrictions(base, ["mute_posts": "true"])
        case "unmute_posts":
            return restrictions(base, ["mute_posts": "false"])
        case "mute_messages":
            return restrictions(base, ["mute_messages": "true"])
        case "disable_calls":
            return restrictions(base, ["calls_disabled": "true"])
        case "enable_calls":
            return restrictions(base, ["calls_disabled": "false"])
        case "shadow":
            return restrictions(base, ["shadow_restricted": "true"])
        case "rate_limit":
            return restrictions(base, ["rate_limit_multiplier": String(multiplier ?? 1)])
        case "revoke_push":
            return AdminRoutePlan(method: "POST", path: "\(base)/devices/revoke", body: [:], unavailableReason: nil)
        case "force_disconnect":
            return AdminRoutePlan(method: "POST", path: "\(base)/calls/disconnect", body: [:], unavailableReason: nil)
        case "monetize_approve":
            return AdminRoutePlan(method: "POST", path: "\(base)/monetization", body: ["approve": "true"], unavailableReason: nil)
        case "monetize_reject":
            return AdminRoutePlan(method: "POST", path: "\(base)/monetization", body: ["approve": "false"], unavailableReason: nil)
        case "test_push":
            var body = ["user_id": id]
            if let title, !title.isEmpty { body["title"] = title }
            if let message, !message.isEmpty { body["body"] = message }
            return AdminRoutePlan(method: "POST", path: "v1/social/admin/notifications/test", body: body, unavailableReason: nil)
        case "wipe_sessions", "pin", "unpin":
            return AdminRoutePlan(method: "", path: "", body: [:], unavailableReason: "The server has no \(action.replacingOccurrences(of: "_", with: " ")) route. Nothing was changed.")
        default:
            return AdminRoutePlan(method: "", path: "", body: [:], unavailableReason: "Unknown admin action \(action). Nothing was sent.")
        }
    }

    private static func restrictions(_ base: String, _ fields: [String: String]) -> AdminRoutePlan {
        AdminRoutePlan(method: "PATCH", path: "\(base)/restrictions", body: fields, unavailableReason: nil)
    }
}

/// What `POST /v1/social/calls` should send. Agora is the default. LiveKit is used when the server says so, or when Agora is explicitly not configured.
enum CallProviderPlan {
    static func createField(serverPreferred: String?, agoraConfigured: Bool?) -> String? {
        let preferred = serverPreferred?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if preferred == "livekit" { return nil }
        if agoraConfigured == false { return nil }
        return "agora"
    }

    static let messageTransportNote = "Messages stay on Blindbandit encrypted delivery. They are not sent through LiveKit or Agora. Agora Chat and Agora RTM are not set up in this app. Switching calls does not move chat history."
}

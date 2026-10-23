import Foundation

/// Thrown when the server doesn't have a route yet. The UI shows "Needs server update" and keeps working.
struct NeedsServerUpdate: LocalizedError {
    let feature: ServerFeatures.Feature
    var errorDescription: String? { "\(ServerFeatures.needsUpdateText). \(CommunicationsError.serverUpdateMessage)" }
}

struct SecurityEvent: Identifiable, Decodable, Equatable {
    let id: String
    let type: String
    let actor_handle: String?
    let detail: String?
    let created_at: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString
        type = (try? c.decode(String.self, forKey: .type)) ?? "event"
        actor_handle = try? c.decode(String.self, forKey: .actor_handle)
        detail = try? c.decode(String.self, forKey: .detail)
        created_at = LenientTime.decode(c, .created_at) ?? 0
    }
    init(id: String, type: String, actor: String?, detail: String?, at: Double) {
        self.id = id; self.type = type; actor_handle = actor; self.detail = detail; created_at = at
    }
    enum CodingKeys: String, CodingKey { case id, type, actor_handle, detail, created_at }

    var readable: String {
        let who = actor_handle.map { "@\($0)" } ?? "Someone"
        switch type {
        case "screenshot": return "\(who) took a screenshot"
        case "screen_recording_started": return "\(who) started recording the screen"
        case "screen_recording_stopped": return "\(who) stopped recording the screen"
        case "timer_changed": return "\(who) changed disappearing messages" + (detail.map { " (\($0))" } ?? "")
        case "e2ee_changed": return "\(who) changed end-to-end encryption"
        case "no_store_changed": return "\(who) changed relay-only mode"
        case "security_changed": return "\(who) changed chat security settings"
        case "cleared": return "\(who) cleared this chat from the server"
        case "key_changed", "key_changed_seen": return "Safety number changed for \(who)"
        case "safety_number_verified": return "\(who) verified the safety number"
        case "view_once_opened": return "\(who) opened a view-once message"
        case "device_added": return "\(who) added a new device"
        default: return "\(who): \(type.replacingOccurrences(of: "_", with: " "))" + (detail.map { " (\($0))" } ?? "")
        }
    }
}

struct SessionInfo: Identifiable, Decodable, Equatable {
    let id: String
    let device_name: String
    let platform: String
    let last_active_at: Double?
    let current: Bool
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        device_name = (try? c.decode(String.self, forKey: .device_name)) ?? "Unknown device"
        platform = (try? c.decode(String.self, forKey: .platform)) ?? ""
        last_active_at = LenientTime.decode(c, .last_active_at)
        current = c.lenientBool(.current) ?? false
    }
    enum CodingKeys: String, CodingKey { case id, device_name, platform, last_active_at, current }
}

struct JoinRequest: Identifiable, Decodable, Equatable {
    let id: String
    let handle: String
    let display_name: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
        display_name = try? c.decode(String.self, forKey: .display_name)
    }
    enum CodingKeys: String, CodingKey { case id, handle, display_name }
}

/// Every server-dependent security route (site contract). Each call is gated through ServerFeatures.
@MainActor
enum SecurityAPI {
    @discardableResult
    /// Runs a request; on a missing route marks the feature unavailable and throws NeedsServerUpdate.
    static func gated<T>(_ feature: ServerFeatures.Feature, _ work: () async throws -> T) async throws -> T {
        do {
            let value = try await work()
            ServerFeatures.shared.markAvailable(feature)
            return value
        } catch let error as CommunicationsError {
            if case .notFound = error, error.isMissingRoute {
                ServerFeatures.shared.markMissing(feature)
                throw NeedsServerUpdate(feature: feature)
            }
            throw error
        }
    }

    static func data(_ data: Data) -> [String: Any] {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return obj["data"] as? [String: Any] ?? obj
    }

    // MARK: Settings
    static func settings(_ chat: ChatRef) async throws -> ChatSecuritySettings {
        try await gated(.settings) {
            let d = try await BlindbanditAPI.request("\(chat.basePath)/settings")
            if let s = try? BlindbanditAPI.decode(ChatSecuritySettings.self, from: d) { return s }
            return (try? JSONDecoder().decode(ChatSecuritySettings.self, from: d)) ?? ChatSecuritySettings()
        }
    }

    @discardableResult
    static func patchSettings(_ chat: ChatRef, _ patch: [String: Any]) async throws -> ChatSecuritySettings? {
        try await gated(.settings) {
            let d = try await BlindbanditAPI.request("\(chat.basePath)/settings", method: "PATCH", body: patch)
            return try? BlindbanditAPI.decode(ChatSecuritySettings.self, from: d)
        }
    }

    // MARK: Messages
    static func clearServer(_ chat: ChatRef, scope: String? = nil) async throws {
        var body: [String: Any] = ["confirm": true]
        if let scope { body["scope"] = scope }
        try await gated(.clearServer) { try await BlindbanditAPI.request("\(chat.basePath)/clear-server", method: "POST", body: body) }
    }

    /// Unsend: deletes for everyone, no time limit.
    static func unsend(_ chat: ChatRef, messageID: String) async throws {
        try await gated(.unsend) { try await BlindbanditAPI.request(chat.messagePath(messageID), method: "DELETE") }
    }

    static func edit(_ chat: ChatRef, messageID: String, envelope: E2EEEnvelope) async throws {
        try await gated(.edit) {
            try await BlindbanditAPI.request(chat.messagePath(messageID), method: "PATCH", body: ["envelope": envelope.jsonObject])
        }
    }

    /// Returns the envelope once; nil when it was already opened (410).
    static func openViewOnce(_ chat: ChatRef, messageID: String) async throws -> E2EEEnvelope? {
        try await gated(.viewOnce) {
            do {
                let d = try await BlindbanditAPI.request("\(chat.messagePath(messageID))/view-once/open", method: "POST", body: [:])
                return E2EEEnvelope.from(any: data(d)["envelope"])
            } catch CommunicationsError.server(let m) where m.lowercased().contains("opened") {
                return nil
            }
        }
    }

    static func postSecurityEvent(_ chat: ChatRef, type: String) async {
        guard ServerFeatures.shared.isAvailable(.securityEvents) else { return }
        _ = try? await gated(.securityEvents) {
            try await BlindbanditAPI.request("\(chat.basePath)/security-events", method: "POST", body: ["type": type])
        }
    }

    static func securityEvents(_ chat: ChatRef) async throws -> [SecurityEvent] {
        try await gated(.securityEvents) {
            try BlindbanditAPI.decode(ItemsPayload<SecurityEvent>.self, from: try await BlindbanditAPI.request("\(chat.basePath)/security-events?limit=100")).items
        }
    }

    static func export(_ chat: ChatRef) async throws -> Data {
        try await gated(.export) { try await BlindbanditAPI.request("\(chat.basePath)/export") }
    }

    static func deleteMine(_ chat: ChatRef) async throws {
        try await gated(.deleteMine) { try await BlindbanditAPI.request("\(chat.basePath)/mine", method: "DELETE") }
    }

    // MARK: Relay-only
    struct RelayItem { let id: String; let chatType: String; let chatID: String; let messageID: String; let sender: String; let envelope: E2EEEnvelope?; let createdAt: Double }

    static func relayPending() async throws -> [RelayItem] {
        try await gated(.relay) {
            let obj = data(try await BlindbanditAPI.request("v1/social/relay/pending"))
            return (obj["items"] as? [[String: Any]] ?? []).map {
                RelayItem(id: "\($0["id"] ?? "")", chatType: $0["chat_type"] as? String ?? "dm", chatID: "\($0["chat_id"] ?? "")",
                          messageID: "\($0["message_id"] ?? "")", sender: $0["sender_handle"] as? String ?? "",
                          envelope: E2EEEnvelope.from(any: $0["envelope"]), createdAt: ($0["created_at"] as? Double) ?? Date().timeIntervalSince1970)
            }
        }
    }

    static func relayAck(deviceID: String, ids: [String]) async {
        guard !ids.isEmpty else { return }
        _ = try? await gated(.relay) {
            try await BlindbanditAPI.request("v1/social/relay/ack", method: "POST", body: ["device_id": deviceID, "ids": ids])
        }
    }

    // MARK: Attachments
    struct UploadSlot { let attachmentID: String; let url: URL }

    static func createAttachment(size: Int, chat: ChatRef) async throws -> UploadSlot {
        try await gated(.attachments) {
            var body: [String: Any] = ["size": size, "chat_type": chat.isGroup ? "group" : "dm"]
            switch chat { case .dm(let cid, _): body["chat_id"] = cid; case .group(let id): body["chat_id"] = id }
            let obj = data(try await BlindbanditAPI.request("v1/social/attachments", method: "POST", body: body))
            guard let id = obj["attachment_id"] as? String, let upload = obj["upload"] as? [String: Any],
                  let raw = upload["url"] as? String, let url = URL(string: raw) else { throw CommunicationsError.invalidResponse }
            return UploadSlot(attachmentID: id, url: url)
        }
    }

    static func attachmentURL(id: String) async throws -> URL {
        try await gated(.attachments) {
            let obj = data(try await BlindbanditAPI.request("v1/social/attachments/\(ChatRef.escape(id))"))
            guard let raw = (obj["url"] as? String) ?? (obj["download_url"] as? String), let url = URL(string: raw) else { throw CommunicationsError.invalidResponse }
            return url
        }
    }

    // MARK: Sessions
    static func sessions() async throws -> [SessionInfo] {
        try await gated(.sessions) {
            try BlindbanditAPI.decode(ItemsPayload<SessionInfo>.self, from: try await BlindbanditAPI.request("v1/social/sessions")).items
        }
    }

    static func signOut(session id: String) async throws {
        try await gated(.sessions) { try await BlindbanditAPI.request("v1/social/sessions/\(ChatRef.escape(id))", method: "DELETE") }
    }

    // MARK: Groups
    static func createInviteLink(groupID: String) async throws -> String {
        try await gated(.inviteLinks) {
            let obj = data(try await BlindbanditAPI.request("v1/social/groups/\(ChatRef.escape(groupID))/invite-links", method: "POST", body: [:]))
            return (obj["url"] as? String) ?? "https://mrblindbandit.net/join/\(obj["token"] as? String ?? "")"
        }
    }

    static func revokeInviteLink(groupID: String, token: String) async throws {
        try await gated(.inviteLinks) {
            do { try await BlindbanditAPI.request("v1/social/groups/\(ChatRef.escape(groupID))/invite-links/\(ChatRef.escape(token))", method: "DELETE") }
            catch { throw NeedsServerUpdate(feature: .inviteLinks) } // revoke route not live yet (404/405)
        }
    }

    /// Returns "joined" or "pending".
    static func join(token: String) async throws -> String {
        try await gated(.inviteLinks) {
            let obj = data(try await BlindbanditAPI.request("v1/social/groups/join/\(ChatRef.escape(token))", method: "POST", body: [:]))
            return obj["status"] as? String ?? "joined"
        }
    }

    static func joinRequests(groupID: String) async throws -> [JoinRequest] {
        try await gated(.joinRequests) {
            try BlindbanditAPI.decode(ItemsPayload<JoinRequest>.self, from: try await BlindbanditAPI.request("v1/social/groups/\(ChatRef.escape(groupID))/join-requests")).items
        }
    }

    static func answerJoinRequest(groupID: String, requestID: String, approve: Bool) async throws {
        try await gated(.joinRequests) {
            do {
                try await BlindbanditAPI.request("v1/join-requests/\(ChatRef.escape(requestID))", method: "POST", body: ["approve": approve, "status": approve ? "approved" : "declined"])
            } catch {
                try await BlindbanditAPI.request("v1/social/groups/\(ChatRef.escape(groupID))/join-requests/\(ChatRef.escape(requestID))", method: "POST", body: ["approve": approve])
            }
        }
    }

    // MARK: Reports with evidence (§12)
    static func reportWithEvidence(chat: ChatRef, targetType: String, targetID: String, reason: String,
                                   messages: [(id: String, sender: String, text: String, at: Double, envelopeSHA: String)]) async throws {
        let evidence: [String: Any] = [
            "conversation_id": { switch chat { case .dm(let c, _): return c; case .group(let g): return g } }(),
            "chat_type": chat.isGroup ? "group" : "dm",
            "messages": messages.prefix(50).map { ["message_id": $0.id, "sender_handle": $0.sender, "plaintext": String($0.text.prefix(4000)), "created_at": $0.at, "envelope_sha256": $0.envelopeSHA] }
        ]
        do {
            try await BlindbanditAPI.request("v1/social/reports", method: "POST",
                                             body: ["target_type": targetType, "target_id": targetID, "reason": reason, "evidence": evidence])
        } catch {
            // Older servers reject unknown fields: fall back to the plain report.
            try await BlindbanditAPI.report(targetType: targetType, targetID: targetID, reason: reason, details: "")
        }
    }
}

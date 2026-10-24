import Foundation

// MARK: - People, groups and group calls (contract documented in site-ai-prompt-190.md)

/// One person from GET /v1/social/search?q=.
struct BlindbanditPerson: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    let handle: String
    let display_name: String
    let avatar_url: String?
    let verified: Bool
    let is_artist: Bool
    let bio: String?

    init(id: String, handle: String, display_name: String, avatar_url: String? = nil, verified: Bool = false, is_artist: Bool = false, bio: String? = nil) {
        self.id = id; self.handle = handle; self.display_name = display_name
        self.avatar_url = avatar_url; self.verified = verified; self.is_artist = is_artist; self.bio = bio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
        id = (try? c.decode(String.self, forKey: .id)) ?? handle
        let name = (try? c.decodeIfPresent(String.self, forKey: .display_name)) ?? nil
        display_name = (name?.isEmpty == false ? name : nil) ?? handle
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
        verified = FlexibleBool.decode(c, .verified) ?? false
        is_artist = FlexibleBool.decode(c, .is_artist) ?? false
        bio = try? c.decodeIfPresent(String.self, forKey: .bio)
    }

    enum CodingKeys: String, CodingKey { case id, handle, display_name, avatar_url, verified, is_artist, bio }

    var accessibilitySummary: String {
        var parts = ["\(display_name), @\(handle)"]
        if verified { parts.append("Verified") }
        if is_artist { parts.append("artist") }
        if let bio, !bio.isEmpty { parts.append(bio) }
        return parts.joined(separator: ", ")
    }
}

struct BlindbanditGroup: Identifiable, Decodable, Equatable, Hashable {
    let id: String
    var name: String
    var avatar_url: String?
    var member_count: Int
    var my_role: String
    var last_message_body: String?
    var last_message_at: Double?
    var updated_at: Double

    var isAdmin: Bool { ["owner", "admin"].contains(my_role) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? (try? c.decode(String.self, forKey: .title)) ?? "Group"
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
        let memberList = try? c.decode([BlindbanditGroupMember].self, forKey: .members)
        member_count = (try? c.decode(Int.self, forKey: .member_count)) ?? (try? c.decode(Int.self, forKey: .members_count)) ?? memberList?.count ?? 0
        let role = (try? c.decode(String.self, forKey: .my_role)) ?? (try? c.decode(String.self, forKey: .role)) ?? "member"
        my_role = role.isEmpty ? "member" : role.lowercased()
        updated_at = (try? c.decode(Double.self, forKey: .updated_at)) ?? (try? c.decode(Double.self, forKey: .created_at)) ?? 0
        if let last = try? c.decode(LastMessage.self, forKey: .last_message) {
            last_message_body = last.body
            last_message_at = last.created_at
        } else {
            last_message_body = nil
            last_message_at = nil
        }
    }

    struct LastMessage: Decodable { let body: String; let created_at: Double? }
    enum CodingKeys: String, CodingKey { case id, name, title, avatar_url, member_count, members_count, members, my_role, role, updated_at, created_at, last_message }
}

struct BlindbanditGroupMember: Identifiable, Decodable, Equatable, Hashable {
    let profile_id: String
    let handle: String
    let display_name: String
    let avatar_url: String?
    var role: String
    var verified: Bool = false
    var id: String { profile_id.isEmpty ? handle : profile_id }
    var isAdmin: Bool { ["owner", "admin"].contains(role) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
        profile_id = (try? c.decode(String.self, forKey: .profile_id)) ?? (try? c.decode(String.self, forKey: .id)) ?? handle
        display_name = (try? c.decode(String.self, forKey: .display_name)) ?? handle
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
        role = ((try? c.decode(String.self, forKey: .role)) ?? "member").lowercased()
        verified = FlexibleBool.decode(c, .verified) ?? false
    }

    enum CodingKeys: String, CodingKey { case profile_id, id, handle, display_name, avatar_url, role, verified }
}

/// Accepts both `{group:{...}, members:[...]}` and a flat group object with `members` inside it.
struct BlindbanditGroupDetail: Decodable {
    let group: BlindbanditGroup
    let members: [BlindbanditGroupMember]

    enum CodingKeys: String, CodingKey { case group, members }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.decode(BlindbanditGroup.self, forKey: .group) {
            group = nested
        } else {
            group = try BlindbanditGroup(from: decoder)
        }
        members = (try? c.decode([BlindbanditGroupMember].self, forKey: .members)) ?? []
    }
}

struct BlindbanditGroupMessage: Identifiable, Decodable, Equatable {
    let id: String
    let sender_id: String
    let sender_handle: String
    let sender_name: String
    var body: String
    let created_at: Double
    var e2ee = false
    var envelopeJSON: String?
    var kind = "text"
    var edited_at: Double?
    var decrypted: E2EEPayload?
    var envelope: E2EEEnvelope? { envelopeJSON.flatMap { E2EEEnvelope.from(any: $0) } }
    var delivered_at: Double? = nil
    var read_at: Double? = nil
    /// Names or @handles of members who have read it (may be empty when the server only sends a count).
    var read_by: [String] = []
    var read_count: Int = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        delivered_at = LenientTime.decode(c, .delivered_at)
        read_at = LenientTime.decode(c, .read_at) ?? LenientTime.decode(c, .last_read_at)
        if let names = try? c.decode([String].self, forKey: .read_by) {
            read_by = names
        } else if let people = try? c.decode([ReadByPerson].self, forKey: .read_by) {
            read_by = people.map(\.label)
            if read_at == nil { read_at = people.compactMap(\.read_at).max() }
        }
        read_count = (try? c.decode(Int.self, forKey: .read_count)) ?? read_by.count
        sender_id = (try? c.decode(String.self, forKey: .sender_id)) ?? (try? c.decode(String.self, forKey: .author_id)) ?? ""
        sender_handle = (try? c.decode(String.self, forKey: .sender_handle)) ?? (try? c.decode(String.self, forKey: .handle)) ?? ""
        let name = (try? c.decode(String.self, forKey: .sender_display_name)) ?? (try? c.decode(String.self, forKey: .sender_name))
            ?? (try? c.decode(String.self, forKey: .display_name))
        sender_name = name ?? (sender_handle.isEmpty ? "Member" : "@\(sender_handle)")
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        created_at = LenientTime.decode(c, .created_at) ?? LenientTime.decode(c, .sent_at) ?? 0
        e2ee = c.lenientBool(.e2ee) ?? false
        if let s = try? c.decode(String.self, forKey: .envelope) { envelopeJSON = s }
        else if let env = try? c.decode(E2EEEnvelope.self, forKey: .envelope), let d = try? JSONEncoder().encode(env) { envelopeJSON = String(data: d, encoding: .utf8) }
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "text"
        edited_at = LenientTime.decode(c, .edited_at)
    }

    struct ReadByPerson: Decodable {
        let label: String
        let read_at: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
            label = (try? c.decode(String.self, forKey: .display_name)) ?? (handle.isEmpty ? "Someone" : "@\(handle)")
            read_at = LenientTime.decode(c, .read_at)
        }
        enum CodingKeys: String, CodingKey { case handle, display_name, read_at }
    }

    enum CodingKeys: String, CodingKey { case id, sender_id, sender_handle, sender_display_name, sender_name, body, created_at, sent_at, author_id, handle, display_name, delivered_at, read_at, last_read_at, read_by, read_count, e2ee, envelope, kind, edited_at }

    /// Optimistic / local-only row before the server echoes the send.
    static func local(id: String, handle: String, name: String, body: String, kind: String = "text") -> BlindbanditGroupMessage {
        BlindbanditGroupMessage(
            id: id, sender_id: "local", sender_handle: handle, sender_name: name,
            body: body, created_at: Date().timeIntervalSince1970 * 1000, e2ee: false,
            envelopeJSON: nil, kind: kind, edited_at: nil, decrypted: nil,
            delivered_at: nil, read_at: nil, read_by: [], read_count: 0
        )
    }

    init(id: String, sender_id: String, sender_handle: String, sender_name: String, body: String,
         created_at: Double, e2ee: Bool = false, envelopeJSON: String? = nil, kind: String = "text",
         edited_at: Double? = nil, decrypted: E2EEPayload? = nil, delivered_at: Double? = nil,
         read_at: Double? = nil, read_by: [String] = [], read_count: Int = 0) {
        self.id = id; self.sender_id = sender_id; self.sender_handle = sender_handle
        self.sender_name = sender_name; self.body = body; self.created_at = created_at
        self.e2ee = e2ee; self.envelopeJSON = envelopeJSON; self.kind = kind
        self.edited_at = edited_at; self.decrypted = decrypted
        self.delivered_at = delivered_at; self.read_at = read_at
        self.read_by = read_by; self.read_count = read_count
    }
}

/// Server timestamps: epoch milliseconds (number or string), epoch seconds, or ISO 8601.
enum LenientTime {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d < 100_000_000_000 ? d * 1000 : d }
        guard let s = try? c.decode(String.self, forKey: key), !s.isEmpty else { return nil }
        if let d = Double(s) { return d < 100_000_000_000 ? d * 1000 : d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: s) { return date.timeIntervalSince1970 * 1000 }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s).map { $0.timeIntervalSince1970 * 1000 }
    }
}

/// A ringing call for me, from GET /v1/social/calls/incoming or a push payload.
struct BlindbanditIncomingCall: Identifiable, Decodable, Equatable {
    let id: String
    let kind: String
    let from_handle: String
    let from_name: String
    let from_avatar_url: String?
    let group_id: String?
    let group_name: String?
    let created_at: Double

    var isVideo: Bool { kind == "video" }
    var callerLabel: String {
        if let group_name, !group_name.isEmpty { return "\(from_name) in \(group_name)" }
        return from_name
    }

    init(id: String, kind: String, from_handle: String, from_name: String, group_id: String?, group_name: String?, created_at: Double, from_avatar_url: String? = nil) {
        self.id = id; self.kind = kind; self.from_handle = from_handle; self.from_name = from_name
        self.from_avatar_url = from_avatar_url
        self.group_id = group_id; self.group_name = group_name; self.created_at = created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "voice"
        from_handle = (try? c.decode(String.self, forKey: .from_handle)) ?? ""
        let name = (try? c.decode(String.self, forKey: .from_name)) ?? ""
        from_name = name.isEmpty ? (from_handle.isEmpty ? "Someone" : "@\(from_handle)") : name
        from_avatar_url = (try? c.decodeIfPresent(String.self, forKey: .from_avatar_url))
            ?? (try? c.decodeIfPresent(String.self, forKey: .avatar_url))
        group_id = try? c.decodeIfPresent(String.self, forKey: .group_id)
        group_name = try? c.decodeIfPresent(String.self, forKey: .group_name)
        created_at = (try? c.decode(Double.self, forKey: .created_at)) ?? Date().timeIntervalSince1970 * 1000
    }

    enum CodingKeys: String, CodingKey { case id, kind, from_handle, from_name, from_avatar_url, avatar_url, group_id, group_name, created_at }
}

@MainActor
extension BlindbanditAPI {
    /// Contract: GET /v1/social/directory?cursor=&q=. Falls back to /v1/social/search on older servers.
    static func directory(query: String, cursor: String?) async throws -> (people: [BlindbanditPerson], next: String?) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var path = "v1/social/directory?q=\(escape(q))"
            if let cursor, !cursor.isEmpty { path += "&cursor=\(escape(cursor))" }
            let page = try decode(DirectoryPage.self, from: try await request(path))
            return (page.items.filter { !$0.handle.isEmpty }, page.next_cursor)
        } catch let error as CommunicationsError where error.isMissingRoute {
            guard !q.isEmpty else { return ([], nil) }
            return (try await searchPeople(q), nil)
        }
    }

    struct DirectoryPage: Decodable { let items: [BlindbanditPerson]; let next_cursor: String? }

    static func searchPeople(_ query: String, limit: Int = 30) async throws -> [BlindbanditPerson] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try decode(ItemsPayload<BlindbanditPerson>.self, from: try await request("v1/social/search?q=\(escape(q))&limit=\(limit)")).items
            .filter { !$0.handle.isEmpty }
    }

    static func groups() async throws -> [BlindbanditGroup] {
        try decode(ItemsPayload<BlindbanditGroup>.self, from: try await request("v1/social/groups?limit=100")).items
    }

    static func createGroup(name: String, handles: [String]) async throws -> BlindbanditGroup {
        try decode(BlindbanditGroup.self, from: try await request(
            "v1/social/groups", method: "POST", body: ["name": name, "member_handles": handles, "handles": handles]
        ))
    }

    static func groupDetail(id: String) async throws -> BlindbanditGroupDetail {
        try decode(BlindbanditGroupDetail.self, from: try await request("v1/social/groups/\(escape(id))"))
    }

    static func renameGroup(id: String, name: String) async throws {
        try await request("v1/social/groups/\(escape(id))", method: "PATCH", body: ["name": name])
    }

    static func addGroupMembers(id: String, handles: [String]) async throws {
        try await request("v1/social/groups/\(escape(id))/members", method: "POST", body: ["handles": handles])
    }

    static func removeGroupMember(id: String, handle: String) async throws {
        try await request("v1/social/groups/\(escape(id))/members/\(escape(handle))", method: "DELETE")
    }

    /// Addendum route (site-ai-prompt-190-addendum.md).
    static func setGroupRole(id: String, handle: String, role: String) async throws {
        try await request("v1/social/groups/\(escape(id))/members/\(escape(handle))", method: "PATCH", body: ["role": role])
    }

    /// Contract: leaving is DELETE /groups/{id}/members/{my handle}.
    static func leaveGroup(id: String, myHandle: String) async throws {
        try await request("v1/social/groups/\(escape(id))/members/\(escape(myHandle))", method: "DELETE")
    }

    /// Addendum route (site-ai-prompt-190-addendum.md). Admins only.
    static func deleteGroup(id: String) async throws {
        try await request("v1/social/groups/\(escape(id))", method: "DELETE")
    }

    static func markGroupRead(id: String) async {
        _ = try? await request("v1/social/groups/\(escape(id))/read", method: "POST", body: [:])
    }

    /// Returns the handles currently typing in the group.
    static func sendGroupTyping(id: String) async -> [String] {
        guard let data = try? await request("v1/social/groups/\(escape(id))/typing", method: "POST", body: ["typing": true]),
              let payload = try? decode(TypingPayload.self, from: data) else { return [] }
        return payload.typing_handles ?? []
    }

    struct TypingPayload: Decodable { let typing_handles: [String]? }

    /// Who is typing in the group right now (GET; empty if the route isn't live).
    static func groupTyping(id: String) async -> [String] {
        guard let data = try? await request("v1/social/groups/\(escape(id))/typing"),
              let payload = try? decode(TypingPayload.self, from: data) else { return [] }
        return payload.typing_handles ?? []
    }

    static func groupMessages(id: String) async throws -> [BlindbanditGroupMessage] {
        try decode(ItemsPayload<BlindbanditGroupMessage>.self, from: try await request("v1/social/groups/\(escape(id))/messages?limit=100")).items
            .sorted { $0.created_at < $1.created_at }
            .resolvedE2EE(groupID: id)
    }

    static func sendGroupMessage(id: String, body: String, silent: Bool = false) async throws {
        let payload = E2EEPayload(t: "text", body: body, silent: silent ? true : nil)
        if try await E2EEService.shared.sendGroup(id: id, payload: payload) { return }
        var fields: [String: Any] = ["body": body]
        if silent { fields["silent"] = true }
        try await request("v1/social/groups/\(escape(id))/messages", method: "POST", body: fields)
    }

    /// Best-effort group reaction (404/405 → kept on device only).
    static func reactGroup(groupID: String, messageID: String, emoji: String?) async {
        var body: [String: Any] = [:]
        if let emoji { body["emoji"] = emoji } else { body["emoji"] = NSNull() }
        _ = try? await request("v1/social/groups/\(escape(groupID))/messages/\(escape(messageID))/reactions",
                               method: "POST", body: body)
    }

    /// Contract: POST /v1/social/calls {kind, group_id}.
    static func startGroupCall(groupID: String, video: Bool) async throws -> BlindbanditCallResponse {
        try decode(BlindbanditCallResponse.self, from: try await request(
            "v1/social/calls", method: "POST", body: ["kind": video ? "video" : "voice", "group_id": groupID]
        ))
    }

    /// Contract: GET /v1/social/calls/{id} → participants[] with state ringing|joined|left|declined.
    static func callDetail(id: String) async throws -> BlindbanditCallDetail {
        try decode(BlindbanditCallDetail.self, from: try await request("v1/social/calls/\(escape(id))"))
    }

    static func inviteToCall(id: String, handles: [String]) async throws {
        try await request("v1/social/calls/\(escape(id))/invite", method: "POST", body: ["handles": handles])
    }

    /// Addendum route: POST /v1/social/calls/{id}/remove {handle}. Admin/host only.
    static func removeFromCall(id: String, handle: String) async throws {
        try await request("v1/social/calls/\(escape(id))/remove", method: "POST", body: ["handle": handle])
    }

    /// Addendum route: POST /v1/social/messages/{conversation}/{message}/reactions {emoji|null}.
    /// Best effort: the reaction always stays on this phone.
    static func react(conversationID: String, messageID: String, emoji: String?) async {
        _ = try? await request("v1/social/messages/\(escape(conversationID))/\(escape(messageID))/reactions",
                               method: "POST", body: ["emoji": emoji.map { $0 as Any } ?? NSNull()])
    }

    /// POST /v1/social/messages/{conversation id}/unread.
    static func markConversationUnread(id: String) async throws {
        try await request("v1/social/messages/\(escape(id))/unread", method: "POST", body: [:])
    }

    static func declineCall(id: String) async {
        do {
            try await request("v1/social/calls/\(escape(id))/decline", method: "POST", body: [:])
        } catch {
            // Older servers have no decline route: ending the call stops the ring for the caller too.
            await endCall(id: id)
        }
    }

    /// Ringing calls addressed to me. Falls back to call history on servers without the route.
    static func incomingCalls() async throws -> [BlindbanditIncomingCall] {
        do {
            return try decode(ItemsPayload<BlindbanditIncomingCall>.self, from: try await request("v1/social/calls/incoming")).items
        } catch CommunicationsError.notFound(_) {
            // A 404 here means the route isn't live yet (or nothing is ringing): treat it as no incoming calls.
            let now = Date().timeIntervalSince1970 * 1000
            return ((try? await callHistory()) ?? [])
                .filter { $0.isIncoming && $0.status == "ringing" && now - $0.created_at < 45_000 }
                .map {
                    BlindbanditIncomingCall(
                        id: $0.id, kind: $0.kind, from_handle: $0.other?.handle ?? "",
                        from_name: $0.other?.display_name ?? ($0.other.map { "@\($0.handle)" } ?? "Someone"),
                        group_id: nil, group_name: nil, created_at: $0.created_at,
                        from_avatar_url: $0.other?.avatar_url
                    )
                }
        }
    }
}

struct BlindbanditCallDetail: Decodable {
    struct Participant: Decodable, Equatable {
        let handle: String
        let display_name: String
        let state: String
    }
    let participants: [Participant]
    let status: String?
    let group_id: String?
    let group_name: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        participants = (try? c.decode([Participant].self, forKey: .participants)) ?? []
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        group_id = try? c.decodeIfPresent(String.self, forKey: .group_id)
        group_name = try? c.decodeIfPresent(String.self, forKey: .group_name)
    }
    enum CodingKeys: String, CodingKey { case participants, status, group_id, group_name }
}


extension Array where Element == BlindbanditGroupMessage {
    @MainActor func resolvedE2EE(groupID: String) -> [BlindbanditGroupMessage] { E2EEService.shared.resolveGroup(self, groupID: groupID) }
}

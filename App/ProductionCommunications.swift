import Foundation
import SwiftUI
import UIKit
import AVFoundation
import LiveKit
import ClerkKit

// MARK: - API models (shapes match worker/platform/social.ts on api.mrblindbandit.net)

struct BlindbanditSocialProfile: Decodable {
    let id: String
    let handle: String
    let display_name: String
    /// Public HTTPS profile photo URL (not E2EE). Empty or nil = initials.
    var avatar_url: String? = nil
    /// Real API field: SQLite 1/0 or true/false.
    var verified: Bool? = nil

    init(id: String, handle: String, display_name: String, avatar_url: String? = nil, verified: Bool? = nil) {
        self.id = id; self.handle = handle; self.display_name = display_name
        self.avatar_url = avatar_url; self.verified = verified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        handle = try c.decode(String.self, forKey: .handle)
        display_name = (try? c.decode(String.self, forKey: .display_name)) ?? handle
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
        verified = FlexibleBool.decode(c, .verified)
    }
    enum CodingKeys: String, CodingKey { case id, handle, display_name, avatar_url, verified }
}

struct BlindbanditConversation: Identifiable, Decodable, Equatable {
    struct Other: Decodable, Equatable {
        let handle: String
        let display_name: String
        let avatar_url: String?
        /// The list endpoint returns SQLite 0/1 here while other endpoints return true/false.
        /// A strict `Bool?` made the whole inbox fail to decode, which hid every conversation.
        let verified: Bool?
        /// Dialer call number from slim inbox (`/v1/social/inbox`), when assigned.
        let call_number: String?

        init(handle: String, display_name: String, avatar_url: String?, verified: Bool?, call_number: String? = nil) {
            self.handle = handle; self.display_name = display_name; self.avatar_url = avatar_url
            self.verified = verified; self.call_number = call_number
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
            display_name = (try? c.decode(String.self, forKey: .display_name)) ?? handle
            avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
            verified = FlexibleBool.decode(c, .verified)
            call_number = try? c.decodeIfPresent(String.self, forKey: .call_number)
        }

        enum CodingKeys: String, CodingKey { case handle, display_name, avatar_url, verified, call_number }
    }
    struct LastMessage: Decodable, Equatable {
        let body: String
        let created_at: Double
        let sender_id: String

        /// Soft-decode: a null/missing body (or SQLite quirks) must not fail the whole inbox list.
        init(body: String, created_at: Double, sender_id: String) {
            self.body = body; self.created_at = created_at; self.sender_id = sender_id
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            body = (try? c.decode(String.self, forKey: .body)) ?? ""
            created_at = (try? c.decode(Double.self, forKey: .created_at))
                ?? (try? c.decode(Int.self, forKey: .created_at)).map(Double.init)
                ?? 0
            sender_id = (try? c.decode(String.self, forKey: .sender_id))
                ?? (try? c.decode(Int.self, forKey: .sender_id)).map(String.init)
                ?? ""
        }

        enum CodingKeys: String, CodingKey { case body, created_at, sender_id }
    }
    let id: String
    let updated_at: Double
    let other: Other?
    let last_message: LastMessage?
    /// From slim inbox; nil on classic list payloads.
    let unread_count: Int?

    /// Soft-decode: one bad/missing field must not blank the whole inbox list.
    init(id: String, updated_at: Double, other: Other?, last_message: LastMessage?, unread_count: Int? = nil) {
        self.id = id; self.updated_at = updated_at; self.other = other
        self.last_message = last_message; self.unread_count = unread_count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id))
            ?? (try? c.decode(Int.self, forKey: .id)).map(String.init)
            ?? ""
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "conversation id required")
        }
        updated_at = (try? c.decode(Double.self, forKey: .updated_at))
            ?? (try? c.decode(Int.self, forKey: .updated_at)).map(Double.init)
            ?? 0
        other = try? c.decode(Other.self, forKey: .other)
        last_message = try? c.decode(LastMessage.self, forKey: .last_message)
        unread_count = (try? c.decode(Int.self, forKey: .unread_count))
            ?? (try? c.decode(Double.self, forKey: .unread_count)).map { Int($0) }
    }

    enum CodingKeys: String, CodingKey { case id, updated_at, other, last_message, unread_count }
}

struct BlindbanditServerMessage: Identifiable, Decodable, Equatable {
    let id: String
    let sender_id: String
    /// Decrypted locally for E2EE rows (the server only ever has an empty body for those).
    var body: String
    let created_at: Double
    let read_at: Double?
    /// Present once the backend records delivery to the recipient's device. Until then "Delivered" is never shown.
    let delivered_at: Double?
    // E2EE 2.0 fields (all optional so older servers keep decoding).
    var e2ee: Bool = false
    var envelopeJSON: String?
    var kind: String = "text"
    var expires_at: Double?
    var view_once: Bool = false
    var opened_at: Double?
    var edited_at: Double?
    var client_msg_id: String?
    /// Filled in by E2EEService after decrypting.
    var decrypted: E2EEPayload?
    var decryptFailed = false

    init(id: String, sender_id: String, body: String, created_at: Double, read_at: Double? = nil, delivered_at: Double? = nil) {
        self.id = id; self.sender_id = sender_id; self.body = body; self.created_at = created_at
        self.read_at = read_at; self.delivered_at = delivered_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? (try? c.decode(Int.self, forKey: .id)).map(String.init) ?? UUID().uuidString
        sender_id = (try? c.decode(String.self, forKey: .sender_id)) ?? ""
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        created_at = (try? c.decode(Double.self, forKey: .created_at)) ?? 0
        read_at = try? c.decode(Double.self, forKey: .read_at)
        delivered_at = try? c.decode(Double.self, forKey: .delivered_at)
        e2ee = FlexibleBool.decode(c, .e2ee) ?? false
        if let s = try? c.decode(String.self, forKey: .envelope) {
            envelopeJSON = s
        } else if let env = try? c.decode(E2EEEnvelope.self, forKey: .envelope), let d = try? JSONEncoder().encode(env) {
            envelopeJSON = String(data: d, encoding: .utf8)
        }
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "text"
        expires_at = try? c.decode(Double.self, forKey: .expires_at)
        view_once = FlexibleBool.decode(c, .view_once) ?? false
        opened_at = try? c.decode(Double.self, forKey: .opened_at)
        edited_at = try? c.decode(Double.self, forKey: .edited_at)
        client_msg_id = try? c.decode(String.self, forKey: .client_msg_id)
    }

    var envelope: E2EEEnvelope? { envelopeJSON.flatMap { E2EEEnvelope.from(any: $0) } }
    var isSystem: Bool { kind == "system" }
    /// Prefer client_msg_id so optimistic local- rows and the server echo share one identity.
    var stableIdentity: String {
        if let c = client_msg_id, !c.isEmpty { return c }
        return id
    }

    enum CodingKeys: String, CodingKey {
        case id, sender_id, body, created_at, read_at, delivered_at, e2ee, envelope, kind, expires_at, view_once, opened_at, edited_at, client_msg_id
    }
}

struct BlindbanditLiveKitGrant: Decodable {
    let token: String
    let identity: String?
    let room: String
    let expires_at: Double?
    let url: String?
}

/// Accepts both the 1.8 shape `{id, room, kind, status, livekit:{token,url,…}}` and the 1.9 contract
/// shape `{call_id, room, livekit_url, token}`.
struct BlindbanditCallResponse: Decodable {
    let id: String
    let room: String
    let kind: String
    let status: String
    let livekit: BlindbanditLiveKitGrant

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(String.self, forKey: .id) { id = value } else { id = try c.decode(String.self, forKey: .call_id) }
        room = (try? c.decode(String.self, forKey: .room)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "voice"
        status = (try? c.decode(String.self, forKey: .status)) ?? "ringing"
        if let grant = try? c.decode(BlindbanditLiveKitGrant.self, forKey: .livekit) {
            livekit = grant
        } else {
            livekit = BlindbanditLiveKitGrant(
                token: try c.decode(String.self, forKey: .token),
                identity: nil, room: room, expires_at: nil,
                url: try? c.decodeIfPresent(String.self, forKey: .livekit_url)
            )
        }
    }

    enum CodingKeys: String, CodingKey { case id, call_id, room, kind, status, livekit, token, livekit_url }
}

struct BlindbanditMessageResponse: Decodable {
    let id: String
    let conversation_id: String
    let created_at: Double
}

struct BlindbanditCallNumberProfile: Decodable {
    let id: String?
    let handle: String
    let display_name: String
    let avatar_url: String?
    let verified: Bool?
    let call_number: String?
}

struct BlindbanditMyCallNumber: Decodable {
    let call_number: String?
    let handle: String?
    let id: String?
    let cleared: Bool?
}

enum FlexibleBool {
    /// Accepts true/false, 0/1 and "0"/"1"/"true"/"false" so a backend type change never blanks a screen.
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if let b = try? c.decode(Bool.self, forKey: key) { return b }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: key) { return ["1", "true", "yes"].contains(s.lowercased()) }
        return nil
    }
}

struct ItemsPayload<Item: Decodable>: Decodable { let items: [Item] }

struct BlindbanditThreadPayload: Decodable {
    var items: [BlindbanditServerMessage]
    let otherTyping: Bool

    init(items: [BlindbanditServerMessage], otherTyping: Bool) {
        self.items = items; self.otherTyping = otherTyping
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Prefer strict array; fall back to per-row so one bad message cannot blank the thread.
        if let all = try? c.decode([BlindbanditServerMessage].self, forKey: .items) {
            items = all
        } else {
            var arr = try c.nestedUnkeyedContainer(forKey: .items)
            var out: [BlindbanditServerMessage] = []
            while !arr.isAtEnd {
                if let m = try? arr.decode(BlindbanditServerMessage.self) {
                    out.append(m)
                } else {
                    // Advance past the bad element by decoding a generic JSON value.
                    _ = try? arr.decode(BlindbanditJSONSkip.self)
                }
            }
            items = out
        }
        otherTyping = FlexibleBool.decode(c, .other_typing) ?? false
    }

    enum CodingKeys: String, CodingKey { case items, other_typing }
}

/// Decodes (and discards) any JSON value so lossy array parsing can skip a bad row.
private struct BlindbanditJSONSkip: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { return }
        if (try? c.decode(Bool.self)) != nil { return }
        if (try? c.decode(Int.self)) != nil { return }
        if (try? c.decode(Double.self)) != nil { return }
        if (try? c.decode(String.self)) != nil { return }
        if (try? c.decode([BlindbanditJSONSkip].self)) != nil { return }
        if (try? c.decode([String: BlindbanditJSONSkip].self)) != nil { return }
    }
}

/// Every API response is wrapped as `{ "success": true, "data": …, "meta": … }`.
struct BlindbanditEnvelope<Payload: Decodable>: Decodable { let data: Payload }

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String?; let message: String? }
    let error: Detail?
}

enum ReportReason: String, CaseIterable, Identifiable {
    case harassment = "Harassment or bullying"
    case spam = "Spam or scam"
    case hate = "Hate speech"
    case sexual = "Sexual or explicit content"
    case violence = "Threats or violence"
    case impersonation = "Impersonation"
    case other = "Something else"
    var id: String { rawValue }
}

enum BlindbanditHandle {
    /// Usernames are lowercase letters, numbers and underscores. People often type a leading @.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasPrefix("@") { value.removeFirst() }
        return value
    }
}

/// Friendly copy for transient network failures — never show raw "The request timed out." full-screen.
enum CommsNetwork {
    static func friendly(_ error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .cancelled:
                return "Still connecting…"
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Showing saved chats when available."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Can't reach Blindbandit. Retrying…"
            default:
                break
            }
        }
        if error is DecodingError { return "Updating chats…" }
        if let auth = error as? AuthServiceError { return auth.errorDescription ?? "Signing in…" }
        return "Still connecting…"
    }

    static func isTransient(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [
                .timedOut, .cancelled, .notConnectedToInternet, .networkConnectionLost,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed
            ].contains(url.code)
        }
        if error is DecodingError { return true }
        if case AuthServiceError.noActiveSession = error { return true }
        if case AuthServiceError.sdkNotReady = error { return true }
        return false
    }
}

@MainActor
enum BlindbanditAPI {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(BlindbanditEnvelope<T>.self, from: data).data
    }

    /// Decode envelope `items` one-by-one so a single bad row cannot blank the inbox/thread.
    static func softDecodeItems<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        if let items = try? decode(ItemsPayload<T>.self, from: data).items { return items }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommunicationsError.invalidResponse
        }
        let payload = (root["data"] as? [String: Any]) ?? root
        let raw = (payload["items"] as? [Any]) ?? []
        var out: [T] = []
        for item in raw {
            guard JSONSerialization.isValidJSONObject(item),
                  let d = try? JSONSerialization.data(withJSONObject: item),
                  let decoded = try? JSONDecoder().decode(T.self, from: d) else { continue }
            out.append(decoded)
        }
        if out.isEmpty, !raw.isEmpty {
            // Surface the original decode error rather than silently empty.
            return try decode(ItemsPayload<T>.self, from: data).items
        }
        return out
    }

    private static func url(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pieces = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(url: AppConfig.apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/" + String(pieces[0])
        if pieces.count > 1 { components.percentEncodedQuery = String(pieces[1]) }
        return components.url!
    }

    /// Absolute URL from a server string: full https, or path relative to apiBaseURL.
    static func resolveURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" || scheme == "file" {
            return u
        }
        // "//cdn..." protocol-relative
        if s.hasPrefix("//"), let u = URL(string: "https:" + s) { return u }
        let path = s.hasPrefix("/") ? String(s.dropFirst()) : s
        return url(path)
    }

    /// GET an arbitrary https URL with the same Bearer + device headers as BlindbanditAPI.request.
    /// Used for attachment downloads that are not fully public/presigned.
    static func authenticatedData(from absolute: URL) async throws -> Data {
        if StoreScreenshotMode.isActive { throw AuthServiceError.noActiveSession }
        guard let token = await clerkTokenWithTimeout() else { throw AuthServiceError.noActiveSession }
        var request = URLRequest(url: absolute)
        request.httpMethod = "GET"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let device = IdentityStore.shared.deviceID { request.setValue(device, forHTTPHeaderField: "X-BB-Device-Id") }
        request.setValue(Self.installationID, forHTTPHeaderField: "X-Installation-ID")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunicationsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw CommunicationsError.notFound("attachment download") }
            throw CommunicationsError.server("Attachment download failed (HTTP \(http.statusCode)).")
        }
        return data
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? value
    }

    @discardableResult
    static func request(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        timeout: TimeInterval = 12
    ) async throws -> Data {
        // Store screenshot mode never configures Clerk, so never touch Clerk.shared there.
        if StoreScreenshotMode.isActive { throw AuthServiceError.noActiveSession }
        guard let token = await clerkTokenWithTimeout() else {
            throw AuthServiceError.noActiveSession
        }
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let device = IdentityStore.shared.deviceID { request.setValue(device, forHTTPHeaderField: "X-BB-Device-Id") }
        request.setValue(Self.installationID, forHTTPHeaderField: "X-Installation-ID")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunicationsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            if http.statusCode == 404 {
                throw CommunicationsError.notFound(envelope?.error?.message ?? "")
            }
            throw CommunicationsError.server(envelope?.error?.message ?? "The Blindbandit server returned an error (HTTP \(http.statusCode)).")
        }
        return data
    }

    static func currentProfile() async throws -> BlindbanditSocialProfile {
        try decode(BlindbanditSocialProfile.self, from: try await request("v1/social/me"))
    }

    /// PATCH /v1/social/me — public profile fields including avatar_url (absolute HTTPS).
    @discardableResult
    static func updateSocialProfile(_ fields: [String: Any]) async throws -> BlindbanditSocialProfile {
        try decode(BlindbanditSocialProfile.self, from: try await request("v1/social/me", method: "PATCH", body: fields))
    }

    /// PUT /v1/social/me/avatar — raw JPEG body; server stores a public object and sets avatar_url.
    static func uploadPublicAvatar(jpeg: Data) async throws -> String {
        if StoreScreenshotMode.isActive { throw AuthServiceError.noActiveSession }
        guard let token = await clerkTokenWithTimeout() else { throw AuthServiceError.noActiveSession }
        var request = URLRequest(url: url("v1/social/me/avatar"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("\(jpeg.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let device = IdentityStore.shared.deviceID { request.setValue(device, forHTTPHeaderField: "X-BB-Device-Id") }
        request.setValue(Self.installationID, forHTTPHeaderField: "X-Installation-ID")
        request.httpBody = jpeg
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunicationsError.invalidResponse }
        if http.statusCode == 404 {
            throw CommunicationsError.server("Profile photo upload is not available on the server yet. Try again after the next Blindbandit update.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw CommunicationsError.server(envelope?.error?.message ?? "Could not upload profile picture (HTTP \(http.statusCode)).")
        }
        let profile = try decode(BlindbanditSocialProfile.self, from: data)
        let trimmed = profile.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw CommunicationsError.server("Upload succeeded but no public avatar URL was returned.")
        }
        return trimmed
    }

    static func clearPublicAvatar() async throws {
        _ = try await updateSocialProfile(["avatar_url": ""])
    }

    static func conversations() async throws -> [BlindbanditConversation] {
        // Prefer slim inbox (Sites native-speed batch bb031a35). Fall back to classic list on 404.
        do {
            let d = try await request("v1/social/inbox?limit=100", timeout: 12)
            let items = try softDecodeItems(BlindbanditConversation.self, from: d)
            await ChatCache.saveList(d)
            return items
        } catch let error as CommunicationsError {
            switch error {
            case .notFound:
                break
            default:
                if !error.isMissingRoute { throw error }
            }
            let d = try await request("v1/social/messages?limit=100", timeout: 20)
            let items = try softDecodeItems(BlindbanditConversation.self, from: d)
            await ChatCache.saveList(d)
            return items
        }
    }

    static func messages(conversationID: String) async throws -> [BlindbanditServerMessage] {
        try await thread(conversationID: conversationID).items
    }

    /// The thread payload also carries `other_typing` (set for six seconds after the other person types).
    static func thread(conversationID: String) async throws -> BlindbanditThreadPayload {
        let d = try await request("v1/social/messages/\(escape(conversationID))?limit=100", timeout: 20)
        var payload: BlindbanditThreadPayload
        if let decoded = try? decode(BlindbanditThreadPayload.self, from: d) {
            payload = decoded
        } else {
            let items = try softDecodeItems(BlindbanditServerMessage.self, from: d)
            let typing: Bool = {
                guard let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let data = root["data"] as? [String: Any] else { return false }
                if let b = data["other_typing"] as? Bool { return b }
                if let i = data["other_typing"] as? Int { return i != 0 }
                return false
            }()
            payload = BlindbanditThreadPayload(items: items, otherTyping: typing)
        }
        payload.items = await E2EEService.shared.resolve(payload.items, conversationID: conversationID)
        return payload
    }

    static func sendTyping(conversationID: String) async {
        let allow = UserDefaults.standard.object(forKey: SettingsKey.sendTypingIndicators) as? Bool ?? true
        guard allow else { return }
        _ = try? await request("v1/social/messages/\(escape(conversationID))/typing", method: "POST", body: ["typing": true])
    }

    static func sendMessage(handle: String, body: String, silent: Bool = false, clientMsgID: String? = nil) async throws -> BlindbanditMessageResponse {
        // Race E2EE (includes key fetch) ≤350ms; soft-missing bundles/me must not feel like multi-second lag.
        let e2ee: BlindbanditMessageResponse? = await withHardTimeout(seconds: 0.35) {
            try await E2EEService.shared.sendDM(handle: handle, payload: E2EEPayload(t: "text", body: body, silent: silent ? true : nil))
        } ?? nil
        if let sent = e2ee { return sent }
        var fields: [String: Any] = ["handle": handle, "body": body]
        if silent { fields["silent"] = true }
        if let clientMsgID, !clientMsgID.isEmpty { fields["client_msg_id"] = clientMsgID }
        return try decode(BlindbanditMessageResponse.self, from: try await request(
            "v1/social/messages", method: "POST", body: fields, timeout: 8
        ))
    }

    /// Fast send ack by client_msg_id (native-speed) — no thread refetch.
    static func sendAck(conversationID: String, clientMsgID: String) async throws -> Bool {
        let d = try await request(
            "v1/social/messages/send-ack", method: "POST",
            body: ["conversation_id": conversationID, "client_msg_id": clientMsgID],
            timeout: 6
        )
        guard let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        let data = (root["data"] as? [String: Any]) ?? root
        return data["acked"] as? Bool ?? false
    }

    /// Prefetch many threads in one round-trip.
    static func hydrateThreads(ids: [String], limitPer: Int = 30) async {
        let slice = Array(ids.prefix(20))
        guard !slice.isEmpty else { return }
        guard let d = try? await request(
            "v1/social/inbox/hydrate", method: "POST",
            body: ["conversation_ids": slice, "limit_per": limitPer],
            timeout: 15
        ) else { return }
        guard let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        let data = (root["data"] as? [String: Any]) ?? root
        guard let threads = data["threads"] as? [[String: Any]] else { return }
        for thr in threads {
            guard let id = thr["id"] as? String,
                  let itemsRaw = thr["items"] as? [Any],
                  JSONSerialization.isValidJSONObject(itemsRaw),
                  let itemData = try? JSONSerialization.data(withJSONObject: ["data": ["items": itemsRaw]]),
                  let items = try? softDecodeItems(BlindbanditServerMessage.self, from: itemData),
                  !items.isEmpty else { continue }
            let resolved = await E2EEService.shared.resolve(items, conversationID: id)
            ChatCache.put(id, resolved.sorted { $0.created_at < $1.created_at })
        }
    }

    static func resolveCallNumber(_ number: String) async throws -> (handle: String, displayName: String, callNumber: String) {
        let digits = number.filter(\.isNumber)
        let d = try await request("v1/social/call-numbers/\(escape(digits))", timeout: 6)
        let profile = try decode(BlindbanditCallNumberProfile.self, from: d)
        return (profile.handle, profile.display_name, profile.call_number ?? digits)
    }

    static func getMyCallNumber() async throws -> String? {
        let d = try await request("v1/social/me/call-number", timeout: 6)
        let row = try decode(BlindbanditMyCallNumber.self, from: d)
        return row.call_number
    }

    static func setMyCallNumber(_ number: String?) async throws -> String? {
        var body: [String: Any] = [:]
        if let number, !number.isEmpty {
            body["call_number"] = number
        } else {
            body["call_number"] = NSNull()
        }
        let d = try await request("v1/social/me/call-number", method: "PUT", body: body, timeout: 8)
        let row = try decode(BlindbanditMyCallNumber.self, from: d)
        return row.call_number
    }

    static func presenceBatch(handles: [String]) async throws -> [String: Bool] {
        let slice = Array(Set(handles.map { $0.lowercased() })).prefix(50)
        guard !slice.isEmpty else { return [:] }
        let d = try await request(
            "v1/social/presence/batch", method: "POST",
            body: ["handles": Array(slice)], timeout: 8
        )
        guard let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        let data = (root["data"] as? [String: Any]) ?? root
        guard let items = data["items"] as? [[String: Any]] else { return [:] }
        var out: [String: Bool] = [:]
        for item in items {
            guard let h = item["handle"] as? String else { continue }
            let online = (item["online"] as? Bool) ?? ((item["online"] as? Int).map { $0 != 0 } ?? false)
            out[h.lowercased()] = online
        }
        return out
    }

    static func readBatch(conversationIDs: [String]) async {
        let slice = Array(Set(conversationIDs)).prefix(50)
        guard !slice.isEmpty else { return }
        _ = try? await request(
            "v1/social/messages/read-batch", method: "POST",
            body: ["conversation_ids": Array(slice)], timeout: 8
        )
    }

    static func startCall(handle: String, video: Bool) async throws -> BlindbanditCallResponse {
        try decode(BlindbanditCallResponse.self, from: try await request(
            "v1/social/calls", method: "POST", body: ["handle": handle, "to_handle": handle, "kind": video ? "video" : "voice"]
        ))
    }

    static func joinCall(id: String) async throws -> BlindbanditCallResponse {
        try decode(BlindbanditCallResponse.self, from: try await request(
            "v1/social/calls/\(escape(id))/join", method: "POST",
            body: ["installation_id": Self.installationID]
        ))
    }

    static func endCall(id: String) async {
        await EndedCalls.endReliably(id)
    }

    /// One /end attempt. 404/409/410 mean the server already considers it over: success.
    static func endCallChecked(id: String) async -> Bool {
        do { _ = try await request("v1/social/calls/\(escape(id))/end", method: "POST",
                                   body: ["installation_id": Self.installationID]); return true }
        catch {
            let text = "\(error)"
            return text.contains("404") || text.contains("409") || text.contains("410")
        }
    }

    static func markRead(conversationID: String) async throws {
        let allow = UserDefaults.standard.object(forKey: SettingsKey.sendReadReceipts) as? Bool ?? true
        guard allow else { return }

        try await request("v1/social/messages/\(escape(conversationID))/read", method: "POST", body: [:])
    }

    static func callHistory() async throws -> [BlindbanditCallRecord] {
        try decode(ItemsPayload<BlindbanditCallRecord>.self, from: try await request("v1/social/calls/history?limit=50")).items
    }

    static func blockedProfiles() async throws -> [BlindbanditBlockedProfile] {
        try decode(ItemsPayload<BlindbanditBlockedProfile>.self, from: try await request("v1/social/blocks")).items
    }

    static func unblock(handle: String) async throws {
        try await request("v1/social/profiles/\(escape(handle))/block", method: "DELETE")
    }

    static func socialNotifications() async throws -> [BlindbanditSocialNotification] {
        try decode(ItemsPayload<BlindbanditSocialNotification>.self, from: try await request("v1/social/notifications?limit=50")).items
    }

    static func markSocialNotificationsRead() async throws {
        try await request("v1/social/notifications/read", method: "POST", body: [:])
    }

    static func profileExists(handle: String) async -> Bool? {
        do {
            _ = try await request("v1/social/profiles/\(escape(handle))")
            return true
        } catch CommunicationsError.server(_) {
            return false
        } catch CommunicationsError.notFound(_) {
            return false
        } catch {
            return nil
        }
    }

    static func block(handle: String) async throws {
        try await request("v1/social/profiles/\(escape(handle))/block", method: "POST", body: [:])
    }

    static func report(targetType: String, targetID: String, reason: String, details: String) async throws {
        var body: [String: Any] = ["target_type": targetType, "target_id": targetID, "reason": String(reason.prefix(200))]
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["details"] = String(trimmed.prefix(2000)) }
        try await request("v1/social/reports", method: "POST", body: body)
    }

    static func requestAccountDataDeletion() async throws {
        try await request("v1/privacy/delete", method: "POST", body: [:])
    }

    /// Stable per-install id (UserDefaults). Sent on join/end so the server can exclude this device
    /// from "answered elsewhere" / hang-up echo pushes (see /workspace/e2ee/tyrese-call-fix.md).
    static var installationID: String {
        let key = "blindbandit.installationID"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }

    /// Registers the APNs alert token and, when PushKit has issued one, the VoIP token used for
    /// CallKit incoming calls (APNs topic net.mrblindbandit.app.voip, push type voip).
    static func registerPushToken(_ token: String) async throws {
        let voip = UserDefaults.standard.string(forKey: CallKitManager.voipTokenKey) ?? ""
        guard !token.isEmpty || !voip.isEmpty else { return }
        let installationID = Self.installationID
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppConfig.marketingVersion
        try await request(
            "v1/social/devices/register",
            method: "POST",
            body: [
                "installation_id": installationID,
                "platform": "ios",
                "token": token,
                "voip_token": voip,
                "apns_voip_topic": (Bundle.main.bundleIdentifier ?? "net.mrblindbandit.app") + ".voip",
                "supports_callkit": true,
                "app_version": version,
                "language": Locale.current.language.languageCode?.identifier ?? "en"
            ]
        )
    }
}

enum CommunicationsError: LocalizedError {
    case invalidResponse
    case server(String)
    case liveKitURLMissing
    /// HTTP 404. Either the item is gone or this server build does not have the route yet.
    case notFound(String)

    /// True when a 404 most likely means the route is missing on the server rather than a missing item.
    var isMissingRoute: Bool {
        guard case .notFound(let message) = self else { return false }
        let m = message.lowercased()
        return m.isEmpty || m.contains("route") || m == "not found" || m.contains("no handler") || m.contains("unknown endpoint")
            || m.contains("device not found") || m.contains("device_not_found") || m.contains("e2ee device")
    }

    static let serverUpdateMessage = "This feature needs a Blindbandit server update that isn't live yet. Everything else keeps working. Please try again after the next server update."

    var errorDescription: String? {
        switch self {
        case .notFound(let message):
            return isMissingRoute ? Self.serverUpdateMessage : message
        case .invalidResponse: return "The Blindbandit server sent a response the app could not read."
        case .server(let message): return message
        case .liveKitURLMissing: return "The call server is unavailable right now. Please try again shortly."
        }
    }
}

// MARK: - Service (one instance for the whole app so an active call survives navigation)

@MainActor
final class ProductionCommunicationsService: ObservableObject {
    @Published private(set) var conversations: [BlindbanditConversation] = []
    @Published private(set) var messages: [BlindbanditServerMessage] = []
    @Published private(set) var myProfileID = ""
    @Published private(set) var myVerified = false
    @Published private(set) var myHandle = ""
    @Published private(set) var myDisplayName = ""
    /// Public HTTPS avatar URL from /v1/social/me (not E2EE).
    @Published private(set) var myAvatarURL: String? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var isInCall = false
    /// Full-screen call UI collapsed — LiveKit/CallKit keep running; mini pill stays on tabs.
    @Published var callUIMinimized = false
    @Published private(set) var isVideoCall = false
    @Published private(set) var micEnabled = true
    @Published private(set) var cameraEnabled = false
    @Published private(set) var callSeconds = 0
    @Published private(set) var activeCallID: String?
    @Published private(set) var callPeerName = ""
    @Published private(set) var localVideoTrack: VideoTrack?
    @Published private(set) var remoteVideoTrack: VideoTrack?
    @Published var statusMessage = ""
    @Published private(set) var loadError = ""
    /// Inline reconnect copy — never drives the full-screen CommsErrorView.
    @Published private(set) var softBanner = ""
    @Published private(set) var callHistory: [BlindbanditCallRecord] = []
    @Published private(set) var historyError = ""
    @Published private(set) var blockedProfiles: [BlindbanditBlockedProfile] = []
    @Published private(set) var isRinging = false
    @Published private(set) var speakerOn = false
    @Published private(set) var openConversationID: String?
    @Published private(set) var lastReadStamp: [String: Double] = LocalComms.lastRead
    @Published private(set) var pendingMessages: [PendingMessage] = LocalComms.pending
    @Published private(set) var otherTyping = false

    // Calls (1:1 and group)
    @Published private(set) var participants: [CallParticipantInfo] = []
    @Published private(set) var activeSpeakerID: String?
    @Published private(set) var callGroupID: String?
    @Published private(set) var callGroupName: String?
    @Published private(set) var screenSharing = false
    /// VoiceOver-readable call encryption state shown on the call screen.
    @Published private(set) var callEncryptionLabel = ""
    @Published private(set) var callEncrypted = false
    private var callKeyProvider: BaseKeyProvider?
    private var callKeyIndex = 0
    private var callKeyIsMine = false
    private var callKeyPeerHandle: String?
    private var callKeyPoll: Task<Void, Never>?
    @Published private(set) var usingFrontCamera = true
    @Published private(set) var handRaised = false
    @Published private(set) var raisedHands: Set<String> = []
    @Published private(set) var callChat: [InCallChatMessage] = []
    @Published var unreadCallChat = 0
    @Published private(set) var isOnHold = false
    @Published private(set) var incomingCall: BlindbanditIncomingCall?
    @Published private(set) var missedGroupCalls: [BlindbanditIncomingCall] = []
    @Published private(set) var localQuality: ConnectionQuality = .unknown

    private var room: Room?
    private var pollTimer: Timer?
    private var ringTimeout: Task<Void, Never>?
    /// The outgoing call is marked missed by the server after a short wait; we stop ringing at 45 seconds
    /// and always send end so the call never stays stuck as ringing.
    static let ringTimeoutSeconds: UInt64 = 45
    private var ticker: Timer?
    private var bootstrapped = false
    private var softRetryTask: Task<Void, Never>?
    private var softRetryAttempt = 0
    private var threadSoftRetryTask: Task<Void, Never>?

    var callTimeLabel: String {
        String(format: "%02d:%02d", callSeconds / 60, callSeconds % 60)
    }

    func applyMyAvatarURL(_ url: String?) {
        let t = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        myAvatarURL = t.isEmpty ? nil : t
    }

    func applyMyDisplayName(_ name: String) {
        myDisplayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bootstrap(force: Bool = false) async {
        guard force || !bootstrapped else { return }
        isLoading = true
        defer { isLoading = false }
        // Instant inbox: render on-device cache before any network so a slow/transient failure never shows "Couldn't load".
        loadCachedConversations()
        if !conversations.isEmpty {
            loadError = ""
            softBanner = ""
        }

        // Parallel: /me must never block the inbox. Profile failure keeps cached chats visible.
        async let profileOutcome: Result<BlindbanditSocialProfile, Error> = {
            do { return .success(try await BlindbanditAPI.currentProfile()) }
            catch { return .failure(error) }
        }()
        async let inboxOutcome: Result<[BlindbanditConversation], Error> = {
            do { return .success(try await BlindbanditAPI.conversations()) }
            catch {
                try? await Task.sleep(nanoseconds: 400_000_000)
                do { return .success(try await BlindbanditAPI.conversations()) }
                catch { return .failure(error) }
            }
        }()

        let profile = await profileOutcome
        let inbox = await inboxOutcome

        if case .success(let p) = profile {
            myProfileID = p.id
            myHandle = p.handle
            myDisplayName = p.display_name
            myAvatarURL = {
                let t = p.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return t.isEmpty ? nil : t
            }()
            UserDefaults.standard.set(p.id, forKey: CallKitManager.myIDKey)
            UserDefaults.standard.set(p.handle, forKey: CallKitManager.myHandleKey)
            AIPersona.serverHandle = p.handle
            myVerified = p.verified == true
            E2EEService.shared.myUserID = p.id
            Task { await HistoryBackup.restoreIfNeeded(); await AIChatBackup.restoreIfNeeded() }
            Task { await E2EEService.shared.bootstrap(handle: p.handle) }
        }

        bootstrapped = true
        startPolling()

        switch inbox {
        case .success(let items):
            announceNewIncoming(old: conversations, new: items)
            conversations = items
            loadError = ""
            softBanner = ""
            softRetryAttempt = 0
            softRetryTask?.cancel()
            softRetryTask = nil
            statusMessage = ""
            prefetchThreads()
            await flushPendingMessages()
        case .failure(let error):
            // Never leave the owner on full-screen "The request timed out." Keep cache; soft-retry.
            loadError = ""
            if conversations.isEmpty {
                softBanner = CommsNetwork.friendly(error)
                statusMessage = softBanner
            } else {
                softBanner = ""
            }
            scheduleSoftRetry()
            // If /me failed too, still retry — inbox soft-retry refreshes both.
            if case .failure = profile { /* covered by scheduleSoftRetry */ }
        }
    }

    private func scheduleSoftRetry() {
        softRetryTask?.cancel()
        softRetryAttempt += 1
        let exp = min(softRetryAttempt, 5)
        let delay = min(30.0, pow(2.0, Double(exp))) // 2,4,8,16,32 → cap 30
        softRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.bootstrap(force: true)
        }
    }

    /// Renders the inbox instantly from the on-device cache, then refreshes from the server.
    func loadCachedConversations() {
        guard conversations.isEmpty, let d = ChatCache.loadList() else { return }
        if let items = try? BlindbanditAPI.softDecodeItems(BlindbanditConversation.self, from: d), !items.isEmpty {
            conversations = items
            return
        }
        if let items = try? BlindbanditAPI.decode(ItemsPayload<BlindbanditConversation>.self, from: d).items, !items.isEmpty {
            conversations = items
        }
    }

    private var prefetched = false
    /// Prefetches top chats via native-speed hydrate (one round-trip) with classic fallback.
    private func prefetchThreads() {
        guard !prefetched else { return }
        prefetched = true
        let ids = conversations.prefix(8).map(\.id)
        Task { [weak self] in
            await BlindbanditAPI.hydrateThreads(ids: ids, limitPer: 40)
            for id in ids where ChatCache.get(id) == nil {
                if let p = try? await BlindbanditAPI.thread(conversationID: id) {
                    ChatCache.put(id, p.items.sorted { $0.created_at < $1.created_at })
                }
            }
            _ = self
        }
    }

    func refreshConversations() async {
        loadCachedConversations()
        do {
            let fresh = try await BlindbanditAPI.conversations()
            announceNewIncoming(old: conversations, new: fresh)
            conversations = fresh
            prefetchThreads()
            loadError = ""
            softBanner = ""
            softRetryAttempt = 0
            softRetryTask?.cancel()
            softRetryTask = nil
        } catch {
            loadError = ""
            if conversations.isEmpty {
                softBanner = CommsNetwork.friendly(error)
                scheduleSoftRetry()
            }
        }
    }

    // MARK: Unread state (stored on this iPhone; the server records read_at when a thread is opened)

    func isUnread(_ conversation: BlindbanditConversation) -> Bool {
        guard let last = conversation.last_message, last.sender_id != myProfileID, !myProfileID.isEmpty else { return false }
        return last.created_at > (lastReadStamp[conversation.id] ?? 0)
    }

    var unreadCount: Int {
        let n = conversations.filter { isUnread($0) && !LocalComms.muted.contains($0.id) }.count
        FeatureBehaviors220.publishConversationBadge(unread: n)
        return n
    }

    private func markLocallyRead(_ conversation: BlindbanditConversation) {
        let stamp = max(conversation.last_message?.created_at ?? 0, messages.last?.created_at ?? 0)
        guard stamp > (lastReadStamp[conversation.id] ?? 0) else { return }
        lastReadStamp[conversation.id] = stamp
        LocalComms.lastRead = lastReadStamp
    }

    func markUnread(_ conversation: BlindbanditConversation) {
        lastReadStamp[conversation.id] = 0
        LocalComms.lastRead = lastReadStamp
        let id = conversation.id
        Task { try? await BlindbanditAPI.markConversationUnread(id: id) }
    }

    private func announceNewIncoming(old: [BlindbanditConversation], new: [BlindbanditConversation]) {
        guard !old.isEmpty else { return }
        for conversation in new where isUnread(conversation) && conversation.id != openConversationID {
            let before = old.first { $0.id == conversation.id }?.last_message?.created_at ?? 0
            if (conversation.last_message?.created_at ?? 0) > before, !LocalComms.muted.contains(conversation.id) {
                CallSounds.inboundNotification()
                AppHaptics.light()
                let who = conversation.other.map { "@\($0.handle)" } ?? "someone"
                UIAccessibility.post(notification: .announcement, argument: "New message from \(who)")
            }
        }
    }

    func openConversation(_ conversation: BlindbanditConversation) async {
        openConversationID = conversation.id
        let handle = conversation.other?.handle ?? ""
        let title: String = {
            guard let other = conversation.other else { return "Chat" }
            if !other.display_name.isEmpty { return other.display_name }
            return "@\(other.handle)"
        }()
        FeatureBehaviors220.onChatOpened(id: conversation.id, title: title, handle: handle)
        // Always paint cache first so a timeout never blanks an already-seen thread.
        if let cached = ChatCache.get(conversation.id), !cached.isEmpty {
            messages = cached
            loadError = ""
        }
        await reloadThread(conversation.id)
        markLocallyRead(conversation)
        try? await BlindbanditAPI.markRead(conversationID: conversation.id)
    }

    /// Opens a thread by id even when the inbox list hasn't caught up yet (e.g. from a notification).
    func openConversation(id: String) async {
        if let c = conversation(id: id) { await openConversation(c); return }
        openConversationID = id
        await reloadThread(id)
        await refreshConversations()
        if let c = conversation(id: id) { markLocallyRead(c) }
        try? await BlindbanditAPI.markRead(conversationID: id)
    }

    func closeConversation() {
        openConversationID = nil
        messages = []
        otherTyping = false
    }

    private var lastTypingSent = Date.distantPast

    /// Tells the server I'm typing, at most once every 3 seconds (the server keeps the flag for 6).
    func userTyped(in conversationID: String) {
        guard Date().timeIntervalSince(lastTypingSent) > 3 else { return }
        lastTypingSent = Date()
        Task { await BlindbanditAPI.sendTyping(conversationID: conversationID) }
    }

    private func reloadThread(_ id: String) async {
        if messages.isEmpty, let cached = ChatCache.get(id), !cached.isEmpty {
            messages = cached
            loadError = ""
        }
        do {
            let payload = try await BlindbanditAPI.thread(conversationID: id)
            let fresh = payload.items.sorted { $0.created_at < $1.created_at }
            guard openConversationID == id else { return }
            if payload.otherTyping != otherTyping {
                otherTyping = payload.otherTyping
                if payload.otherTyping {
                    let who = conversation(id: id)?.other.map { "@\($0.handle)" } ?? "The other person"
                    UIAccessibility.post(notification: .announcement, argument: "\(who) is typing")
                }
            }
            let hadIncoming = fresh.count > messages.count && fresh.last?.sender_id != myProfileID && !messages.isEmpty
            // Keep optimistic rows until the server echo arrives; match by client_msg_id or body so
            // ScrollView identity does not thrash (local- → server id was the jump).
            var consumedLocal = Set<String>()
            var merged = fresh.map { server -> BlindbanditServerMessage in
                var row = server
                if let match = messages.first(where: { local in
                    local.id.hasPrefix("local-")
                        && !consumedLocal.contains(local.id)
                        && local.sender_id == myProfileID
                        && (local.body == server.body
                            || (server.client_msg_id != nil && local.id == server.client_msg_id))
                }) {
                    consumedLocal.insert(match.id)
                    row = server
                    if row.client_msg_id == nil || row.client_msg_id?.isEmpty == true {
                        row.client_msg_id = match.client_msg_id ?? match.id
                    }
                }
                return row
            }
            let optimistic = messages.filter { m in m.id.hasPrefix("local-") && !consumedLocal.contains(m.id)
                && !fresh.contains(where: { f in f.sender_id == myProfileID && f.body == m.body }) }
            merged += optimistic
            if merged != messages { messages = merged }
            ChatCache.put(id, fresh)
            if hadIncoming, let current = self.conversation(id: id) {
                CallSounds.inboundNotification()
                markLocallyRead(current)
                try? await BlindbanditAPI.markRead(conversationID: id)
            }
            loadError = ""
            softBanner = ""
            threadSoftRetryTask?.cancel()
            threadSoftRetryTask = nil
        } catch {
            // Keep cached/optimistic rows. Never wipe; never full-screen timeout on empty thread.
            loadError = ""
            if messages.isEmpty {
                softBanner = CommsNetwork.friendly(error)
                threadSoftRetryTask?.cancel()
                threadSoftRetryTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    guard let self, self.openConversationID == id else { return }
                    await self.reloadThread(id)
                }
            }
        }
    }

    // MARK: Live updates (polling: the server has no socket or push channel for message events)

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, UIApplication.shared.applicationState == .active else { return }
                // Parallel: relay/E2EE must not serialize behind conversation refresh (PR #84 claimed this; ship it).
                async let conversations: Void = self.refreshConversations()
                async let relay: Void = E2EEService.shared.pollRelay()
                async let scheduled: Void = ScheduledSender.flushDue(self)
                async let incoming: Void = self.checkIncomingCalls()
                if let id = self.openConversationID {
                    async let thread: Void = self.reloadThread(id)
                    _ = await (conversations, relay, scheduled, thread, incoming)
                } else {
                    _ = await (conversations, relay, scheduled, incoming)
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Call history (GET /v1/social/calls/history)

    func refreshCallHistory() async {
        do {
            callHistory = try await BlindbanditAPI.callHistory()
            historyError = ""
        } catch {
            historyError = error.localizedDescription
        }
    }

    // MARK: Blocked accounts

    func refreshBlocked() async {
        do { blockedProfiles = try await BlindbanditAPI.blockedProfiles() }
        catch { statusMessage = error.localizedDescription }
    }

    func unblock(handle rawHandle: String) async -> Bool {
        let handle = BlindbanditHandle.normalize(rawHandle)
        do {
            try await BlindbanditAPI.unblock(handle: handle)
            statusMessage = "@\(handle) is unblocked."
            AppHaptics.success()
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            await refreshBlocked()
            return true
        } catch {
            statusMessage = error.localizedDescription
            AppHaptics.error()
            return false
        }
    }

    // MARK: Offline queue (messages typed with no connection are sent when the network returns)

    func flushPendingMessages() async {
        guard !pendingMessages.isEmpty else { return }
        for item in pendingMessages {
            do {
                _ = try await BlindbanditAPI.sendMessage(handle: item.handle, body: item.body)
                pendingMessages.removeAll { $0.id == item.id }
            } catch {
                break
            }
        }
        LocalComms.pending = pendingMessages
        await refreshConversations()
        if let id = openConversationID { await reloadThread(id) }
    }

    func discardPending(_ item: PendingMessage) {
        pendingMessages.removeAll { $0.id == item.id }
        LocalComms.pending = pendingMessages
    }

    func conversation(id: String) -> BlindbanditConversation? {
        conversations.first { $0.id == id }
    }

    func sendMessage(recipient: String, body: String, silent: Bool = false) async -> String? {
        let handle = BlindbanditHandle.normalize(recipient)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty, !text.isEmpty else {
            statusMessage = "Enter a Blindbandit username and a message."
            return nil
        }
        // Optimistic: bubble + "Sent" caption immediately; network runs after VO/haptics.
        let lid = "local-" + UUID().uuidString
        var localID: String?
        if let open = openConversationID, conversation(id: open)?.other?.handle.lowercased() == handle.lowercased() {
            var m = BlindbanditServerMessage(id: lid, sender_id: myProfileID, body: String(text.prefix(4000)),
                                             created_at: Date().timeIntervalSince1970 * 1000)
            m.client_msg_id = lid
            localID = lid
            messages.append(m)
        }
        AppHaptics.light()
        UIAccessibility.post(notification: .announcement, argument: "Sending")
        CallSounds.messageSent()
        UIAccessibility.post(notification: .announcement, argument: "Sent")
        statusMessage = "Message sent to @\(handle)."
        do {
            let response = try await BlindbanditAPI.sendMessage(
                handle: handle, body: String(text.prefix(4000)), silent: silent, clientMsgID: localID ?? lid
            )
            if let localID, let i = messages.firstIndex(where: { $0.id == localID }) {
                if messages.contains(where: { $0.id == response.id }) {
                    messages.remove(at: i)
                } else {
                    var real = BlindbanditServerMessage(
                        id: response.id, sender_id: messages[i].sender_id, body: messages[i].body,
                        created_at: response.created_at > 0 ? response.created_at : messages[i].created_at
                    )
                    real.client_msg_id = localID
                    messages[i] = real
                }
            }
            let convID = response.conversation_id
            let ackID = localID ?? lid
            Task { [weak self] in
                _ = try? await BlindbanditAPI.sendAck(conversationID: convID, clientMsgID: ackID)
                await self?.refreshConversations()
                if self?.openConversationID == convID { await self?.reloadThread(convID) }
            }
            return response.conversation_id
        } catch let error as URLError where [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            if let localID { messages.removeAll { $0.id == localID } }
            pendingMessages.append(PendingMessage(handle: handle, body: String(text.prefix(4000))))
            LocalComms.pending = pendingMessages
            statusMessage = "You're offline. The message to @\(handle) will send when you're back online."
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            AppHaptics.warning()
            return nil
        } catch {
            if let localID { messages.removeAll { $0.id == localID } }
            statusMessage = "Couldn't send: \(error.localizedDescription)"
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            AppHaptics.error()
            return nil
        }
    }


    func block(handle rawHandle: String) async -> Bool {
        let handle = BlindbanditHandle.normalize(rawHandle)
        guard !handle.isEmpty else { return false }
        do {
            try await BlindbanditAPI.block(handle: handle)
            statusMessage = "@\(handle) is blocked. They can no longer message or call you."
            AppHaptics.success()
            await refreshConversations()
            return true
        } catch {
            statusMessage = error.localizedDescription
            AppHaptics.error()
            return false
        }
    }

    func report(targetType: String, targetID: String, reason: ReportReason, details: String) async -> Bool {
        do {
            try await BlindbanditAPI.report(targetType: targetType, targetID: targetID, reason: reason.rawValue, details: details)
            statusMessage = "Thanks. Your report was sent to the Blindbandit moderation team."
            AppHaptics.success()
            return true
        } catch {
            statusMessage = error.localizedDescription
            AppHaptics.error()
            return false
        }
    }

    // MARK: - Calls (1:1 and group), driven through CallKit

    private var roomObserver: CallRoomObserver?
    private var knownParticipantIDs: Set<String> = []
    private var hadRemote = false
    private var aloneSince: Date?
    private var holdRestore: (mic: Bool, camera: Bool)?
    private var announcedIncoming: Set<String> = []
    private var callIsIncoming = false
    private(set) var joiningCallID: String?
    /// Wall-clock when this device successfully joined `activeCallID`. Used to ignore the server's
    /// "answered elsewhere" call_end echo that can still arrive after joiningCallID is cleared.
    private var joinedAt: [String: Date] = [:]

    func startCall(recipient: String, video: Bool) async {
        let handle = BlindbanditHandle.normalize(recipient)
        guard !handle.isEmpty else {
            statusMessage = "Enter the person's Blindbandit username first."
            AppHaptics.warning()
            return
        }
        // Real display name for CallKit / Recents / car displays, never an id.
        let known = conversations.first(where: { $0.other?.handle.lowercased() == handle.lowercased() })?.other?.display_name
        await placeCall(label: "@\(handle)", handle: handle, groupID: nil, groupName: nil, video: video, displayName: known)
        LocalComms.recordRecent(handle)
    }

    func startGroupCall(groupID: String, groupName: String, video: Bool, memberCount: Int? = nil) async {
        await placeCall(label: groupName, handle: nil, groupID: groupID, groupName: groupName, video: video, memberCount: memberCount)
    }

    private func placeCall(label: String, handle: String?, groupID: String?, groupName: String?, video: Bool, displayName: String? = nil, memberCount: Int? = nil) async {
        guard !isInCall, activeCallID == nil else {
            statusMessage = "You're already in a call."
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            return
        }
        // 2.0.6: show CallKit's outgoing UI instantly (before any network work) under a local ID,
        // then rebind it to the server call ID.
        CallWarmup.preconnect()
        CallTiming.start("outgoing call to \(label)")
        let localID = "local-" + UUID().uuidString
        CallKitManager.shared.startOutgoing(callID: localID, handle: handle ?? "", displayName: displayName ?? label, video: video, groupID: groupID, memberCount: memberCount)
        CallTiming.step("CallKit start requested")
        // Phase 1: US dial tone while dialing / connecting (before remote ring).
        CallSounds.callInitiated()
        statusMessage = "Calling \(label)…"
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
        callPeerName = label
        callGroupID = groupID
        callGroupName = groupName
        callIsIncoming = false
        CallTiming.step("dial tone started (pre-server)")
        var createdID: String?
        do {
            // Server call creation returns the LiveKit token in the same round trip (no separate token fetch).
            async let created: BlindbanditCallResponse = groupID != nil
                ? BlindbanditAPI.startGroupCall(groupID: groupID!, video: video)
                : BlindbanditAPI.startCall(handle: handle ?? "", video: video)
            let response = try await created
            CallTiming.step("server call created + token")
            createdID = response.id
            CallKitManager.shared.rebind(from: localID, to: response.id)
            if EndedCalls.contains(localID) {
                // User hung up while we were creating the call.
                CallSounds.stopOutgoingProgress()
                await BlindbanditAPI.endCall(id: response.id)
                CallKitManager.shared.reportEnded(callID: response.id, reason: nil)
                return
            }
            callKeyPeerHandle = handle
            // Phase 2: server minted the call (status typically ringing) — switch dial → US ringback.
            beginOutgoingRinging()
            CallTiming.step("ringback started (remote ringing)")
            // Call key is generated locally; delivery and LiveKit connect run in parallel.
            let msg = CallKeyMessage(call_id: response.id, key: E2EECrypto.b64u(CallKeyStore.newKey()), index: 0)
            async let delivered = sendCallKey(msg, handle: handle, groupID: groupID)
            try await connect(response: response, video: video, callKey: msg)
            CallTiming.step("LiveKit connected")
            let callKey: CallKeyMessage? = await delivered ? msg : nil
            CallTiming.step("call key delivered=\(callKey != nil)")
            if callKey == nil { markCallUnencrypted() }
            callKeyIsMine = true
            if callKey != nil, groupID != nil { startCallKeyPolling(callID: response.id) }
        } catch {
            CallTiming.step("failed: \(error.localizedDescription)")
            if let createdID {
                CallKitManager.shared.reportEnded(callID: createdID, reason: .failed)
                await BlindbanditAPI.endCall(id: createdID)
            } else {
                CallKitManager.shared.reportEnded(callID: localID, reason: .failed)
            }
            teardownRoom()
            CallSounds.busyOrFailed()
            statusMessage = (error as? CommunicationsError)?.isMissingRoute == true
                ? CommunicationsError.serverUpdateMessage
                : "Call failed: \(error.localizedDescription)"
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            AppHaptics.error()
        }
        await refreshCallHistory()
    }

    private func beginOutgoingRinging() {
        // room == nil (pre-LiveKit) means nobody has joined yet — treat as still ringing.
        let noRemoteYet = room?.remoteParticipants.isEmpty ?? true
        guard noRemoteYet else {
            if let id = activeCallID { CallKitManager.shared.reportOutgoingConnected(callID: id) }
            return
        }
        isRinging = true
        CallSounds.startRingback()
        statusMessage = "Ringing \(callPeerName)…"
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
        ringTimeout?.cancel()
        ringTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.ringTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled, let self, self.isRinging else { return }
            let peer = self.callPeerName
            self.endCall()
            self.statusMessage = self.callGroupID == nil ? "No answer from \(peer)." : "No one in \(peer) answered."
            UIAccessibility.post(notification: .announcement, argument: self.statusMessage)
        }
    }

    private func stopRinging(answered: Bool) {
        guard isRinging else { return }
        isRinging = false
        ringTimeout?.cancel()
        ringTimeout = nil
        CallSounds.stopRingback()
        if answered {
            callSeconds = 0
            CallSounds.callConnected()
            if let id = activeCallID { CallKitManager.shared.reportOutgoingConnected(callID: id) }
            statusMessage = callGroupID == nil ? "\(callPeerName) answered." : "Someone joined \(callPeerName)."
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
        }
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        applySpeaker()
        AppHaptics.selection()
        UIAccessibility.post(notification: .announcement, argument: speakerOn ? "Speaker on" : "Speaker off")
    }

    private func applySpeaker() {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    // MARK: Incoming

    /// Shows the full-screen incoming UI for a call id (from a push tap or polling).
    func presentIncomingCall(id: String) async {
        guard !id.isEmpty, activeCallID != id else { return }
        if let ringing = try? await BlindbanditAPI.incomingCalls().first(where: { $0.id == id }) {
            receiveIncoming(ringing)
            return
        }
        // Not ringing any more: just show history so the user sees it was missed.
        await refreshCallHistory()
        statusMessage = "That call has already ended."
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    /// Called for every ringing call we learn about (VoIP push, FCM-style polling, push tap).
    func receiveIncoming(_ call: BlindbanditIncomingCall) {
        if EndedCalls.shouldIgnore(id: call.id, createdAtMs: call.created_at) {
            CallTiming.log("ignored invite for ended/stale call \(call.id)")
            return
        }
        guard activeCallID != call.id, !isInCall || incomingCall == nil else { return }
        if isInCall {
            // Already busy: let CallKit show call waiting; we don't steal the screen.
            CallKitManager.shared.reportIncoming(call)
            return
        }
        incomingCall = call
        CallKitManager.shared.reportIncoming(call)
        if !announcedIncoming.contains(call.id) {
            announcedIncoming.insert(call.id)
            UIAccessibility.post(notification: .announcement, argument: "Incoming \(call.isVideo ? "video" : "voice") call from \(call.callerLabel)")
        }
    }

    func checkIncomingCalls() async {
        guard !myHandle.isEmpty || !myProfileID.isEmpty else { return }
        guard let ringing = try? await BlindbanditAPI.incomingCalls() else { return }
        if let current = incomingCall, !ringing.contains(where: { $0.id == current.id }) {
            remoteEnded(callID: current.id)
        }
        if let first = ringing.first(where: { $0.id != activeCallID }) { receiveIncoming(first) }
    }

    /// True when this device just answered/joined and a late "answered elsewhere" echo would kill the call.
    func shouldIgnoreAnswerEcho(callID: String) -> Bool {
        if joiningCallID == callID { return true }
        if let t = joinedAt[callID], Date().timeIntervalSince(t) < 8 { return true }
        return false
    }

    /// The caller hung up, someone answered on another device, or the server sent call_end.
    func remoteEnded(callID: String) {
        if shouldIgnoreAnswerEcho(callID: callID) { return } // our own "answered elsewhere" echo
        if activeCallID != callID || callGroupID == nil { EndedCalls.mark(callID) }
        if incomingCall?.id == callID {
            let missed = incomingCall
            incomingCall = nil
            CallSounds.stopLoop()
            CallKitManager.shared.reportEnded(callID: callID, reason: .unanswered)
            if let missed, missed.group_id != nil {
                missedGroupCalls.insert(missed, at: 0)
                missedGroupCalls = Array(missedGroupCalls.prefix(20))
            }
            if let missed {
                statusMessage = "Missed call from \(missed.callerLabel)."
                UIAccessibility.post(notification: .announcement, argument: statusMessage)
            }
            Task { await refreshCallHistory() }
        } else if activeCallID == callID, isInCall, callGroupID == nil {
            finishCall(notifyServer: false, announcement: "\(callPeerName) ended the call.")
        }
    }

    /// Answer button in the app (or Magic Tap). Goes through CallKit so the system call UI stays in sync.
    func answerIncoming() {
        guard let call = incomingCall else { return }
        CallSounds.stopLoop()
        CallKitManager.shared.requestAnswer(callID: call.id) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in _ = await self?.performJoin(id: call.id) }
        }
    }

    func declineIncoming() {
        guard let call = incomingCall else { return }
        CallSounds.stopLoop()
        CallKitManager.shared.requestEnd(callID: call.id) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in self?.performDecline(id: call.id) }
        }
    }

    /// CallKit decline (or fallback). Never leaves the server row ringing.
    func performDecline(id: String) {
        EndedCalls.mark(id)
        if incomingCall?.id == id { incomingCall = nil }
        CallSounds.stopLoop()
        Task {
            await BlindbanditAPI.declineCall(id: id)
            await refreshCallHistory()
        }
        statusMessage = "Call declined."
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    /// Kept for older callers (Calls tab "Join" buttons).
    func joinIncomingCall(id: String) async {
        if incomingCall?.id != id {
            incomingCall = BlindbanditIncomingCall(id: id, kind: "voice", from_handle: "", from_name: "Incoming call", group_id: nil, group_name: nil, created_at: Date().timeIntervalSince1970 * 1000)
        }
        _ = await performJoin(id: id)
    }

    /// Actually joins the LiveKit room. Called from CallKit's answer action.
    @discardableResult
    func performJoin(id: String) async -> Bool {
        guard !id.isEmpty else { return false }
        if activeCallID == id && isInCall { return true }
        let invite = incomingCall?.id == id ? incomingCall : nil
        CallSounds.stopLoop()
        statusMessage = "Joining call…"
        joiningCallID = id
        defer { joiningCallID = nil }
        do {
            let response = try await BlindbanditAPI.joinCall(id: id)
            if let invite {
                callPeerName = invite.group_name ?? invite.from_name
                callGroupID = invite.group_id
                callGroupName = invite.group_name
            } else if let peer = callHistory.first(where: { $0.id == id })?.other?.handle {
                callPeerName = "@\(peer)"
            } else {
                callPeerName = "Call"
            }
            callIsIncoming = true
            incomingCall = nil
            let voiceOnly = UserDefaults.standard.bool(forKey: "callkit.answerVoiceOnly")
            UserDefaults.standard.removeObject(forKey: "callkit.answerVoiceOnly")
            let peer = invite?.from_handle ?? callHistory.first(where: { $0.id == id })?.other?.handle
            callKeyIsMine = false
            callKeyPeerHandle = peer
            // Prefer a quick key wait so CallKit audio isn't stalled for ~8 s; announce clearly if missing.
            let callKey = await awaitCallKey(callID: id, handle: peer, groupID: callGroupID, attempts: 3)
            if callKey == nil {
                statusMessage = "Connecting without call encryption. Waiting for the other person's keys…"
                UIAccessibility.post(notification: .announcement, argument: statusMessage)
            }
            try await connect(response: response, video: !voiceOnly && ((invite?.isVideo ?? false) || response.kind == "video"), callKey: callKey)
            joinedAt[id] = Date()
            if callKey != nil, callGroupID != nil { startCallKeyPolling(callID: id) }
            // Keep polling briefly for a late key so we can surface encryption status.
            if callKey == nil {
                Task { [weak self] in
                    guard let self else { return }
                    if let late = await self.awaitCallKey(callID: id, handle: peer, groupID: self.callGroupID, attempts: 5) {
                        guard self.activeCallID == id else { return }
                        self.callEncryptionLabel = "End-to-end encrypted (key arrived late — reconnect for full protection)"
                        UIAccessibility.post(notification: .announcement, argument: self.callEncryptionLabel)
                        _ = late
                    } else if self.activeCallID == id {
                        self.markCallUnencrypted()
                        UIAccessibility.post(notification: .announcement, argument: self.callEncryptionLabel)
                    }
                }
            }
            return true
        } catch {
            incomingCall = nil
            await BlindbanditAPI.endCall(id: id)
            CallKitManager.shared.reportEnded(callID: id, reason: .failed)
            teardownRoom()
            CallSounds.busyOrFailed()
            statusMessage = (error as? CommunicationsError)?.isMissingRoute == true
                ? CommunicationsError.serverUpdateMessage
                : "Could not join call: \(error.localizedDescription)"
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            AppHaptics.error()
            return false
        }
    }

    private func connect(response: BlindbanditCallResponse, video: Bool, callKey: CallKeyMessage? = nil) async throws {
        let serverURL = (response.livekit.url?.isEmpty == false ? response.livekit.url : nil) ?? AppConfig.liveKitURL
        guard serverURL.hasPrefix("wss://") else { throw CommunicationsError.liveKitURLMissing }
        let observer = CallRoomObserver(service: self)
        let newRoom: Room
        if let callKey {
            // LiveKit frame encryption (AES-GCM) for every published track: mic (incl. mixed app audio), camera, screen share.
            let provider = BaseKeyProvider(isSharedKey: true)
            provider.setKey(key: callKey.key, index: Int32(callKey.index % 16))
            callKeyProvider = provider
            callKeyIndex = callKey.index
            callEncrypted = true
            callEncryptionLabel = "End-to-end encrypted"
            newRoom = Room(delegate: observer, roomOptions: RoomOptions(e2eeOptions: E2EEOptions(keyProvider: provider)))
        } else {
            callKeyProvider = nil
            callEncrypted = false
            callEncryptionLabel = "Not encrypted: other person needs to update"
            newRoom = Room(delegate: observer)
        }
        roomObserver = observer
        activeCallID = response.id
        UserDefaults.standard.set(serverURL, forKey: "livekit.lastURL")
        try await newRoom.connect(url: serverURL, token: response.livekit.token)
        room = newRoom
        isVideoCall = video
        micEnabled = true
        // Keep Apple voice processing / AEC on — bypassing it makes speakerphone echo badly.
        AudioManager.shared.isVoiceProcessingBypassed = false
        try await newRoom.localParticipant.setMicrophone(enabled: true)
        let startCameraOff = UserDefaults.standard.bool(forKey: "startCallsWithCameraOff")
        if video && !startCameraOff {
            _ = try await newRoom.localParticipant.setCamera(enabled: true)
            cameraEnabled = true
            speakerOn = true
            applySpeaker()
        } else {
            cameraEnabled = false
        }
        usingFrontCamera = true
        knownParticipantIDs = Set(newRoom.remoteParticipants.values.compactMap { $0.identity?.stringValue })
        hadRemote = !knownParticipantIDs.isEmpty
        aloneSince = nil
        isInCall = true
        callUIMinimized = false
        callSeconds = 0
        startTicker()
        refreshParticipants()
        if UserDefaults.standard.object(forKey: SettingsKey.liveCaptionsDefault) as? Bool ?? false, !captionsOn {
            captionsOn = true
            let tracks = newRoom.remoteParticipants.values.flatMap { $0.audioTracks.compactMap { $0.track as? RemoteAudioTrack } }
            setCaptions(true, tracks: tracks)
        }
        // Local LiveKit connect is NOT remote answer. Keep looping US ringback until a remote joins.
        if isRinging {
            AppHaptics.light()
            statusMessage = "Ringing \(callPeerName)…"
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
        } else {
            CallSounds.callConnected()
            AppHaptics.success()
            var connected = callGroupID == nil ? "Connected with \(callPeerName)." : "Joined \(callPeerName). \(participants.count) in the call."
            if !callEncryptionLabel.isEmpty { connected += " " + callEncryptionLabel + "." }
            statusMessage = connected
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
        }
    }

    // MARK: Room state

    func roomChanged() { refreshParticipants() }

    func roomDisconnected(_ closed: Room) {
        guard closed === room, isInCall else { return }
        finishCall(notifyServer: true, announcement: "Call disconnected.")
    }

    /// Rebuilds the grid, active speaker, video tracks and joined/left announcements.
    private func refreshParticipants() {
        guard let room else {
            participants = []
            localVideoTrack = nil
            remoteVideoTrack = nil
            return
        }
        let local = room.localParticipant
        let localCamera = local.firstCameraPublication?.track as? VideoTrack
        let localScreen = local.firstScreenSharePublication?.track as? VideoTrack
        var list: [CallParticipantInfo] = [CallParticipantInfo(
            id: local.identity?.stringValue ?? "me", name: "You", isLocal: true,
            isSpeaking: local.isSpeaking, micOn: micEnabled, cameraOn: cameraEnabled && localCamera != nil,
            sharingScreen: screenSharing, quality: local.connectionQuality, handRaised: handRaised,
            videoTrack: localCamera, screenTrack: localScreen
        )]
        let remotes = room.remoteParticipants.values.sorted { ($0.joinedAt ?? .distantPast) < ($1.joinedAt ?? .distantPast) }
        var currentIDs = Set<String>()
        for p in remotes {
            let id = p.identity?.stringValue ?? UUID().uuidString
            currentIDs.insert(id)
            let name = (p.name?.isEmpty == false ? p.name : nil) ?? "@\(id)"
            let camera = p.firstCameraPublication
            let screen = p.firstScreenSharePublication
            list.append(CallParticipantInfo(
                id: id, name: name, isLocal: false, isSpeaking: p.isSpeaking,
                micOn: p.isMicrophoneEnabled(), cameraOn: p.isCameraEnabled() && camera?.track != nil,
                sharingScreen: screen?.track != nil, quality: p.connectionQuality,
                handRaised: raisedHands.contains(id),
                videoTrack: camera?.isMuted == false ? camera?.track as? VideoTrack : nil,
                screenTrack: screen?.track as? VideoTrack
            ))
        }
        for joined in currentIDs.subtracting(knownParticipantIDs) {
            let name = list.first(where: { $0.id == joined })?.name ?? "Someone"
            UIAccessibility.post(notification: .announcement, argument: "\(name) joined the call")
            AppHaptics.light()
        }
        let leftIDs = knownParticipantIDs.subtracting(currentIDs)
        for left in leftIDs {
            let name = participants.first(where: { $0.id == left })?.name ?? "Someone"
            UIAccessibility.post(notification: .announcement, argument: "\(name) left the call")
            raisedHands.remove(left)
        }
        knownParticipantIDs = currentIDs
        if !currentIDs.isEmpty { hadRemote = true }
        participants = list
        localQuality = local.connectionQuality
        localVideoTrack = localCamera
        // Prefer someone's screen share, then the active speaker's camera, then anyone's camera.
        let speaker = room.activeSpeakers.first { !($0 is LocalParticipant) }?.identity?.stringValue
        activeSpeakerID = speaker
        remoteVideoTrack = list.first(where: { !$0.isLocal && $0.screenTrack != nil })?.screenTrack
            ?? list.first(where: { $0.id == speaker && $0.videoTrack != nil })?.videoTrack
            ?? list.first(where: { !$0.isLocal && $0.videoTrack != nil })?.videoTrack

        // Ending rules: a 1:1 call ends when the other person leaves; a group call when I've been alone 2 minutes.
        if isRinging, !currentIDs.isEmpty { stopRinging(answered: true) }
        if !isRinging, hadRemote, currentIDs.isEmpty {
            if callGroupID == nil, !leftIDs.isEmpty {
                finishCall(notifyServer: true, announcement: "\(callPeerName) left. Call ended.")
                return
            }
            if aloneSince == nil { aloneSince = Date() }
            if let since = aloneSince, Date().timeIntervalSince(since) > 120 {
                finishCall(notifyServer: true, announcement: "Everyone left. Call ended.")
            }
        } else {
            aloneSince = nil
        }
    }

    // MARK: Controls

    func toggleMic() { setMic(enabled: !micEnabled) }

    /// Idempotent so CallKit's mute action and the in-app button can both call it without looping.
    func setMic(enabled: Bool) {
        guard micEnabled != enabled else { return }
        micEnabled = enabled
        if screenSharing {
            // Broadcast app audio is mixed into the mic track, so while sharing keep the track live
            // and mute only the mic's input in the mixer; otherwise muting would also silence the shared audio.
            AudioManager.shared.mixer.micVolume = enabled ? 1 : 0
        } else {
            Task { try? await room?.localParticipant.setMicrophone(enabled: enabled) }
        }
        if let id = activeCallID { CallKitManager.shared.requestMute(callID: id, muted: !enabled) }
        AppHaptics.selection()
        UIAccessibility.post(notification: .announcement, argument: enabled ? "Microphone on" : "Muted")
        refreshParticipants()
    }

    func toggleCamera() {
        guard isInCall else { return }
        if !isVideoCall { upgradeToVideo(); return }
        cameraEnabled.toggle()
        let enabled = cameraEnabled
        Task {
            _ = try? await room?.localParticipant.setCamera(enabled: enabled)
            refreshParticipants()
        }
        AppHaptics.selection()
        UIAccessibility.post(notification: .announcement, argument: enabled ? "Camera on" : "Camera off")
    }

    /// Mid-call upgrade from voice to video. The other side sees the new camera track automatically.
    func upgradeToVideo() {
        guard isInCall else { return }
        isVideoCall = true
        cameraEnabled = true
        if !speakerOn { speakerOn = true; applySpeaker() }
        Task {
            do {
                _ = try await room?.localParticipant.setCamera(enabled: true)
                statusMessage = "Switched to video."
            } catch {
                cameraEnabled = false
                statusMessage = "Couldn't turn on the camera: \(error.localizedDescription)"
            }
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            refreshParticipants()
        }
        if let id = activeCallID { CallKitManager.shared.reportVideo(callID: id, video: true) }
    }

    /// Downgrade back to voice: camera and screen share off, earpiece unless the user chose speaker.
    func downgradeToVoice() {
        guard isInCall else { return }
        isVideoCall = false
        cameraEnabled = false
        Task {
            _ = try? await room?.localParticipant.setCamera(enabled: false)
            if screenSharing { _ = try? await room?.localParticipant.setScreenShare(enabled: false) }
            screenSharing = false
            refreshParticipants()
        }
        if let id = activeCallID { CallKitManager.shared.reportVideo(callID: id, video: false) }
        statusMessage = "Switched to voice only."
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    func switchCamera() {
        guard let capturer = (room?.localParticipant.firstCameraPublication?.track as? LocalVideoTrack)?.capturer as? CameraCapturer else {
            statusMessage = "Turn your camera on first."
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            return
        }
        Task {
            _ = try? await capturer.switchCameraPosition()
            usingFrontCamera = capturer.position != .back
            AppHaptics.selection()
            UIAccessibility.post(notification: .announcement, argument: usingFrontCamera ? "Front camera" : "Back camera")
        }
    }

    /// In-app screen share (LiveKit captures this app's screen).
    func toggleScreenShare() {
        guard let room else { return }
        let enable = !screenSharing
        Task {
            do {
                // Whole-iPhone sharing through the Broadcast Upload extension (iOS asks you to Start Broadcast);
                // turn off "Share whole screen" in Settings to share just this app.
                let whole = UserDefaults.standard.object(forKey: "screenShare.wholeScreen") as? Bool ?? true
                // appAudio: true makes LiveKit's BroadcastScreenCapturer pull .audioApp samples from the
                // extension and mix them into the published microphone track (the only way remote people hear
                // videos/music playing on the phone). Without it, only video was ever sent.
                if enable {
                    // App audio rides on the mic track: make sure it is published even when muted,
                    // and represent "muted" as mic volume 0 in the mixer.
                    AudioManager.shared.mixer.micVolume = micEnabled ? 1 : 0
                    AudioManager.shared.mixer.appVolume = 1
                    try await room.localParticipant.setMicrophone(enabled: true)
                }
                _ = try await room.localParticipant.set(source: .screenShareVideo, enabled: enable,
                    captureOptions: ScreenShareCaptureOptions(appAudio: true, useBroadcastExtension: whole))
                if !enable {
                    AudioManager.shared.mixer.micVolume = 1
                    if !micEnabled { try? await room.localParticipant.setMicrophone(enabled: false) }
                }
                screenSharing = enable
                statusMessage = enable
                    ? (whole
                       ? "Choose Mr. BlindBandit, then Start Broadcast. Everyone in the call will see your whole screen. Note: Apple Music, Netflix, Spotify and other protected apps can block their audio from screen share. That is an iOS limit."
                       : "Sharing your screen. Everyone in the call sees this app. Note: Apple Music, Netflix, Spotify and other protected apps can block their audio from screen share. That is an iOS limit.")
                    : "Stopped sharing your screen."
            } catch {
                statusMessage = "Screen sharing failed: \(error.localizedDescription)"
            }
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            refreshParticipants()
        }
    }

    func setHold(_ on: Bool) {
        guard isInCall, isOnHold != on else { return }
        isOnHold = on
        if on {
            holdRestore = (micEnabled, cameraEnabled)
            Task {
                try? await room?.localParticipant.setMicrophone(enabled: false)
                _ = try? await room?.localParticipant.setCamera(enabled: false)
            }
            micEnabled = false
            cameraEnabled = false
        } else if let restore = holdRestore {
            micEnabled = restore.mic
            cameraEnabled = restore.camera
            Task {
                try? await room?.localParticipant.setMicrophone(enabled: restore.mic)
                if restore.camera { _ = try? await room?.localParticipant.setCamera(enabled: true) }
            }
            holdRestore = nil
        }
        UIAccessibility.post(notification: .announcement, argument: on ? "Call on hold" : "Call resumed")
        refreshParticipants()
    }

    func toggleHand() {
        handRaised.toggle()
        send(CallDataMessage(type: "hand", raised: handRaised))
        UIAccessibility.post(notification: .announcement, argument: handRaised ? "Hand raised" : "Hand lowered")
        refreshParticipants()
    }

    func sendCallChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = UUID().uuidString
        callChat.append(InCallChatMessage(id: id, sender: "You", text: trimmed, mine: true, date: Date()))
        send(CallDataMessage(type: "chat", id: id, text: trimmed))
    }

    private func send(_ message: CallDataMessage) {
        guard let room, let data = try? JSONEncoder().encode(message) else { return }
        Task { try? await room.localParticipant.publish(data: data, options: DataPublishOptions(topic: "bb.call", reliable: true)) }
    }

    func handleCallData(_ data: Data, identity: String, sender: String) {
        guard let message = try? JSONDecoder().decode(CallDataMessage.self, from: data) else { return }
        switch message.type {
        case "hand":
            if message.raised == true {
                raisedHands.insert(identity)
                UIAccessibility.post(notification: .announcement, argument: "\(sender) raised their hand")
            } else {
                raisedHands.remove(identity)
            }
            refreshParticipants()
        case "chat":
            guard let text = message.text, !text.isEmpty else { return }
            callChat.append(InCallChatMessage(id: message.id ?? UUID().uuidString, sender: sender, text: text, mine: false, date: Date()))
            unreadCallChat += 1
            UIAccessibility.post(notification: .announcement, argument: "\(sender) says: \(text)")
        default:
            break
        }
    }

    /// Adds people to the call that's already running.
    func invite(handles: [String]) async {
        guard let id = activeCallID else { return }
        let clean = handles.map(BlindbanditHandle.normalize).filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        do {
            try await BlindbanditAPI.inviteToCall(id: id, handles: clean)
            statusMessage = "Ringing " + clean.map { "@\($0)" }.joined(separator: ", ") + "."
        } catch let error as CommunicationsError where error.isMissingRoute {
            statusMessage = CommunicationsError.serverUpdateMessage
        } catch {
            statusMessage = "Couldn't add people: \(error.localizedDescription)"
        }
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    // MARK: Ending

    /// In-app End button. CallKit runs the end action, which calls finishCall.
    func minimizeCallUI() {
        guard isInCall else { return }
        callUIMinimized = true
        UIAccessibility.post(notification: .announcement, argument: "Call minimized. Tap the call banner to return.")
        AppHaptics.light()
    }

    func expandCallUI() {
        guard isInCall else { return }
        callUIMinimized = false
        UIAccessibility.post(notification: .announcement, argument: "Call expanded.")
        AppHaptics.selection()
    }

    func endCall() {
        guard let id = activeCallID else { finishCall(notifyServer: false, announcement: "Call ended."); return }
        CallKitManager.shared.requestEnd(callID: id) { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in self?.finishCall(notifyServer: true, announcement: "Call ended.") }
        }
    }

    /// Tears everything down. Safe to call more than once.
    func finishCall(notifyServer: Bool, announcement: String) {
        let id = activeCallID
        if let id { EndedCalls.mark(id) }
        let closingRoom = room
        let wasActive = isInCall || id != nil
        stopRinging(answered: false)
        stopTicker()
        speakerOn = false
        Task {
            try? await closingRoom?.localParticipant.setMicrophone(enabled: false)
            _ = try? await closingRoom?.localParticipant.setCamera(enabled: false)
            await closingRoom?.disconnect()
            if notifyServer, let id { await BlindbanditAPI.endCall(id: id) }
            await self.refreshCallHistory()
        }
        if let id { CallKitManager.shared.reportEnded(callID: id, reason: nil) }
        room = nil
        roomObserver = nil
        activeCallID = nil
        isInCall = false
        callUIMinimized = false
        isVideoCall = false
        cameraEnabled = false
        micEnabled = true
        localVideoTrack = nil
        remoteVideoTrack = nil
        callSeconds = 0
        participants = []
        activeSpeakerID = nil
        callGroupID = nil
        callGroupName = nil
        screenSharing = false
        handRaised = false
        raisedHands = []
        callChat = []
        unreadCallChat = 0
        isOnHold = false
        holdRestore = nil
        knownParticipantIDs = []
        hadRemote = false
        aloneSince = nil
        if let id { joinedAt[id] = nil }
        guard wasActive else { return }
        CallSounds.hangup()
        statusMessage = announcement
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    // MARK: Call E2EE (2.0.6)

    /// Generates a fresh 256-bit frame key and sends it to every participant device inside a p256-v1 E2EE message
    /// (silent, hidden control payload). Returns nil when any recipient can't do E2EE (old app / no keys).
    /// Key delivery failed after connecting encrypted: the callee can't decrypt, so drop E2EE for this call
    /// rather than leave it silent, and say so on the call screen.
    private func markCallUnencrypted() {
        callEncrypted = false
        callEncryptionLabel = "Not encrypted: other person needs to update"
        callKeyProvider = nil
        if let room { room.e2eeManager?.enableE2EE(enabled: false) }
    }

    private func sendCallKey(_ msg: CallKeyMessage, handle: String?, groupID: String?) async -> Bool {
        let payload = E2EEPayload(t: "call_key", body: CallKeyStore.encode(msg), silent: true)
        do {
            if let groupID {
                guard try await E2EEService.shared.sendGroup(id: groupID, payload: payload) else { return false }
            } else if let handle, !handle.isEmpty {
                guard try await E2EEService.shared.sendDM(handle: handle, payload: payload) != nil else { return false }
            } else { return false }
        } catch {
            KeySetupLog.record("Call key delivery failed: \(error.localizedDescription)")
            return false
        }
        CallKeyStore.shared.set(msg)
        return true
    }

    private func sendNewCallKey(callID: String, handle: String?, groupID: String?, index: Int) async -> CallKeyMessage? {
        let msg = CallKeyMessage(call_id: callID, key: E2EECrypto.b64u(CallKeyStore.newKey()), index: index)
        let payload = E2EEPayload(t: "call_key", body: CallKeyStore.encode(msg), silent: true)
        do {
            if let groupID {
                guard try await E2EEService.shared.sendGroup(id: groupID, payload: payload) else { return nil }
            } else if let handle, !handle.isEmpty {
                guard try await E2EEService.shared.sendDM(handle: handle, payload: payload) != nil else { return nil }
            } else { return nil }
        } catch {
            KeySetupLog.record("Call key delivery failed: \(error.localizedDescription)")
            return nil
        }
        CallKeyStore.shared.set(msg)
        return msg
    }

    /// Pulls the caller's key message. No key ⇒ the caller is on an old app / keys missing ⇒ unencrypted fallback.
    private func awaitCallKey(callID: String, handle: String?, groupID: String?, attempts: Int = 3) async -> CallKeyMessage? {
        let n = max(1, attempts)
        for attempt in 0..<n {
            if let k = CallKeyStore.shared.keys[callID] { return k }
            await fetchCallKeyMessages(handle: handle, groupID: groupID)
            if let k = CallKeyStore.shared.keys[callID] { return k }
            if attempt < n - 1 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        return nil
    }

    private func fetchCallKeyMessages(handle: String?, groupID: String?) async {
        if let groupID {
            if let items = try? await BlindbanditAPI.groupMessages(id: groupID) {
                _ = E2EEService.shared.resolveGroup(items, groupID: groupID)
            }
        } else if let handle {
            let h = handle.lowercased()
            let convs = (try? await BlindbanditAPI.conversations()) ?? conversations
            guard let c = convs.first(where: { $0.other?.handle.lowercased() == h }),
                  let items = try? await BlindbanditAPI.messages(conversationID: c.id) else { return }
            _ = await E2EEService.shared.resolve(items, conversationID: c.id)
        }
    }

    /// Group calls: listen for rotated keys while connected.
    private func startCallKeyPolling(callID: String) {
        callKeyPoll?.cancel()
        CallKeyStore.shared.onKey = { [weak self] m in
            guard let self, m.call_id == callID, m.index > self.callKeyIndex else { return }
            self.callKeyIndex = m.index
            self.callKeyProvider?.setKey(key: m.key, index: Int32(m.index % 16))
        }
        callKeyPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, self.activeCallID == callID, !self.callKeyIsMine else { continue }
                await self.fetchCallKeyMessages(handle: nil, groupID: self.callGroupID)
            }
        }
    }

    /// Called when someone joins or leaves a group call: the caller rotates to a fresh key (forward/backward secrecy).
    func rotateCallKeyIfNeeded() {
        guard callKeyIsMine, callKeyProvider != nil, let callID = activeCallID, let groupID = callGroupID else { return }
        let next = callKeyIndex + 1
        Task { [weak self] in
            guard let self, let m = await self.sendNewCallKey(callID: callID, handle: nil, groupID: groupID, index: next) else { return }
            // Give receivers time to fetch it before switching our sending key.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard self.activeCallID == callID, next > self.callKeyIndex else { return }
            self.callKeyIndex = next
            self.callKeyProvider?.setKey(key: m.key, index: Int32(next % 16))
        }
    }

    private func teardownRoom() {
        callKeyPoll?.cancel(); callKeyPoll = nil
        CallKeyStore.shared.onKey = nil
        if let id = activeCallID {
            CallKeyStore.shared.clear(id)
            joinedAt[id] = nil
        }
        callKeyProvider = nil; callKeyIndex = 0; callKeyIsMine = false
        callEncrypted = false; callEncryptionLabel = ""
        let closingRoom = room
        Task { await closingRoom?.disconnect() }
        room = nil
        roomObserver = nil
        activeCallID = nil
        isInCall = false
        callUIMinimized = false
        isRinging = false
        ringTimeout?.cancel()
        CallSounds.stopLoop()
        stopTicker()
        participants = []
    }

    /// Clears everything held in memory, used on sign-out and account deletion.
    func reset() {
        AIPersona.serverHandle = ""
        ChatCache.clear()
        if isInCall { finishCall(notifyServer: true, announcement: "Call ended.") }
        incomingCall = nil
        stopPolling()
        callHistory = []
        blockedProfiles = []
        openConversationID = nil
        conversations = []
        messages = []
        myProfileID = ""
        myDisplayName = ""
        myAvatarURL = nil
        myHandle = ""
        UserDefaults.standard.removeObject(forKey: CallKitManager.myIDKey)
        UserDefaults.standard.removeObject(forKey: CallKitManager.myHandleKey)
        statusMessage = ""
        missedGroupCalls = []
        bootstrapped = false
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isRinging { self.callSeconds += 1 }
                self.refreshParticipants()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Per-participant actions

    @Published private(set) var locallyMuted: Set<String> = []
    @Published var lastCaption = ""
    @Published private(set) var captionsOn = false

    func toggleCaptions() {
        captionsOn.toggle()
        let tracks = room?.remoteParticipants.values.flatMap { $0.audioTracks.compactMap { $0.track as? RemoteAudioTrack } } ?? []
        setCaptions(captionsOn, tracks: tracks)
    }

    /// Mutes one person's audio on this phone only (they aren't told).
    func toggleLocalMute(participantID: String) {
        guard let p = room?.remoteParticipants.values.first(where: { $0.identity?.stringValue == participantID }) else { return }
        let mute = !locallyMuted.contains(participantID)
        for pub in p.audioTracks { (pub.track as? RemoteAudioTrack)?.volume = mute ? 0 : 1 }
        if mute { locallyMuted.insert(participantID) } else { locallyMuted.remove(participantID) }
        let name = participants.first(where: { $0.id == participantID })?.name ?? "them"
        UIAccessibility.post(notification: .announcement, argument: mute ? "\(name) muted for you" : "\(name) unmuted for you")
    }

    /// Admin only. Needs POST /v1/social/calls/{id}/remove (see addendum).
    func removeFromCall(participantID: String) async {
        guard let id = activeCallID else { return }
        do {
            try await BlindbanditAPI.removeFromCall(id: id, handle: participantID)
            statusMessage = "Removed from the call."
        } catch let error as CommunicationsError where error.isMissingRoute {
            statusMessage = CommunicationsError.serverUpdateMessage
        } catch {
            statusMessage = "Couldn't remove them: \(error.localizedDescription)"
        }
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }
}

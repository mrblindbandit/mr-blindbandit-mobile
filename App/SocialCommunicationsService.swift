import Foundation
import ClerkKit

struct SocialProfile: Codable, Equatable, Identifiable {
    let id: String
    let handle: String
    let displayName: String
    let avatarUrl: String?
    let verified: Bool?
}

struct SocialConversation: Codable, Equatable, Identifiable {
    struct Peer: Codable, Equatable {
        let handle: String
        let displayName: String
        let avatarUrl: String?
        let verified: Bool?
    }

    struct LastMessage: Codable, Equatable {
        let body: String
        let createdAt: Double
        let senderId: String
    }

    let id: String
    let updatedAt: Double
    let other: Peer?
    let lastMessage: LastMessage?
}

struct SocialMessage: Codable, Equatable, Identifiable {
    let id: String
    let senderId: String
    let body: String
    let createdAt: Double
    let readAt: Double?
}

struct LiveKitCredentials: Codable, Equatable {
    let token: String
    let identity: String
    let room: String
    let expiresAt: Double
    let url: String
}

struct SocialCallSession: Codable, Equatable {
    let id: String
    let room: String
    let kind: String
    let status: String
    let livekit: LiveKitCredentials
}

struct SentSocialMessage: Codable, Equatable {
    let id: String
    let conversationId: String
    let createdAt: Double
}

@MainActor
final class SocialCommunicationsService: ObservableObject {
    @Published private(set) var profile: SocialProfile?
    @Published private(set) var conversations: [SocialConversation] = []
    @Published private(set) var messages: [String: [SocialMessage]] = [:]
    @Published private(set) var busy = false
    @Published var statusMessage = ""

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func bootstrap() async {
        do {
            profile = try await request(path: "/v1/social/me", method: "GET", body: Optional<EmptyBody>.none)
            await refreshConversations()
        } catch {
            statusMessage = readable(error)
        }
    }

    func refreshConversations() async {
        do {
            let page: Page<SocialConversation> = try await request(path: "/v1/social/messages?limit=100", method: "GET", body: Optional<EmptyBody>.none)
            conversations = page.items
        } catch {
            statusMessage = readable(error)
        }
    }

    func loadMessages(conversationId: String) async {
        do {
            let page: Page<SocialMessage> = try await request(
                path: "/v1/social/messages/\(escaped(conversationId))?limit=100",
                method: "GET",
                body: Optional<EmptyBody>.none
            )
            messages[conversationId] = page.items.sorted { $0.createdAt < $1.createdAt }
        } catch {
            statusMessage = readable(error)
        }
    }

    /// Sends to a Blindbandit user by @handle or by email address.
    /// Existing production API uses profile handles; email input resolves to the default
    /// Clerk/social handle derived from the address local-part.
    func sendMessage(recipient: String, body: String) async -> SentSocialMessage? {
        await perform {
            let handle = try resolveRecipientHandle(recipient)
            let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw CommunicationsError("Type a message first.") }
            let payload = MessageRequest(handle: handle, body: clean)
            let sent: SentSocialMessage = try await request(path: "/v1/social/messages", method: "POST", body: payload)
            await refreshConversations()
            await loadMessages(conversationId: sent.conversationId)
            CallSounds.messageSent()
            AppHaptics.success()
            return sent
        }
    }

    func sendMessage(handle: String, body: String, conversationId: String) async -> Bool {
        let sent = await perform {
            let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw CommunicationsError("Type a message first.") }
            let payload = MessageRequest(handle: handle, body: clean)
            let result: SentSocialMessage = try await request(path: "/v1/social/messages", method: "POST", body: payload)
            await loadMessages(conversationId: result.conversationId)
            await refreshConversations()
            CallSounds.messageSent()
            return result
        }
        return sent != nil
    }

    func startCall(recipient: String, video: Bool) async -> SocialCallSession? {
        await perform {
            let handle = try resolveRecipientHandle(recipient)
            let payload = CallRequest(handle: handle, kind: video ? "video" : "voice")
            return try await request(path: "/v1/social/calls", method: "POST", body: payload)
        }
    }

    func joinCall(id: String) async -> SocialCallSession? {
        await perform {
            try await request(path: "/v1/social/calls/\(escaped(id))/join", method: "POST", body: EmptyBody())
        }
    }

    func endCall(id: String) async {
        do {
            let _: EndCallResponse = try await request(path: "/v1/social/calls/\(escaped(id))/end", method: "POST", body: EmptyBody())
        } catch {
            statusMessage = readable(error)
        }
    }

    func resolveRecipientHandle(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        if let at = value.firstIndex(of: "@") {
            value = String(value[..<at])
                .replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)
        }
        guard value.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil else {
            throw CommunicationsError("Enter a Blindbandit email address or @handle.")
        }
        return value
    }

    private func perform<T>(_ work: () async throws -> T) async -> T? {
        guard !busy else { return nil }
        busy = true
        statusMessage = ""
        defer { busy = false }
        do {
            return try await work()
        } catch {
            statusMessage = readable(error)
            AppHaptics.error()
            return nil
        }
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> Response {
        guard let url = URL(string: path, relativeTo: AppConfig.apiBaseURL) else {
            throw CommunicationsError("Invalid Platform API URL.")
        }
        guard let token = try await Clerk.shared.auth.getToken(), !token.isEmpty else {
            throw CommunicationsError("Your Clerk session expired. Sign in again.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommunicationsError("The Platform API returned an invalid response.")
        }

        if (200..<300).contains(http.statusCode) {
            let envelope = try decoder.decode(SuccessEnvelope<Response>.self, from: data)
            return envelope.data
        }

        if let api = try? decoder.decode(ErrorEnvelope.self, from: data) {
            throw CommunicationsError(api.error.message)
        }
        throw CommunicationsError("Platform API request failed (HTTP \(http.statusCode)).")
    }

    private func escaped(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func readable(_ error: Error) -> String {
        if let value = error as? CommunicationsError { return value.message }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Communications request failed." : text
    }
}

private struct Page<Item: Codable & Equatable>: Codable, Equatable {
    let items: [Item]
    let limit: Int?
    let offset: Int?
}

private struct MessageRequest: Codable { let handle: String; let body: String }
private struct CallRequest: Codable { let handle: String; let kind: String }
private struct EmptyBody: Codable {}
private struct EndCallResponse: Codable { let ended: Bool }

private struct SuccessEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T
}

private struct ErrorEnvelope: Decodable {
    struct APIError: Decodable { let code: String; let message: String; let requestId: String? }
    let success: Bool
    let error: APIError
}

private struct CommunicationsError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

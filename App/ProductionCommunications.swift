import Foundation
import SwiftUI
import LiveKit
import ClerkKit

struct BlindbanditSocialProfile: Decodable {
    let id: String
    let handle: String
    let display_name: String
}

struct BlindbanditConversation: Identifiable, Decodable, Equatable {
    struct Other: Decodable, Equatable {
        let handle: String
        let display_name: String
        let avatar_url: String?
        let verified: Bool?
    }
    struct LastMessage: Decodable, Equatable {
        let body: String
        let created_at: Double
        let sender_id: String
    }
    let id: String
    let updated_at: Double
    let other: Other?
    let last_message: LastMessage?
}

struct BlindbanditServerMessage: Identifiable, Decodable, Equatable {
    let id: String
    let sender_id: String
    let body: String
    let created_at: Double
    let read_at: Double?
}

struct BlindbanditLiveKitGrant: Decodable {
    let token: String
    let identity: String?
    let room: String
    let expires_at: Double?
    let url: String?
}

struct BlindbanditCallResponse: Decodable {
    struct Recipient: Decodable { let handle: String; let display_name: String }
    let id: String
    let room: String
    let kind: String
    let status: String
    let livekit: BlindbanditLiveKitGrant
    let recipient: Recipient?
}

struct BlindbanditMessageResponse: Decodable {
    struct Recipient: Decodable { let handle: String; let display_name: String }
    let id: String
    let conversation_id: String
    let created_at: Double
    let recipient: Recipient?
}

private struct ConversationListResponse: Decodable { let items: [BlindbanditConversation] }
private struct MessageListResponse: Decodable { let items: [BlindbanditServerMessage] }
private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String?; let message: String? }
    let error: Detail?
}

@MainActor
enum BlindbanditAPI {
    private static func url(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pieces = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(url: AppConfig.apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/" + String(pieces[0])
        if pieces.count > 1 { components.percentEncodedQuery = String(pieces[1]) }
        return components.url!
    }

    private static func request(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard let token = try await Clerk.shared.auth.getToken(), !token.isEmpty else {
            throw AuthServiceError.noActiveSession
        }
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunicationsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw CommunicationsError.server(envelope?.error?.message ?? "Server returned HTTP \(http.statusCode).")
        }
        return data
    }

    static func currentProfile() async throws -> BlindbanditSocialProfile {
        try JSONDecoder().decode(BlindbanditSocialProfile.self, from: try await request("v1/social/me"))
    }

    static func conversations() async throws -> [BlindbanditConversation] {
        try JSONDecoder().decode(ConversationListResponse.self, from: try await request("v1/social/messages?limit=100")).items
    }

    static func messages(conversationID: String) async throws -> [BlindbanditServerMessage] {
        let escaped = conversationID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conversationID
        return try JSONDecoder().decode(MessageListResponse.self, from: try await request("v1/social/messages/\(escaped)?limit=100")).items
    }

    static func sendMessage(recipient: String, body: String) async throws -> BlindbanditMessageResponse {
        try JSONDecoder().decode(BlindbanditMessageResponse.self, from: try await request(
            "v1/mobile-native/messages",
            method: "POST",
            body: ["recipient": recipient, "body": body]
        ))
    }

    static func startCall(recipient: String, video: Bool) async throws -> BlindbanditCallResponse {
        try JSONDecoder().decode(BlindbanditCallResponse.self, from: try await request(
            "v1/mobile-native/calls",
            method: "POST",
            body: ["recipient": recipient, "kind": video ? "video" : "voice"]
        ))
    }

    static func joinCall(id: String) async throws -> BlindbanditCallResponse {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try JSONDecoder().decode(BlindbanditCallResponse.self, from: try await request(
            "v1/social/calls/\(escaped)/join",
            method: "POST",
            body: [:]
        ))
    }

    static func endCall(id: String) async {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try? await request("v1/social/calls/\(escaped)/end", method: "POST", body: [:])
    }

    static func registerPushToken(_ token: String) async throws {
        guard !token.isEmpty else { return }
        let installationKey = "blindbandit.installationID"
        let defaults = UserDefaults.standard
        let installationID: String
        if let existing = defaults.string(forKey: installationKey), !existing.isEmpty {
            installationID = existing
        } else {
            installationID = UUID().uuidString
            defaults.set(installationID, forKey: installationKey)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppConfig.marketingVersion
        _ = try await request(
            "v1/social/devices/register",
            method: "POST",
            body: [
                "installation_id": installationID,
                "platform": "ios",
                "token": token,
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The Blindbandit API returned an invalid response."
        case .server(let message): return message
        case .liveKitURLMissing: return "The server did not return a LiveKit URL."
        }
    }
}

@MainActor
final class ProductionCommunicationsService: ObservableObject {
    @Published private(set) var conversations: [BlindbanditConversation] = []
    @Published private(set) var messages: [BlindbanditServerMessage] = []
    @Published private(set) var myProfileID = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isInCall = false
    @Published private(set) var isVideoCall = false
    @Published private(set) var micEnabled = true
    @Published private(set) var cameraEnabled = false
    @Published private(set) var callSeconds = 0
    @Published private(set) var activeCallID: String?
    @Published private(set) var callPeerName = ""
    @Published var statusMessage = ""

    private var room: Room?
    private var ticker: Timer?
    private var selectedConversationID: String?

    var callTimeLabel: String {
        String(format: "%02d:%02d", callSeconds / 60, callSeconds % 60)
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await BlindbanditAPI.currentProfile()
            myProfileID = profile.id
            conversations = try await BlindbanditAPI.conversations()
            statusMessage = "Calls and messages are online."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshConversations() async {
        do { conversations = try await BlindbanditAPI.conversations() }
        catch { statusMessage = error.localizedDescription }
    }

    func openConversation(_ conversation: BlindbanditConversation) async {
        selectedConversationID = conversation.id
        do {
            messages = try await BlindbanditAPI.messages(conversationID: conversation.id).sorted { $0.created_at < $1.created_at }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func sendMessage(recipient: String, body: String) async -> String? {
        let target = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !text.isEmpty else {
            statusMessage = "Enter a recipient email or username and a message."
            return nil
        }
        do {
            let response = try await BlindbanditAPI.sendMessage(recipient: target, body: text)
            CallSounds.messageSent()
            statusMessage = "Message sent to \(response.recipient?.display_name ?? target)."
            await refreshConversations()
            if let conversation = conversations.first(where: { $0.id == response.conversation_id }) {
                await openConversation(conversation)
            }
            return response.conversation_id
        } catch {
            statusMessage = error.localizedDescription
            AppHaptics.error()
            return nil
        }
    }

    func startCall(recipient: String, video: Bool) async {
        let target = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            statusMessage = "Enter the person's email address or Blindbandit username first."
            AppHaptics.warning()
            return
        }
        CallSounds.callInitiated()
        statusMessage = "Calling \(target)…"
        do {
            let response = try await BlindbanditAPI.startCall(recipient: target, video: video)
            callPeerName = response.recipient?.display_name ?? target
            try await connect(response: response, video: video)
        } catch {
            CallSounds.busyOrFailed()
            statusMessage = "Call failed: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }

    func joinIncomingCall(id: String) async {
        guard !id.isEmpty else { return }
        CallSounds.stopLoop()
        statusMessage = "Joining incoming call…"
        do {
            let response = try await BlindbanditAPI.joinCall(id: id)
            callPeerName = "Incoming call"
            try await connect(response: response, video: response.kind == "video")
        } catch {
            CallSounds.busyOrFailed()
            statusMessage = "Could not join call: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }

    private func connect(response: BlindbanditCallResponse, video: Bool) async throws {
        guard let url = response.livekit.url, !url.isEmpty else { throw CommunicationsError.liveKitURLMissing }
        let newRoom = Room()
        try await newRoom.connect(url: url, token: response.livekit.token)
        room = newRoom
        activeCallID = response.id
        isVideoCall = video
        micEnabled = true
        try await newRoom.localParticipant.setMicrophone(enabled: true)
        if video {
            try await newRoom.localParticipant.setCamera(enabled: true)
            cameraEnabled = true
        } else {
            cameraEnabled = false
        }
        isInCall = true
        callSeconds = 0
        startTicker()
        CallSounds.callConnected()
        AppHaptics.success()
        statusMessage = "Connected with \(callPeerName)."
    }

    func toggleMic() {
        micEnabled.toggle()
        Task { try? await room?.localParticipant.setMicrophone(enabled: micEnabled) }
        AppHaptics.selection()
    }

    func toggleCamera() {
        guard isVideoCall else { return }
        cameraEnabled.toggle()
        Task { try? await room?.localParticipant.setCamera(enabled: cameraEnabled) }
        AppHaptics.selection()
    }

    func endCall() {
        let id = activeCallID
        stopTicker()
        Task {
            try? await room?.localParticipant.setMicrophone(enabled: false)
            try? await room?.localParticipant.setCamera(enabled: false)
            await room?.disconnect()
            if let id { await BlindbanditAPI.endCall(id: id) }
        }
        room = nil
        activeCallID = nil
        isInCall = false
        isVideoCall = false
        cameraEnabled = false
        callSeconds = 0
        CallSounds.hangup()
        statusMessage = "Call ended."
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.callSeconds += 1 }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

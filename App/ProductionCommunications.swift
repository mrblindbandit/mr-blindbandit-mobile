import Foundation
import SwiftUI
import UIKit
import LiveKit
import ClerkKit

// MARK: - API models (shapes match worker/platform/social.ts on api.mrblindbandit.net)

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
    let id: String
    let room: String
    let kind: String
    let status: String
    let livekit: BlindbanditLiveKitGrant
}

struct BlindbanditMessageResponse: Decodable {
    let id: String
    let conversation_id: String
    let created_at: Double
}

private struct ItemsPayload<Item: Decodable>: Decodable { let items: [Item] }

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

@MainActor
enum BlindbanditAPI {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(BlindbanditEnvelope<T>.self, from: data).data
    }

    private static func url(_ path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pieces = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(url: AppConfig.apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/" + String(pieces[0])
        if pieces.count > 1 { components.percentEncodedQuery = String(pieces[1]) }
        return components.url!
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? value
    }

    @discardableResult
    static func request(
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
            throw CommunicationsError.server(envelope?.error?.message ?? "The Blindbandit server returned an error (HTTP \(http.statusCode)).")
        }
        return data
    }

    static func currentProfile() async throws -> BlindbanditSocialProfile {
        try decode(BlindbanditSocialProfile.self, from: try await request("v1/social/me"))
    }

    static func conversations() async throws -> [BlindbanditConversation] {
        try decode(ItemsPayload<BlindbanditConversation>.self, from: try await request("v1/social/messages?limit=100")).items
    }

    static func messages(conversationID: String) async throws -> [BlindbanditServerMessage] {
        try decode(ItemsPayload<BlindbanditServerMessage>.self, from: try await request("v1/social/messages/\(escape(conversationID))?limit=100")).items
    }

    static func sendMessage(handle: String, body: String) async throws -> BlindbanditMessageResponse {
        try decode(BlindbanditMessageResponse.self, from: try await request(
            "v1/social/messages", method: "POST", body: ["handle": handle, "body": body]
        ))
    }

    static func startCall(handle: String, video: Bool) async throws -> BlindbanditCallResponse {
        try decode(BlindbanditCallResponse.self, from: try await request(
            "v1/social/calls", method: "POST", body: ["handle": handle, "kind": video ? "video" : "voice"]
        ))
    }

    static func joinCall(id: String) async throws -> BlindbanditCallResponse {
        try decode(BlindbanditCallResponse.self, from: try await request(
            "v1/social/calls/\(escape(id))/join", method: "POST", body: [:]
        ))
    }

    static func endCall(id: String) async {
        _ = try? await request("v1/social/calls/\(escape(id))/end", method: "POST", body: [:])
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
        try await request(
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
    @Published private(set) var myHandle = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isInCall = false
    @Published private(set) var isVideoCall = false
    @Published private(set) var micEnabled = true
    @Published private(set) var cameraEnabled = false
    @Published private(set) var callSeconds = 0
    @Published private(set) var activeCallID: String?
    @Published private(set) var callPeerName = ""
    @Published private(set) var localVideoTrack: VideoTrack?
    @Published private(set) var remoteVideoTrack: VideoTrack?
    @Published var statusMessage = ""

    private var room: Room?
    private var ticker: Timer?
    private var bootstrapped = false

    var callTimeLabel: String {
        String(format: "%02d:%02d", callSeconds / 60, callSeconds % 60)
    }

    func bootstrap(force: Bool = false) async {
        guard force || !bootstrapped else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // GET /v1/social/me creates the profile on first use; other social endpoints require it.
            let profile = try await BlindbanditAPI.currentProfile()
            myProfileID = profile.id
            myHandle = profile.handle
            conversations = try await BlindbanditAPI.conversations()
            bootstrapped = true
            statusMessage = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshConversations() async {
        do { conversations = try await BlindbanditAPI.conversations() }
        catch { statusMessage = error.localizedDescription }
    }

    func openConversation(_ conversation: BlindbanditConversation) async {
        do {
            messages = try await BlindbanditAPI.messages(conversationID: conversation.id).sorted { $0.created_at < $1.created_at }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func conversation(id: String) -> BlindbanditConversation? {
        conversations.first { $0.id == id }
    }

    func sendMessage(recipient: String, body: String) async -> String? {
        let handle = BlindbanditHandle.normalize(recipient)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty, !text.isEmpty else {
            statusMessage = "Enter a Blindbandit username and a message."
            return nil
        }
        do {
            let response = try await BlindbanditAPI.sendMessage(handle: handle, body: String(text.prefix(4000)))
            CallSounds.messageSent()
            statusMessage = "Message sent to @\(handle)."
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            await refreshConversations()
            return response.conversation_id
        } catch {
            statusMessage = error.localizedDescription
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

    func startCall(recipient: String, video: Bool) async {
        let handle = BlindbanditHandle.normalize(recipient)
        guard !handle.isEmpty else {
            statusMessage = "Enter the person's Blindbandit username first."
            AppHaptics.warning()
            return
        }
        guard !isInCall else { return }
        CallSounds.callInitiated()
        statusMessage = "Calling @\(handle)…"
        do {
            let response = try await BlindbanditAPI.startCall(handle: handle, video: video)
            callPeerName = "@\(handle)"
            try await connect(response: response, video: video)
        } catch {
            CallSounds.busyOrFailed()
            statusMessage = "Call failed: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }

    func joinIncomingCall(id: String) async {
        guard !id.isEmpty, !isInCall else { return }
        CallSounds.stopLoop()
        statusMessage = "Joining call…"
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
        let serverURL = (response.livekit.url?.isEmpty == false ? response.livekit.url : nil) ?? AppConfig.liveKitURL
        guard serverURL.hasPrefix("wss://") else { throw CommunicationsError.liveKitURLMissing }
        let newRoom = Room()
        try await newRoom.connect(url: serverURL, token: response.livekit.token)
        room = newRoom
        activeCallID = response.id
        isVideoCall = video
        micEnabled = true
        try await newRoom.localParticipant.setMicrophone(enabled: true)
        let startCameraOff = UserDefaults.standard.bool(forKey: "startCallsWithCameraOff")
        if video && !startCameraOff {
            try await newRoom.localParticipant.setCamera(enabled: true)
            cameraEnabled = true
        } else {
            cameraEnabled = false
        }
        isInCall = true
        callSeconds = 0
        startTicker()
        refreshVideoTracks()
        CallSounds.callConnected()
        AppHaptics.success()
        statusMessage = "Connected with \(callPeerName)."
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    /// Polls LiveKit participants once per second (driven by the call ticker) so the video
    /// views pick up tracks as the other person turns their camera on or off.
    private func refreshVideoTracks() {
        guard let room else {
            localVideoTrack = nil
            remoteVideoTrack = nil
            return
        }
        localVideoTrack = room.localParticipant.videoTracks.first?.track as? VideoTrack
        remoteVideoTrack = room.remoteParticipants.values
            .flatMap { $0.videoTracks }
            .compactMap { $0.track as? VideoTrack }
            .first
    }

    func toggleMic() {
        micEnabled.toggle()
        let enabled = micEnabled
        Task { try? await room?.localParticipant.setMicrophone(enabled: enabled) }
        AppHaptics.selection()
        UIAccessibility.post(notification: .announcement, argument: enabled ? "Microphone on" : "Muted")
    }

    func toggleCamera() {
        guard isVideoCall else { return }
        cameraEnabled.toggle()
        let enabled = cameraEnabled
        Task {
            try? await room?.localParticipant.setCamera(enabled: enabled)
            refreshVideoTracks()
        }
        AppHaptics.selection()
        UIAccessibility.post(notification: .announcement, argument: enabled ? "Camera on" : "Camera off")
    }

    func endCall() {
        let id = activeCallID
        let closingRoom = room
        stopTicker()
        Task {
            try? await closingRoom?.localParticipant.setMicrophone(enabled: false)
            try? await closingRoom?.localParticipant.setCamera(enabled: false)
            await closingRoom?.disconnect()
            if let id { await BlindbanditAPI.endCall(id: id) }
        }
        room = nil
        activeCallID = nil
        isInCall = false
        isVideoCall = false
        cameraEnabled = false
        localVideoTrack = nil
        remoteVideoTrack = nil
        callSeconds = 0
        CallSounds.hangup()
        statusMessage = "Call ended."
        UIAccessibility.post(notification: .announcement, argument: statusMessage)
    }

    /// Clears everything held in memory, used on sign-out and account deletion.
    func reset() {
        if isInCall { endCall() }
        conversations = []
        messages = []
        myProfileID = ""
        myHandle = ""
        statusMessage = ""
        bootstrapped = false
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.callSeconds += 1
                self.refreshVideoTracks()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

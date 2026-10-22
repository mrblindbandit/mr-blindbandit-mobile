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
}

struct BlindbanditConversation: Identifiable, Decodable, Equatable {
    struct Other: Decodable, Equatable {
        let handle: String
        let display_name: String
        let avatar_url: String?
        /// The list endpoint returns SQLite 0/1 here while other endpoints return true/false.
        /// A strict `Bool?` made the whole inbox fail to decode, which hid every conversation.
        let verified: Bool?

        init(handle: String, display_name: String, avatar_url: String?, verified: Bool?) {
            self.handle = handle; self.display_name = display_name; self.avatar_url = avatar_url; self.verified = verified
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            handle = try c.decode(String.self, forKey: .handle)
            display_name = (try? c.decode(String.self, forKey: .display_name)) ?? handle
            avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
            verified = FlexibleBool.decode(c, .verified)
        }

        enum CodingKeys: String, CodingKey { case handle, display_name, avatar_url, verified }
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
        // Store screenshot mode never configures Clerk, so never touch Clerk.shared there.
        if StoreScreenshotMode.isActive { throw AuthServiceError.noActiveSession }
        guard let token = await clerkTokenWithTimeout() else {
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

    static func markRead(conversationID: String) async throws {
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
    @Published private(set) var loadError = ""
    @Published private(set) var callHistory: [BlindbanditCallRecord] = []
    @Published private(set) var historyError = ""
    @Published private(set) var blockedProfiles: [BlindbanditBlockedProfile] = []
    @Published private(set) var isRinging = false
    @Published private(set) var speakerOn = false
    @Published private(set) var openConversationID: String?
    @Published private(set) var lastReadStamp: [String: Double] = LocalComms.lastRead
    @Published private(set) var pendingMessages: [PendingMessage] = LocalComms.pending

    private var room: Room?
    private var pollTimer: Timer?
    private var ringTimeout: Task<Void, Never>?
    /// The outgoing call is marked missed by the server after a short wait; we stop ringing at 45 seconds
    /// and always send end so the call never stays stuck as ringing.
    static let ringTimeoutSeconds: UInt64 = 45
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
            loadError = ""
            startPolling()
            await flushPendingMessages()
        } catch {
            loadError = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func refreshConversations() async {
        do {
            let fresh = try await BlindbanditAPI.conversations()
            announceNewIncoming(old: conversations, new: fresh)
            conversations = fresh
            loadError = ""
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Unread state (stored on this iPhone; the server records read_at when a thread is opened)

    func isUnread(_ conversation: BlindbanditConversation) -> Bool {
        guard let last = conversation.last_message, last.sender_id != myProfileID, !myProfileID.isEmpty else { return false }
        return last.created_at > (lastReadStamp[conversation.id] ?? 0)
    }

    var unreadCount: Int {
        conversations.filter { isUnread($0) && !LocalComms.muted.contains($0.id) }.count
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
    }

    private func announceNewIncoming(old: [BlindbanditConversation], new: [BlindbanditConversation]) {
        guard !old.isEmpty else { return }
        for conversation in new where isUnread(conversation) && conversation.id != openConversationID {
            let before = old.first { $0.id == conversation.id }?.last_message?.created_at ?? 0
            if (conversation.last_message?.created_at ?? 0) > before, !LocalComms.muted.contains(conversation.id) {
                CallSounds.inboundNotification()
                let who = conversation.other.map { "@\($0.handle)" } ?? "someone"
                UIAccessibility.post(notification: .announcement, argument: "New message from \(who)")
            }
        }
    }

    func openConversation(_ conversation: BlindbanditConversation) async {
        openConversationID = conversation.id
        await reloadThread(conversation.id)
        markLocallyRead(conversation)
        try? await BlindbanditAPI.markRead(conversationID: conversation.id)
    }

    func closeConversation() {
        openConversationID = nil
        messages = []
    }

    private func reloadThread(_ id: String) async {
        do {
            let fresh = try await BlindbanditAPI.messages(conversationID: id).sorted { $0.created_at < $1.created_at }
            guard openConversationID == id else { return }
            let hadIncoming = fresh.count > messages.count && fresh.last?.sender_id != myProfileID && !messages.isEmpty
            if fresh != messages { messages = fresh }
            if hadIncoming, let current = self.conversation(id: id) {
                CallSounds.inboundNotification()
                markLocallyRead(current)
                try? await BlindbanditAPI.markRead(conversationID: id)
            }
            loadError = ""
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Live updates (polling: the server has no socket or push channel for message events)

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, UIApplication.shared.applicationState == .active else { return }
                await self.refreshConversations()
                if let id = self.openConversationID { await self.reloadThread(id) }
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
            if openConversationID == response.conversation_id { await reloadThread(response.conversation_id) }
            return response.conversation_id
        } catch let error as URLError where [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            pendingMessages.append(PendingMessage(handle: handle, body: String(text.prefix(4000))))
            LocalComms.pending = pendingMessages
            statusMessage = "You're offline. The message to @\(handle) will send when you're back online."
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
            AppHaptics.warning()
            return nil
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
        var createdID: String?
        do {
            let response = try await BlindbanditAPI.startCall(handle: handle, video: video)
            createdID = response.id
            callPeerName = "@\(handle)"
            try await connect(response: response, video: video)
            LocalComms.recordRecent(handle)
            beginOutgoingRinging()
        } catch {
            // Never leave the server row as 'ringing' when we could not connect.
            if let createdID { await BlindbanditAPI.endCall(id: createdID) }
            teardownRoom()
            CallSounds.busyOrFailed()
            statusMessage = "Call failed: \(error.localizedDescription)"
            AppHaptics.error()
        }
        await refreshCallHistory()
    }

    private func beginOutgoingRinging() {
        guard room?.remoteParticipants.isEmpty ?? false else { return }
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
            self.statusMessage = "No answer from \(peer)."
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
            statusMessage = "\(callPeerName) answered."
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
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    func joinIncomingCall(id: String) async {
        guard !id.isEmpty, !isInCall else { return }
        CallSounds.stopLoop()
        statusMessage = "Joining call…"
        do {
            let response = try await BlindbanditAPI.joinCall(id: id)
            if let peer = callHistory.first(where: { $0.id == id })?.other?.handle {
                callPeerName = "@\(peer)"
            } else {
                callPeerName = "Incoming call"
            }
            try await connect(response: response, video: response.kind == "video")
        } catch {
            await BlindbanditAPI.endCall(id: id)
            teardownRoom()
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

    private func teardownRoom() {
        let closingRoom = room
        Task { await closingRoom?.disconnect() }
        room = nil
        activeCallID = nil
        isInCall = false
        isRinging = false
        ringTimeout?.cancel()
        CallSounds.stopLoop()
        stopTicker()
    }

    func endCall() {
        let id = activeCallID
        let closingRoom = room
        stopRinging(answered: false)
        speakerOn = false
        stopTicker()
        Task {
            try? await closingRoom?.localParticipant.setMicrophone(enabled: false)
            try? await closingRoom?.localParticipant.setCamera(enabled: false)
            await closingRoom?.disconnect()
            if let id { await BlindbanditAPI.endCall(id: id) }
            await self.refreshCallHistory()
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
        stopPolling()
        callHistory = []
        blockedProfiles = []
        openConversationID = nil
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
                if self.isRinging {
                    if !(self.room?.remoteParticipants.isEmpty ?? true) { self.stopRinging(answered: true) }
                } else {
                    self.callSeconds += 1
                }
                self.refreshVideoTracks()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

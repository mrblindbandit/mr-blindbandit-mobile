import Foundation
import SwiftUI
import CryptoKit
import UIKit
import UserNotifications
import CallKit
import AVFoundation
@preconcurrency import LiveKit

enum TestIdentity {
    static func normalizePhone(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        return hasPlus ? "+\(digits)" : digits
    }

    static func routingKey(for raw: String) -> String {
        normalizePhone(raw).filter(\.isNumber)
    }

    static func stableRoomName(prefix: String, value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(hash.prefix(28))"
    }

    static func inboxRoom(for phone: String) -> String {
        stableRoomName(prefix: "bb-inbox", value: routingKey(for: phone))
    }
}

@MainActor
final class TestProfileStore: ObservableObject {
    @Published var username: String
    @Published var phoneNumber: String
    @Published var liveKitDevelopmentTokenServerID: String

    private let defaults: UserDefaults
    private static let usernameKey = "testUsername"
    private static let phoneKey = "testPhoneNumber"
    private static let tokenServerKey = "liveKitDevelopmentTokenServerID"
    private static let deviceIDKey = "testDeviceID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        username = defaults.string(forKey: Self.usernameKey) ?? ""
        phoneNumber = defaults.string(forKey: Self.phoneKey) ?? ""
        liveKitDevelopmentTokenServerID = defaults.string(forKey: Self.tokenServerKey) ?? ""

        if defaults.string(forKey: Self.deviceIDKey) == nil {
            defaults.set(UUID().uuidString.lowercased(), forKey: Self.deviceIDKey)
        }
    }

    var isConfigured: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !TestIdentity.routingKey(for: phoneNumber).isEmpty
    }

    var normalizedPhone: String {
        TestIdentity.normalizePhone(phoneNumber)
    }

    var deviceIdentity: String {
        let value = defaults.string(forKey: Self.deviceIDKey) ?? UUID().uuidString.lowercased()
        return "ios-\(value)"
    }

    func save(username: String, phoneNumber: String, tokenServerID: String) {
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhone = TestIdentity.normalizePhone(phoneNumber)
        let cleanToken = tokenServerID.trimmingCharacters(in: .whitespacesAndNewlines)

        self.username = cleanName
        self.phoneNumber = cleanPhone
        liveKitDevelopmentTokenServerID = cleanToken

        defaults.set(cleanName, forKey: Self.usernameKey)
        defaults.set(cleanPhone, forKey: Self.phoneKey)
        defaults.set(cleanToken, forKey: Self.tokenServerKey)
    }

    func saveTokenServerID(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        liveKitDevelopmentTokenServerID = clean
        defaults.set(clean, forKey: Self.tokenServerKey)
    }
}

enum SignalKind: String, Codable {
    case callInvite
    case callAccept
    case callReject
    case callCancel
    case callEnd
    case message
}

struct SignalEnvelope: Codable {
    var kind: SignalKind
    var id = UUID()
    var callID: UUID?
    var fromUsername: String
    var fromPhone: String
    var toPhone: String
    var isVideo = false
    var body: String?
    var sentAt = Date()
}

struct TestMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let remotePhone: String
    let senderName: String
    let body: String
    let isIncoming: Bool
    let sentAt: Date
}

enum CallDirection: String, Codable {
    case incoming
    case outgoing
}

enum CallPhase: String, Codable {
    case ringing
    case connecting
    case active
}

struct CallSession: Identifiable, Equatable {
    let id: UUID
    var remoteUsername: String
    let remotePhone: String
    let isVideo: Bool
    let direction: CallDirection
    var phase: CallPhase
}

@MainActor
final class LiveKitCommunicationManager: NSObject, ObservableObject, RoomDelegate, @unchecked Sendable {
    @Published private(set) var inboxStatus = "Not connected"
    @Published private(set) var lastError = ""
    @Published var currentCall: CallSession?
    @Published private(set) var messages: [TestMessage] = []
    @Published private(set) var localVideoTrack: VideoTrack?
    @Published private(set) var remoteVideoTrack: VideoTrack?
    @Published private(set) var microphoneMuted = false
    @Published private(set) var cameraEnabled = false
    @Published private(set) var speakerOn = false

    private weak var profile: TestProfileStore?
    private var inboxRoom: Room?
    private var outgoingSignalRoom: Room?
    private var activeCallRoom: Room?
    private let callKit = CallKitController()
    private let signalTopic = "blindbandit.signal"
    private let messagesDefaultsKey = "testMessages"

    override init() {
        super.init()
        loadMessages()

        callKit.onAnswer = { [weak self] uuid in
            Task { @MainActor in await self?.acceptIncomingCall(uuid) }
        }
        callKit.onEnd = { [weak self] uuid in
            Task { @MainActor in await self?.systemEndedCall(uuid) }
        }
        callKit.onMute = { [weak self] uuid, muted in
            Task { @MainActor in
                guard self?.currentCall?.id == uuid else { return }
                await self?.setMuted(muted)
            }
        }
    }

    func attach(profile: TestProfileStore) {
        self.profile = profile
    }

    func startInbox() {
        Task { await connectInbox() }
    }

    func restartInbox() {
        Task {
            if let room = inboxRoom { await room.disconnect() }
            inboxRoom = nil
            await connectInbox()
        }
    }

    private func connectInbox() async {
        guard let profile, profile.isConfigured else {
            inboxStatus = "Set up your test profile"
            return
        }
        guard !profile.liveKitDevelopmentTokenServerID.isEmpty else {
            inboxStatus = "LiveKit test server ID needed"
            return
        }

        inboxStatus = "Connecting…"
        lastError = ""
        do {
            let roomName = TestIdentity.inboxRoom(for: profile.normalizedPhone)
            let credentials = try await credentials(roomName: roomName)
            let room = Room(delegate: self)
            try await room.connect(url: credentials.serverURL.absoluteString,
                                   token: credentials.participantToken)
            inboxRoom = room
            inboxStatus = "Ready for calls & messages"
        } catch {
            inboxStatus = "Connection failed"
            lastError = error.localizedDescription
            AppHaptics.error()
        }
    }

    func startCall(to rawPhone: String, video: Bool) {
        Task { await beginOutgoingCall(to: rawPhone, video: video) }
    }

    private func beginOutgoingCall(to rawPhone: String, video: Bool) async {
        guard currentCall == nil else {
            lastError = "End the current call before starting another one."
            AppHaptics.warning()
            return
        }
        guard let profile, profile.isConfigured else { return }
        guard !profile.liveKitDevelopmentTokenServerID.isEmpty else {
            lastError = "Add your LiveKit development token server ID in Communications Settings first."
            AppHaptics.warning()
            return
        }

        let target = TestIdentity.normalizePhone(rawPhone)
        guard !TestIdentity.routingKey(for: target).isEmpty else {
            lastError = "Enter a phone number for the other tester."
            AppHaptics.warning()
            return
        }
        guard TestIdentity.routingKey(for: target) != TestIdentity.routingKey(for: profile.normalizedPhone) else {
            lastError = "Use a different test phone number."
            AppHaptics.warning()
            return
        }

        let callID = UUID()
        currentCall = CallSession(id: callID,
                                  remoteUsername: target,
                                  remotePhone: target,
                                  isVideo: video,
                                  direction: .outgoing,
                                  phase: .ringing)
        lastError = ""
        callKit.startOutgoing(uuid: callID, remoteName: target, phoneNumber: target, video: video)
        AppHaptics.medium()

        do {
            let targetRoom = TestIdentity.inboxRoom(for: target)
            let creds = try await credentials(roomName: targetRoom)
            let room = Room(delegate: self)
            try await room.connect(url: creds.serverURL.absoluteString, token: creds.participantToken)
            outgoingSignalRoom = room

            let invite = SignalEnvelope(kind: .callInvite,
                                        callID: callID,
                                        fromUsername: profile.username,
                                        fromPhone: profile.normalizedPhone,
                                        toPhone: target,
                                        isVideo: video)
            try await publish(invite, on: room)
        } catch {
            lastError = error.localizedDescription
            callKit.reportEnded(uuid: callID, reason: .failed)
            await endCallLocally(disconnectSignaling: true)
            AppHaptics.error()
        }
    }

    func requestAnswer() {
        guard let call = currentCall, call.direction == .incoming else { return }
        AppHaptics.success()
        callKit.requestAnswer(uuid: call.id)
    }

    func requestEnd() {
        guard let call = currentCall else { return }
        AppHaptics.heavy()
        callKit.requestEnd(uuid: call.id)
    }

    private func acceptIncomingCall(_ uuid: UUID) async {
        guard var call = currentCall,
              call.id == uuid,
              call.direction == .incoming,
              let profile,
              let inboxRoom else { return }

        call.phase = .connecting
        currentCall = call

        let accept = SignalEnvelope(kind: .callAccept,
                                    callID: call.id,
                                    fromUsername: profile.username,
                                    fromPhone: profile.normalizedPhone,
                                    toPhone: call.remotePhone,
                                    isVideo: call.isVideo)
        do {
            try await publish(accept, on: inboxRoom)
            try await connectCallRoom(call)
        } catch {
            lastError = error.localizedDescription
            callKit.reportEnded(uuid: call.id, reason: .failed)
            await endCallLocally(disconnectSignaling: false)
            AppHaptics.error()
        }
    }

    private func connectCallRoom(_ call: CallSession) async throws {
        let roomName = "bb-call-\(call.id.uuidString.lowercased())"
        let creds = try await credentials(roomName: roomName)
        let room = Room(delegate: self)
        try await room.connect(url: creds.serverURL.absoluteString, token: creds.participantToken)
        activeCallRoom = room

        try await room.localParticipant.setMicrophone(enabled: true)
        microphoneMuted = false
        if call.isVideo {
            try await room.localParticipant.setCamera(enabled: true)
            cameraEnabled = true
        } else {
            cameraEnabled = false
        }

        if var current = currentCall, current.id == call.id {
            current.phase = .active
            currentCall = current
            if current.direction == .outgoing {
                callKit.reportConnected(uuid: current.id)
            }
        }

        if let signalRoom = outgoingSignalRoom {
            await signalRoom.disconnect()
            outgoingSignalRoom = nil
        }
        AppHaptics.success()
    }

    func toggleMute() {
        Task { await setMuted(!microphoneMuted) }
    }

    func setMuted(_ muted: Bool) async {
        guard let room = activeCallRoom else {
            microphoneMuted = muted
            return
        }
        do {
            try await room.localParticipant.setMicrophone(enabled: !muted)
            microphoneMuted = muted
            AppHaptics.selection()
        } catch {
            lastError = error.localizedDescription
            AppHaptics.error()
        }
    }

    func toggleSpeaker() {
        let next = !speakerOn
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(next ? .speaker : .none)
            speakerOn = next
            AppHaptics.selection()
        } catch {
            lastError = error.localizedDescription
            AppHaptics.error()
        }
    }

    func toggleCamera() {
        guard currentCall?.isVideo == true else { return }
        Task {
            guard let room = activeCallRoom else { return }
            do {
                let next = !cameraEnabled
                try await room.localParticipant.setCamera(enabled: next)
                cameraEnabled = next
                AppHaptics.selection()
            } catch {
                lastError = error.localizedDescription
                AppHaptics.error()
            }
        }
    }

    func sendMessage(to rawPhone: String, body rawBody: String) {
        Task { await sendMessageAsync(to: rawPhone, body: rawBody) }
    }

    private func sendMessageAsync(to rawPhone: String, body rawBody: String) async {
        guard let profile, profile.isConfigured else { return }
        let target = TestIdentity.normalizePhone(rawPhone)
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !body.isEmpty else { return }
        guard !profile.liveKitDevelopmentTokenServerID.isEmpty else {
            lastError = "Add your LiveKit development token server ID first."
            return
        }

        do {
            let roomName = TestIdentity.inboxRoom(for: target)
            let creds = try await credentials(roomName: roomName)
            let room = Room(delegate: self)
            try await room.connect(url: creds.serverURL.absoluteString, token: creds.participantToken)
            let envelope = SignalEnvelope(kind: .message,
                                          fromUsername: profile.username,
                                          fromPhone: profile.normalizedPhone,
                                          toPhone: target,
                                          body: body)
            try await publish(envelope, on: room)
            appendMessage(TestMessage(id: envelope.id,
                                      remotePhone: target,
                                      senderName: profile.username,
                                      body: body,
                                      isIncoming: false,
                                      sentAt: envelope.sentAt))
            try? await Task.sleep(for: .milliseconds(250))
            await room.disconnect()
            AppHaptics.light()
        } catch {
            lastError = error.localizedDescription
            AppHaptics.error()
        }
    }

    func conversation(with rawPhone: String) -> [TestMessage] {
        let key = TestIdentity.routingKey(for: rawPhone)
        return messages.filter { TestIdentity.routingKey(for: $0.remotePhone) == key }
    }

    func clearMessages() {
        messages.removeAll()
        persistMessages()
        AppHaptics.warning()
    }

    private func credentials(roomName: String) async throws -> TokenSourceResponse {
        guard let profile else { throw CommunicationError.missingProfile }
        let source = DevelopmentTokenSource(id: profile.liveKitDevelopmentTokenServerID)
        return try await source.fetch(TokenRequestOptions(roomName: roomName,
                                                           participantName: profile.username,
                                                           participantIdentity: profile.deviceIdentity))
    }

    private func publish(_ envelope: SignalEnvelope, on room: Room) async throws {
        let data = try JSONEncoder().encode(envelope)
        try await room.localParticipant.publish(data: data,
                                                options: DataPublishOptions(topic: signalTopic, reliable: true))
    }

    private func receive(data: Data, topic: String) async {
        guard topic == signalTopic,
              let profile,
              let envelope = try? JSONDecoder().decode(SignalEnvelope.self, from: data) else { return }

        let mine = TestIdentity.routingKey(for: envelope.toPhone) == TestIdentity.routingKey(for: profile.normalizedPhone)
        guard mine else { return }

        switch envelope.kind {
        case .callInvite:
            await receiveCallInvite(envelope)
        case .callAccept:
            await receiveCallAccept(envelope)
        case .callReject:
            await receiveCallEndedSignal(envelope, reason: .remoteEnded)
        case .callCancel:
            await receiveCallEndedSignal(envelope, reason: .unanswered)
        case .callEnd:
            await receiveCallEndedSignal(envelope, reason: .remoteEnded)
        case .message:
            receiveMessage(envelope)
        }
    }

    private func receiveCallInvite(_ envelope: SignalEnvelope) async {
        guard let callID = envelope.callID, let profile else { return }

        if currentCall != nil {
            if let inboxRoom {
                let busy = SignalEnvelope(kind: .callReject,
                                          callID: callID,
                                          fromUsername: profile.username,
                                          fromPhone: profile.normalizedPhone,
                                          toPhone: envelope.fromPhone,
                                          body: "busy")
                try? await publish(busy, on: inboxRoom)
            }
            return
        }

        let displayName = envelope.fromUsername.isEmpty ? envelope.fromPhone : envelope.fromUsername
        currentCall = CallSession(id: callID,
                                  remoteUsername: displayName,
                                  remotePhone: envelope.fromPhone,
                                  isVideo: envelope.isVideo,
                                  direction: .incoming,
                                  phase: .ringing)
        callKit.reportIncoming(uuid: callID,
                               remoteName: displayName,
                               phoneNumber: envelope.fromPhone,
                               video: envelope.isVideo)
        AppHaptics.doublePulse()
    }

    private func receiveCallAccept(_ envelope: SignalEnvelope) async {
        guard let callID = envelope.callID,
              var call = currentCall,
              call.id == callID,
              call.direction == .outgoing else { return }

        if !envelope.fromUsername.isEmpty { call.remoteUsername = envelope.fromUsername }
        call.phase = .connecting
        currentCall = call

        do {
            try await connectCallRoom(call)
        } catch {
            lastError = error.localizedDescription
            callKit.reportEnded(uuid: call.id, reason: .failed)
            await endCallLocally(disconnectSignaling: true)
            AppHaptics.error()
        }
    }

    private func receiveCallEndedSignal(_ envelope: SignalEnvelope, reason: CXCallEndedReason) async {
        guard let callID = envelope.callID,
              let call = currentCall,
              call.id == callID else { return }
        callKit.reportEnded(uuid: call.id, reason: reason)
        await endCallLocally(disconnectSignaling: true)
        AppHaptics.soft()
    }

    private func receiveMessage(_ envelope: SignalEnvelope) {
        guard let body = envelope.body, !body.isEmpty else { return }
        let message = TestMessage(id: envelope.id,
                                  remotePhone: envelope.fromPhone,
                                  senderName: envelope.fromUsername,
                                  body: body,
                                  isIncoming: true,
                                  sentAt: envelope.sentAt)
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        appendMessage(message)

        let alertMode = UserDefaults.standard.string(forKey: "messageAlertMode") ?? "sound"
        if UIApplication.shared.applicationState == .active {
            if alertMode != "silent" { AppHaptics.doublePulse() }
        } else {
            let content = UNMutableNotificationContent()
            content.title = envelope.fromUsername.isEmpty ? "New message" : envelope.fromUsername
            content.body = body
            if alertMode == "sound" { content.sound = .default }
            let request = UNNotificationRequest(identifier: envelope.id.uuidString,
                                                content: content,
                                                trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    private func systemEndedCall(_ uuid: UUID) async {
        guard let call = currentCall, call.id == uuid else { return }
        switch (call.direction, call.phase) {
        case (.incoming, .ringing):
            await rejectIncoming(call)
        case (.outgoing, .ringing):
            await cancelOutgoing(call)
        default:
            await hangUp(call)
        }
    }

    private func rejectIncoming(_ call: CallSession) async {
        if let profile, let inboxRoom {
            let reject = SignalEnvelope(kind: .callReject,
                                        callID: call.id,
                                        fromUsername: profile.username,
                                        fromPhone: profile.normalizedPhone,
                                        toPhone: call.remotePhone)
            try? await publish(reject, on: inboxRoom)
        }
        await endCallLocally(disconnectSignaling: false)
    }

    private func cancelOutgoing(_ call: CallSession) async {
        if let profile, let room = outgoingSignalRoom {
            let cancel = SignalEnvelope(kind: .callCancel,
                                        callID: call.id,
                                        fromUsername: profile.username,
                                        fromPhone: profile.normalizedPhone,
                                        toPhone: call.remotePhone)
            try? await publish(cancel, on: room)
        }
        await endCallLocally(disconnectSignaling: true)
    }

    private func hangUp(_ call: CallSession) async {
        if let profile, let room = activeCallRoom {
            let end = SignalEnvelope(kind: .callEnd,
                                     callID: call.id,
                                     fromUsername: profile.username,
                                     fromPhone: profile.normalizedPhone,
                                     toPhone: call.remotePhone)
            try? await publish(end, on: room)
        }
        await endCallLocally(disconnectSignaling: true)
    }

    private func endCallLocally(disconnectSignaling: Bool) async {
        if let room = activeCallRoom { await room.disconnect() }
        activeCallRoom = nil

        if disconnectSignaling, let room = outgoingSignalRoom {
            await room.disconnect()
            outgoingSignalRoom = nil
        }

        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
        localVideoTrack = nil
        remoteVideoTrack = nil
        microphoneMuted = false
        cameraEnabled = false
        speakerOn = false
        currentCall = nil
    }

    private func appendMessage(_ message: TestMessage) {
        messages.append(message)
        messages.sort { $0.sentAt < $1.sentAt }
        if messages.count > 500 { messages.removeFirst(messages.count - 500) }
        persistMessages()
    }

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: messagesDefaultsKey),
              let decoded = try? JSONDecoder().decode([TestMessage].self, from: data) else { return }
        messages = decoded
    }

    private func persistMessages() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messagesDefaultsKey)
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant?,
                          didReceiveData data: Data,
                          forTopic topic: String,
                          encryptionType: EncryptionType) {
        Task { @MainActor [weak self] in
            await self?.receive(data: data, topic: topic)
        }
    }

    nonisolated func room(_ room: Room,
                          participant: LocalParticipant,
                          didPublishTrack publication: LocalTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        Task { @MainActor [weak self] in self?.localVideoTrack = track }
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant,
                          didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        Task { @MainActor [weak self] in self?.remoteVideoTrack = track }
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant,
                          didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.remoteVideoTrack = nil }
    }
}

enum CommunicationError: LocalizedError {
    case missingProfile

    var errorDescription: String? {
        switch self {
        case .missingProfile: return "The test communication profile is not configured."
        }
    }
}

import Foundation
import SwiftUI
import AVFoundation
import LiveKit

enum LiveKitConnectionState: String {
    case disconnected, connecting, connected, reconnecting, error
}

/// Legacy chat bubble model kept for call system lines in Calls pane.
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: String
    let body: String
    let sentAt: Date
    let isLocal: Bool
    let isVoiceNote: Bool
    var voiceNoteURL: URL?

    init(id: UUID = UUID(), sender: String, body: String, sentAt: Date = Date(), isLocal: Bool, isVoiceNote: Bool = false, voiceNoteURL: URL? = nil) {
        self.id = id
        self.sender = sender
        self.body = body
        self.sentAt = sentAt
        self.isLocal = isLocal
        self.isVoiceNote = isVoiceNote
        self.voiceNoteURL = voiceNoteURL
    }
}

/// LiveKit façade — real Room.connect using scaffold token (or POST /v1/livekit/token when available).
@MainActor
final class LiveKitService: ObservableObject {
    @Published private(set) var connectionState: LiveKitConnectionState = .disconnected
    @Published private(set) var roomName = AppConfig.defaultLiveKitRoom
    @Published private(set) var participants: [String] = []
    @Published var messages: [ChatMessage] = []
    @Published var micEnabled = true
    @Published var cameraEnabled = false
    @Published var statusMessage = ""
    @Published var callElapsedSeconds = 0
    @Published var isInCall = false
    @Published var isVideoCall = false
    @Published var isRecordingVoiceNote = false
    @Published var voiceNoteDraftURL: URL?
    @Published private(set) var usingScaffoldToken = false
    @Published private(set) var tokenSourceLabel = "Not connected"
    @Published var peerTypingName: String?
    @Published var activeThreadId: String?

    let threadStore = DMThreadStore.shared

    private var ticker: Timer?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var room: Room?
    private var localIdentity = "you-\(UUID().uuidString.prefix(8))"
    private var localDisplayName = "You"
    private var typingClearTask: Task<Void, Never>?
    private var incomingChunks: [String: (meta: DMEnvelope, parts: [Int: Data])] = [:]
    private var dataConnected = false

    var isConfigured: Bool { AppConfig.isLiveKitConfigured }
    var hasScaffoldToken: Bool { !AppConfig.liveKitScaffoldToken.isEmpty }

    var callTimeLabel: String {
        let m = callElapsedSeconds / 60
        let s = callElapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Token

    /// Prefer production `POST /v1/livekit/token`; fall back to gitignored scaffold token.
    private func resolveAccessToken(room: String) async -> (token: String, scaffold: Bool)? {
        if let server = await fetchServerToken(room: room) {
            return (server, false)
        }
        let scaffold = AppConfig.liveKitScaffoldToken
        guard !scaffold.isEmpty else { return nil }
        return (scaffold, true)
    }

    private func fetchServerToken(room: String) async -> String? {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("v1/livekit/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4
        let body: [String: Any] = ["room": room, "identity": localIdentity, "name": localDisplayName]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["token"] as? String, !token.isEmpty { return token }
                if let token = json["accessToken"] as? String, !token.isEmpty { return token }
            }
        } catch {
            // Endpoint not available yet — scaffold path is expected.
        }
        return nil
    }

    // MARK: - Connect / disconnect

    func connect(room: String = AppConfig.defaultLiveKitRoom, asVideo: Bool = false, dataOnly: Bool = false) async {
        guard isConfigured else {
            statusMessage = "LiveKit URL missing. Add LIVEKIT_URL to Secrets.local.swift."
            connectionState = .error
            AppHaptics.error()
            return
        }

        if dataConnected, roomObj != nil, !dataOnly || isInCall {
            if !dataOnly {
                await publishAV(asVideo: asVideo)
                isInCall = true
                isVideoCall = asVideo
                startTicker()
            }
            return
        }

        roomName = room
        isVideoCall = asVideo && !dataOnly
        cameraEnabled = isVideoCall
        connectionState = .connecting
        CallSounds.callConnecting()
        statusMessage = dataOnly ? "Connecting messaging (TEST SCAFFOLD)…" : "Connecting to \(room)…"
        if !dataOnly { CallSounds.callInitiated() }
        AppHaptics.medium()

        guard let resolved = await resolveAccessToken(room: room) else {
            connectionState = .error
            statusMessage = "No LiveKit token. Add LIVEKIT_TOKEN / liveKitScaffoldToken in Secrets.local.swift (TEST SCAFFOLD), or enable POST /v1/livekit/token."
            AppHaptics.error()
            return
        }

        usingScaffoldToken = resolved.scaffold
        tokenSourceLabel = resolved.scaffold ? "TEST SCAFFOLD token" : "Server token (/v1/livekit/token)"

        do {
            let newRoom = Room()
            newRoom.add(delegate: self)
            try await newRoom.connect(url: AppConfig.liveKitURL, token: resolved.token)
            self.room = newRoom
            dataConnected = true
            connectionState = .connected
            refreshParticipants()
            if !dataOnly {
                await publishAV(asVideo: asVideo)
                isInCall = true
                startTicker()
                statusMessage = usingScaffoldToken
                    ? (asVideo ? "Video call connected — TEST SCAFFOLD" : "Voice call connected — TEST SCAFFOLD")
                    : (asVideo ? "Video call connected" : "Voice call connected")
                appendSystem("Joined room \(roomName) via \(tokenSourceLabel)")
            } else {
                statusMessage = usingScaffoldToken
                    ? "Messaging connected — TEST SCAFFOLD (temporary token)"
                    : "Messaging connected"
            }
            if !dataOnly { CallSounds.callConnected() }
            AppHaptics.success()
        } catch {
            connectionState = .error
            isInCall = false
            dataConnected = false
            self.room = nil
            statusMessage = "Connect failed: \(error.localizedDescription)"
            CallSounds.busyOrFailed()
            AppHaptics.error()
        }
    }

    private var roomObj: Room? { room }

    private func publishAV(asVideo: Bool) async {
        guard let room else { return }
        do {
            try await room.localParticipant.setMicrophone(enabled: micEnabled)
            if asVideo {
                try await room.localParticipant.setCamera(enabled: true)
                cameraEnabled = true
            }
        } catch {
            statusMessage = "Media publish issue: \(error.localizedDescription)"
        }
    }

    func ensureMessagingConnected() async {
        if dataConnected, room != nil { return }
        await connect(dataOnly: true)
    }

    func disconnect() {
        stopTicker()
        Task {
            try? await room?.localParticipant.setMicrophone(enabled: false)
            try? await room?.localParticipant.setCamera(enabled: false)
            await room?.disconnect()
            room = nil
        }
        dataConnected = false
        connectionState = .disconnected
        isInCall = false
        cameraEnabled = false
        participants = []
        callElapsedSeconds = 0
        usingScaffoldToken = false
        tokenSourceLabel = "Not connected"
        statusMessage = "Call ended / disconnected"
        CallSounds.hangup()
        AppHaptics.soft()
        appendSystem("Left the call")
    }

    func endCallKeepMessaging() {
        stopTicker()
        Task {
            try? await room?.localParticipant.setMicrophone(enabled: false)
            try? await room?.localParticipant.setCamera(enabled: false)
        }
        isInCall = false
        isVideoCall = false
        cameraEnabled = false
        callElapsedSeconds = 0
        statusMessage = usingScaffoldToken ? "Call ended — messaging still on TEST SCAFFOLD" : "Call ended — messaging still connected"
        CallSounds.hangup()
        AppHaptics.soft()
        appendSystem("Left the call")
    }

    func toggleMic() {
        micEnabled.toggle()
        Task { try? await room?.localParticipant.setMicrophone(enabled: micEnabled) }
        AppHaptics.selection()
        statusMessage = micEnabled ? "Microphone on" : "Microphone muted"
    }

    func toggleCamera() {
        cameraEnabled.toggle()
        Task { try? await room?.localParticipant.setCamera(enabled: cameraEnabled) }
        AppHaptics.selection()
        statusMessage = cameraEnabled ? "Camera on" : "Camera off"
    }

    private func refreshParticipants() {
        guard let room else {
            participants = []
            return
        }
        var names = [room.localParticipant.name ?? localDisplayName]
        for (_, p) in room.remoteParticipants {
            names.append(p.name ?? p.identity?.stringValue ?? "Peer")
        }
        participants = names
    }

    // MARK: - Legacy call chat helpers

    func sendText(_ text: String, as sender: String = "You") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(sender: sender, body: trimmed, isLocal: true))
        AppHaptics.light()
    }

    private func appendSystem(_ body: String) {
        messages.append(ChatMessage(sender: "System", body: body, isLocal: false))
    }

    // MARK: - Direct messaging

    func sendDMText(_ text: String, thread: DMThread) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await ensureMessagingConnected()
        let messageId = UUID().uuidString
        let msg = DMMessage(
            id: messageId,
            threadId: thread.id,
            senderId: localIdentity,
            senderName: localDisplayName,
            body: trimmed,
            sentAt: Date(),
            isLocal: true,
            kind: .text,
            receipt: .sending
        )
        threadStore.appendMessage(msg, peerId: thread.peerId, peerName: thread.peerName)
        let env = DMEnvelope(
            type: .text,
            threadId: thread.id,
            messageId: messageId,
            senderId: localIdentity,
            senderName: localDisplayName,
            body: trimmed,
            sentAt: Date().timeIntervalSince1970
        )
        let ok = await publishEnvelope(env)
        threadStore.updateReceipt(threadId: thread.id, messageId: messageId, receipt: ok ? .sent : .sending)
        if ok { CallSounds.messageSent() }
        AppHaptics.light()
    }

    func sendTyping(thread: DMThread, isTyping: Bool) async {
        await ensureMessagingConnected()
        let env = DMEnvelope(
            type: .typing,
            threadId: thread.id,
            messageId: UUID().uuidString,
            senderId: localIdentity,
            senderName: localDisplayName,
            isTyping: isTyping,
            sentAt: Date().timeIntervalSince1970
        )
        _ = await publishEnvelope(env)
    }

    func markRead(thread: DMThread) async {
        let unread = thread.messages.filter { !$0.isLocal && $0.receipt != .read }
        guard !unread.isEmpty else { return }
        await ensureMessagingConnected()
        for m in unread {
            threadStore.updateReceipt(threadId: thread.id, messageId: m.id, receipt: .read)
            let env = DMEnvelope(
                type: .receipt,
                threadId: thread.id,
                messageId: m.id,
                senderId: localIdentity,
                senderName: localDisplayName,
                receiptStatus: .read,
                sentAt: Date().timeIntervalSince1970
            )
            _ = await publishEnvelope(env)
        }
    }

    func sendAttachment(fileURL: URL, mime: String, thread: DMThread) async {
        await ensureMessagingConnected()
        let name = fileURL.lastPathComponent
        guard let data = try? Data(contentsOf: fileURL) else {
            statusMessage = "Could not read attachment"
            AppHaptics.error()
            return
        }
        let dest = DMThreadStore.attachmentsDirectory().appendingPathComponent("\(UUID().uuidString)-\(name)")
        try? data.write(to: dest)
        let messageId = UUID().uuidString
        let msg = DMMessage(
            id: messageId,
            threadId: thread.id,
            senderId: localIdentity,
            senderName: localDisplayName,
            body: name,
            sentAt: Date(),
            isLocal: true,
            kind: .attachment,
            receipt: .sending,
            localFilePath: dest.path,
            attachmentMime: mime,
            attachmentName: name
        )
        threadStore.appendMessage(msg, peerId: thread.peerId, peerName: thread.peerName)
        let ok = await publishChunked(
            type: .attachment,
            chunkType: .attachmentChunk,
            messageId: messageId,
            thread: thread,
            body: name,
            attachmentName: name,
            mime: mime,
            data: data
        )
        threadStore.updateReceipt(threadId: thread.id, messageId: messageId, receipt: ok ? .sent : .sending)
        if ok { CallSounds.attachmentSent() }
        AppHaptics.success()
    }

    func startVoiceNote() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vn-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            voiceNoteDraftURL = url
            isRecordingVoiceNote = true
            AppHaptics.rigid()
            CallHaptics.voiceNotePress()
            statusMessage = "Recording voice note — release to send"
        } catch {
            statusMessage = "Could not start voice note: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }

    func cancelVoiceNote() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecordingVoiceNote = false
        if let url = voiceNoteDraftURL {
            try? FileManager.default.removeItem(at: url)
        }
        voiceNoteDraftURL = nil
        statusMessage = "Voice note cancelled"
        AppHaptics.soft()
    }

    func stopVoiceNoteAndSend(thread: DMThread? = nil) {
        audioRecorder?.stop()
        isRecordingVoiceNote = false
        guard let url = voiceNoteDraftURL else { return }
        voiceNoteDraftURL = nil
        let target = thread ?? activeThread.flatMap { threadStore.thread(id: $0) }
        guard let target else {
            messages.append(ChatMessage(sender: "You", body: "Voice note", isLocal: true, isVoiceNote: true, voiceNoteURL: url))
            statusMessage = "Voice note saved locally"
            return
        }
        Task { await sendVoiceNoteFile(url: url, thread: target) }
    }

    private var activeThread: String? { activeThreadId }

    private func sendVoiceNoteFile(url: URL, thread: DMThread) async {
        await ensureMessagingConnected()
        guard let data = try? Data(contentsOf: url) else { return }
        let dest = DMThreadStore.attachmentsDirectory().appendingPathComponent("\(UUID().uuidString).m4a")
        try? data.write(to: dest)
        let messageId = UUID().uuidString
        let msg = DMMessage(
            id: messageId,
            threadId: thread.id,
            senderId: localIdentity,
            senderName: localDisplayName,
            body: "Voice note",
            sentAt: Date(),
            isLocal: true,
            kind: .voiceNote,
            receipt: .sending,
            localFilePath: dest.path,
            attachmentMime: "audio/mp4",
            attachmentName: "voice-note.m4a"
        )
        threadStore.appendMessage(msg, peerId: thread.peerId, peerName: thread.peerName)
        let ok = await publishChunked(
            type: .voiceNote,
            chunkType: .voiceNoteChunk,
            messageId: messageId,
            thread: thread,
            body: "Voice note",
            attachmentName: "voice-note.m4a",
            mime: "audio/mp4",
            data: data
        )
        threadStore.updateReceipt(threadId: thread.id, messageId: messageId, receipt: ok ? .sent : .sending)
        statusMessage = "Voice note sent"
        CallSounds.voiceNoteSent()
        AppHaptics.success()
    }

    func playVoiceNote(_ url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            AppHaptics.light()
        } catch {
            statusMessage = "Could not play voice note"
            AppHaptics.error()
        }
    }

    // MARK: - Data channel

    private func publishEnvelope(_ env: DMEnvelope) async -> Bool {
        guard let room else { return false }
        do {
            let data = try JSONEncoder().encode(env)
            try await room.localParticipant.publish(data: data, options: DataPublishOptions(topic: DMEnvelope.topic, reliable: true))
            return true
        } catch {
            statusMessage = "DM send failed: \(error.localizedDescription)"
            return false
        }
    }

    private func publishChunked(
        type: DMPayloadType,
        chunkType: DMPayloadType,
        messageId: String,
        thread: DMThread,
        body: String,
        attachmentName: String,
        mime: String,
        data: Data
    ) async -> Bool {
        let chunks = stride(from: 0, to: data.count, by: DMEnvelope.maxChunkBytes).map { start -> Data in
            let end = min(start + DMEnvelope.maxChunkBytes, data.count)
            return data.subdata(in: start..<end)
        }
        let header = DMEnvelope(
            type: type,
            threadId: thread.id,
            messageId: messageId,
            senderId: localIdentity,
            senderName: localDisplayName,
            body: body,
            attachmentName: attachmentName,
            attachmentMime: mime,
            attachmentSize: data.count,
            chunkTotal: chunks.count,
            sentAt: Date().timeIntervalSince1970
        )
        guard await publishEnvelope(header) else { return false }
        for (idx, chunk) in chunks.enumerated() {
            let part = DMEnvelope(
                type: chunkType,
                threadId: thread.id,
                messageId: messageId,
                senderId: localIdentity,
                senderName: localDisplayName,
                chunkIndex: idx,
                chunkTotal: chunks.count,
                payloadB64: chunk.base64EncodedString(),
                sentAt: Date().timeIntervalSince1970
            )
            guard await publishEnvelope(part) else { return false }
        }
        return true
    }

    fileprivate func handleIncomingData(_ data: Data, from identity: String?) {
        guard let env = try? JSONDecoder().decode(DMEnvelope.self, from: data) else { return }
        switch env.type {
        case .typing:
            if env.senderId == localIdentity { return }
            if env.isTyping == true {
                if peerTypingName == nil { CallSounds.typingPing() }
                peerTypingName = env.senderName
                typingClearTask?.cancel()
                typingClearTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled { peerTypingName = nil }
                }
            } else {
                peerTypingName = nil
            }
        case .receipt:
            if let status = env.receiptStatus {
                threadStore.updateReceipt(threadId: env.threadId, messageId: env.messageId, receipt: status)
                if status == .delivered { CallSounds.delivered() }
                if status == .read { CallSounds.read() }
            }
        case .text:
            guard env.senderId != localIdentity else { return }
            let msg = DMMessage(
                id: env.messageId,
                threadId: env.threadId,
                senderId: env.senderId,
                senderName: env.senderName,
                body: env.body ?? "",
                sentAt: Date(timeIntervalSince1970: env.sentAt),
                isLocal: false,
                kind: .text,
                receipt: .delivered
            )
            threadStore.appendMessage(msg, peerId: env.senderId, peerName: env.senderName)
            CallSounds.inboundNotification()
            Task {
                let ack = DMEnvelope(
                    type: .receipt,
                    threadId: env.threadId,
                    messageId: env.messageId,
                    senderId: localIdentity,
                    senderName: localDisplayName,
                    receiptStatus: .delivered,
                    sentAt: Date().timeIntervalSince1970
                )
                _ = await publishEnvelope(ack)
            }
        case .attachment, .voiceNote:
            incomingChunks[env.messageId] = (env, [:])
            if (env.chunkTotal ?? 0) == 0 {
                finalizeIncomingFile(messageId: env.messageId)
            }
        case .attachmentChunk, .voiceNoteChunk:
            guard var entry = incomingChunks[env.messageId],
                  let idx = env.chunkIndex,
                  let b64 = env.payloadB64,
                  let part = Data(base64Encoded: b64) else { return }
            entry.parts[idx] = part
            incomingChunks[env.messageId] = entry
            if entry.parts.count == (entry.meta.chunkTotal ?? entry.parts.count) {
                finalizeIncomingFile(messageId: env.messageId)
            }
        }
        _ = identity
    }

    private func finalizeIncomingFile(messageId: String) {
        guard let entry = incomingChunks.removeValue(forKey: messageId) else { return }
        let total = entry.meta.chunkTotal ?? 0
        var assembled = Data()
        if total > 0 {
            for i in 0..<total {
                guard let part = entry.parts[i] else { return }
                assembled.append(part)
            }
        }
        let name = entry.meta.attachmentName ?? (entry.meta.type == .voiceNote ? "voice-note.m4a" : "file")
        let dest = DMThreadStore.attachmentsDirectory().appendingPathComponent("\(messageId)-\(name)")
        try? assembled.write(to: dest)
        let kind: DMMessage.Kind = (entry.meta.type == .voiceNote || entry.meta.type == .voiceNoteChunk) ? .voiceNote : .attachment
        let msg = DMMessage(
            id: messageId,
            threadId: entry.meta.threadId,
            senderId: entry.meta.senderId,
            senderName: entry.meta.senderName,
            body: entry.meta.body ?? name,
            sentAt: Date(timeIntervalSince1970: entry.meta.sentAt),
            isLocal: false,
            kind: kind,
            receipt: .delivered,
            localFilePath: dest.path,
            attachmentMime: entry.meta.attachmentMime,
            attachmentName: name
        )
        threadStore.appendMessage(msg, peerId: entry.meta.senderId, peerName: entry.meta.senderName)
        Task {
            let ack = DMEnvelope(
                type: .receipt,
                threadId: entry.meta.threadId,
                messageId: messageId,
                senderId: localIdentity,
                senderName: localDisplayName,
                receiptStatus: .delivered,
                sentAt: Date().timeIntervalSince1970
            )
            _ = await publishEnvelope(ack)
        }
    }

    // MARK: - Call timer

    private func startTicker() {
        stopTicker()
        callElapsedSeconds = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.callElapsedSeconds += 1 }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

extension LiveKitService: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                self.connectionState = .connected
                self.refreshParticipants()
            case .connecting, .reconnecting:
                self.connectionState = connectionState == .reconnecting ? .reconnecting : .connecting
            case .disconnecting:
                self.connectionState = .connecting
            case .disconnected:
                self.connectionState = .disconnected
                self.dataConnected = false
            @unknown default:
                break
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        Task { @MainActor in
            self.handleIncomingData(data, from: participant?.identity?.stringValue)
        }
    }
}

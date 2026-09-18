import Foundation
import SwiftUI
import AVFoundation

enum LiveKitConnectionState: String {
    case disconnected, connecting, connected, reconnecting, error
}

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

/// Protocol-based LiveKit façade — UI works with stubs; SPM LiveKit client plugs in behind `#if canImport(LiveKit)`.
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

    private var ticker: Timer?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    @Published var isRecordingVoiceNote = false
    @Published var voiceNoteDraftURL: URL?

    var isConfigured: Bool { AppConfig.isLiveKitConfigured }

    func connect(room: String = AppConfig.defaultLiveKitRoom, asVideo: Bool = false) async {
        guard isConfigured else {
            statusMessage = "LiveKit URL missing. Add LIVEKIT_URL to Secrets.local.swift."
            connectionState = .error
            AppHaptics.error()
            return
        }
        roomName = room
        isVideoCall = asVideo
        cameraEnabled = asVideo
        connectionState = .connecting
        statusMessage = "Connecting to \(room)…"
        AppHaptics.medium()

        // #if canImport(LiveKit)
        // let room = Room(); try await room.connect(url: AppConfig.liveKitURL, token: token)
        // #endif

        try? await Task.sleep(for: .milliseconds(700))
        connectionState = .connected
        isInCall = true
        participants = ["You", "Studio"]
        statusMessage = asVideo ? "Video call connected" : "Voice call connected"
        startTicker()
        AppHaptics.success()
        appendSystem("Joined room \(room)")
    }

    func disconnect() {
        stopTicker()
        connectionState = .disconnected
        isInCall = false
        cameraEnabled = false
        participants = []
        callElapsedSeconds = 0
        statusMessage = "Call ended"
        AppHaptics.soft()
        appendSystem("Left the call")
    }

    func toggleMic() {
        micEnabled.toggle()
        AppHaptics.selection()
        statusMessage = micEnabled ? "Microphone on" : "Microphone muted"
    }

    func toggleCamera() {
        cameraEnabled.toggle()
        AppHaptics.selection()
        statusMessage = cameraEnabled ? "Camera on" : "Camera off"
    }

    func sendText(_ text: String, as sender: String = "You") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(sender: sender, body: trimmed, isLocal: true))
        AppHaptics.light()
        // LiveKit data channel / text stream publishes here in production.
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
            statusMessage = "Recording voice note"
        } catch {
            statusMessage = "Could not start voice note: \(error.localizedDescription)"
            AppHaptics.error()
        }
    }

    func stopVoiceNoteAndSend(as sender: String = "You") {
        audioRecorder?.stop()
        isRecordingVoiceNote = false
        guard let url = voiceNoteDraftURL else { return }
        messages.append(ChatMessage(sender: sender, body: "Voice note", isLocal: true, isVoiceNote: true, voiceNoteURL: url))
        voiceNoteDraftURL = nil
        statusMessage = "Voice note sent"
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

    private func appendSystem(_ body: String) {
        messages.append(ChatMessage(sender: "System", body: body, isLocal: false))
    }

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

    var callTimeLabel: String {
        let m = callElapsedSeconds / 60
        let s = callElapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

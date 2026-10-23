import Foundation
import SwiftUI
import AVFoundation
import UIKit

/// Blue verified checkmark. VoiceOver reads it as "Verified".
struct VerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(.white, .blue)
            .imageScale(.small)
            .accessibilityLabel("Verified")
    }
}

/// Records voice messages as AAC (m4a) on this iPhone.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileURL: URL?

    func start() async -> Bool {
        guard !isRecording else { return true }
        let granted = await withCheckedContinuation { c in AVAudioApplication.requestRecordPermission { c.resume(returning: $0) } }
        guard granted else {
            UIAccessibility.post(notification: .announcement, argument: "Microphone access is off. Turn it on in Settings to record voice messages.")
            return false
        }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? s.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: settings), r.record() else { return false }
        recorder = r; fileURL = url; isRecording = true; elapsed = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIAccessibility.post(notification: .announcement, argument: "Recording")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
        return true
    }

    /// Stops and returns the file plus its duration, or nil when cancelled / too short.
    func stop(cancel: Bool) -> (URL, Double)? {
        guard isRecording, let r = recorder, let url = fileURL else { return nil }
        let d = r.currentTime
        r.stop(); timer?.invalidate(); timer = nil; isRecording = false; recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if cancel || d < 0.6 {
            try? FileManager.default.removeItem(at: url)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: cancel ? "Recording cancelled" : "Too short, not sent")
            return nil
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        return (url, d)
    }
}

/// Sends a recorded voice note: encrypted attachment + E2EE "voice" payload when the server supports it,
/// otherwise an on-device transcript as a plaintext message so nothing is lost.
@MainActor
enum VoiceSender {
    static let cacheDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Seals and uploads audio; returns the media descriptor, or nil when attachments aren't on the server yet.
    static func upload(_ data: Data, duration: Double, transcript: String?, listenOnce: Bool, chat: ChatRef) async -> E2EEPayload.Media? {
        do {
            let sealed = try AttachmentCrypto.seal(data)
            let slot = try await SecurityAPI.createAttachment(size: sealed.blob.count, chat: chat)
            var req = URLRequest(url: slot.url); req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.upload(for: req, from: sealed.blob)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            try? data.write(to: cacheDir.appendingPathComponent(slot.attachmentID + ".m4a"))
            return E2EEPayload.Media(url: nil, attachment_id: slot.attachmentID, key: sealed.key.base64EncodedString(),
                nonce: sealed.baseNonce.base64EncodedString(), sha256: sealed.sha256.base64EncodedString(), mime: "audio/mp4",
                size: sealed.plainSize, filename: "voice.m4a", caption: nil, view_once: listenOnce ? true : nil, duration: duration,
                transcript: transcript, alt: nil)
        } catch { return nil }
    }

    static func send(file: URL, duration: Double, handle: String, chat: ChatRef, comms: ProductionCommunicationsService, listenOnce: Bool = false) async -> Bool {
        guard let data = try? Data(contentsOf: file) else { return false }
        let transcript = await Transcriber.transcribe(fileURL: file)
        defer { try? FileManager.default.removeItem(at: file) }
        if let media = await upload(data, duration: duration, transcript: transcript, listenOnce: listenOnce, chat: chat) {
            let payload = E2EEPayload(t: "voice", media: media)
            var ok = false
            if case .group(let gid) = chat { ok = (try? await E2EEService.shared.sendGroup(id: gid, payload: payload, viewOnce: listenOnce)) == true }
            else { ok = (try? await E2EEService.shared.sendDM(handle: handle, payload: payload, viewOnce: listenOnce, chatKey: chat.key)) != nil }
            if ok {
                CallSounds.messageSent()
                UIAccessibility.post(notification: .announcement, argument: "Sent")
                return true
            }
        }
        // Fallback: the server can't store voice yet, or the chat isn't end-to-end encrypted. Send the transcript.
        let text = "🎤 Voice message (\(Int(duration.rounded())) s, transcribed on my iPhone): " + (transcript ?? "[couldn't transcribe]")
        var ok = false
        if case .group(let gid) = chat { ok = (try? await BlindbanditAPI.sendGroupMessage(id: gid, body: text)) != nil }
        else { ok = await comms.sendMessage(recipient: handle, body: text) != nil }
        UIAccessibility.post(notification: .announcement, argument: ok ? "Sent as a transcript. Voice audio needs a server update." : "Voice message not sent")
        return ok
    }
}

/// Composer mic: press and hold to record, release to send, slide left to cancel.
/// VoiceOver: double-tap and hold works (passthrough to the gesture). A plain double-tap toggles: first starts, second sends.
/// Custom actions: "Cancel recording", "Send recording".
struct VoiceMicButton: View {
    let handle: String
    let chat: ChatRef
    @EnvironmentObject private var comms: ProductionCommunicationsService
    @ObservedObject var recorder: VoiceRecorder
    @State private var dragX: CGFloat = 0
    @State private var starting = false
    @AppStorage("voice.listenOnce") private var listenOnce = false

    var body: some View {
        let cancelling = dragX < -70
        Image(systemName: recorder.isRecording ? (cancelling ? "xmark.circle.fill" : "mic.circle.fill") : "mic.fill")
            .font(.title2)
            .foregroundStyle(recorder.isRecording ? (cancelling ? Color.gray : Color.red) : Color.accentColor)
            .frame(width: Brand.minTouch, height: Brand.minTouch)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if recorder.isRecording {
                    Text(cancelling ? "Release to cancel" : "\(Int(recorder.elapsed)) s  ‹ slide to cancel")
                        .font(.caption2).padding(4).background(.regularMaterial, in: Capsule())
                        .fixedSize().offset(x: -60, y: -30).accessibilityHidden(true)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragX = v.translation.width
                        if !recorder.isRecording && !starting { starting = true; Task { _ = await recorder.start(); starting = false } }
                    }
                    .onEnded { _ in let cancel = dragX < -70; dragX = 0; finish(cancel: cancel) }
            )
            .accessibilityElement()
            .accessibilityLabel(recorder.isRecording ? "Recording, \(Int(recorder.elapsed)) seconds" : "Record voice message")
            .accessibilityHint(recorder.isRecording ? "Double tap to send. Swipe up or down for Cancel recording." :
                "Double tap and hold to record, lift to send. Or double tap to start, and double tap again to send.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if recorder.isRecording { finish(cancel: false) } else { Task { _ = await recorder.start() } }
            }
            .accessibilityAction(named: "Cancel recording") { finish(cancel: true) }
            .accessibilityAction(named: "Send recording") { finish(cancel: false) }
            .accessibilityAction(named: listenOnce ? "Turn off listen once" : "Turn on listen once") {
                listenOnce.toggle(); UIAccessibility.post(notification: .announcement, argument: listenOnce ? "Listen once on" : "Listen once off")
            }
            .disabled(handle.isEmpty && !chat.isGroup)
    }

    private func finish(cancel: Bool) {
        guard let (url, d) = recorder.stop(cancel: cancel) else { return }
        let once = listenOnce
        Task { _ = await VoiceSender.send(file: url, duration: d, handle: handle, chat: chat, comms: comms, listenOnce: once) }
    }
}

/// Voice-note player in a bubble with 1x / 1.5x / 2x.
@MainActor
final class VoicePlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var rate: Float = 1
    @Published var loading = false
    @Published var consumed = false
    private var player: AVAudioPlayer?
    var onFinish: (() -> Void)?

    func toggle(media: E2EEPayload.Media) async {
        if playing { player?.pause(); playing = false; return }
        if player == nil {
            loading = true; defer { loading = false }
            guard let data = await Self.load(media) else {
                UIAccessibility.post(notification: .announcement, argument: "Couldn't load this voice message"); return
            }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(data: data)
            player?.enableRate = true
            player?.delegate = self
        }
        player?.rate = rate
        playing = player?.play() ?? false
    }

    func cycleRate() {
        rate = rate == 1 ? 1.5 : (rate == 1.5 ? 2 : 1)
        player?.rate = rate
        UIAccessibility.post(notification: .announcement, argument: "Speed \(Self.rateLabel(rate))")
    }

    static func rateLabel(_ r: Float) -> String { r == 1 ? "1x" : (r == 1.5 ? "1.5x" : "2x") }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false; self.onFinish?() }
    }

    static func load(_ m: E2EEPayload.Media) async -> Data? {
        if let id = m.attachment_id, let d = try? Data(contentsOf: VoiceSender.cacheDir.appendingPathComponent(id + ".m4a")) { return d }
        guard let key = Data(base64Encoded: m.key), let nonceS = m.nonce, let nonce = Data(base64Encoded: nonceS) else { return nil }
        var url: URL?
        if let id = m.attachment_id { url = try? await SecurityAPI.attachmentURL(id: id) } else if let s = m.url { url = URL(string: s) }
        guard let url, let (blob, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let plain = try? AttachmentCrypto.open(blob, key: key, baseNonce: nonce, plainSize: m.size ?? blob.count, sha256: Data(base64Encoded: m.sha256)) else { return nil }
        if let id = m.attachment_id, m.view_once != true { try? plain.write(to: VoiceSender.cacheDir.appendingPathComponent(id + ".m4a")) }
        return plain
    }
}

struct VoiceBubble: View {
    let media: E2EEPayload.Media
    let from: String
    var msgID: String = ""
    @StateObject private var model = VoicePlayerModel()
    @State private var opened = false

    var body: some View {
        let once = media.view_once == true
        let gone = once && (opened || LocalMessageStore.shared.snapshot.openedViewOnce.contains(msgID))
        VStack(alignment: .leading, spacing: 6) {
            if gone && !model.playing {
                Label("Listen-once voice message, played", systemImage: "ear.badge.checkmark")
            } else {
                HStack(spacing: 12) {
                    Button { Task { model.onFinish = { markOpened(once) }; await model.toggle(media: media) } } label: {
                        Image(systemName: model.loading ? "hourglass" : (model.playing ? "pause.circle.fill" : "play.circle.fill")).font(.largeTitle)
                    }
                    .accessibilityLabel(model.playing ? "Pause voice message" :
                        "Play \(once ? "listen-once " : "")voice message from \(from), \(Int((media.duration ?? 0).rounded())) seconds")
                    Button(VoicePlayerModel.rateLabel(model.rate)) { model.cycleRate() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Playback speed \(VoicePlayerModel.rateLabel(model.rate))")
                        .accessibilityHint("Double tap to change between 1x, 1.5x and 2x")
                    Text("\(Int((media.duration ?? 0).rounded())) s").font(.caption).accessibilityHidden(true)
                }
                if !once, let t = media.transcript, !t.isEmpty {
                    Text(t).font(.footnote).foregroundStyle(.secondary).accessibilityLabel("Transcript: \(t)")
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func markOpened(_ once: Bool) {
        guard once, !msgID.isEmpty else { return }
        opened = true
        LocalMessageStore.shared.mutate { $0.openedViewOnce.insert(msgID) }
        if let id = media.attachment_id { try? FileManager.default.removeItem(at: VoiceSender.cacheDir.appendingPathComponent(id + ".m4a")) }
    }
}

extension VoiceRecorder {
    /// Rotor entry on the text field: first use starts recording, second sends.
    func toggleSend(handle: String, chat: ChatRef, comms: ProductionCommunicationsService) async {
        if isRecording {
            guard let (url, d) = stop(cancel: false) else { return }
            _ = await VoiceSender.send(file: url, duration: d, handle: handle, chat: chat, comms: comms,
                                       listenOnce: UserDefaults.standard.bool(forKey: "voice.listenOnce"))
        } else { _ = await start() }
    }
}

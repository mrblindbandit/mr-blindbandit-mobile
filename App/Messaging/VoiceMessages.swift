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
            // Cache the plaintext first so my own note plays from this iPhone even while the upload is still running.
            let local = VoiceSender.cacheDir.appendingPathComponent(slot.attachmentID + ".m4a")
            try? data.write(to: local)
            var req = URLRequest(url: slot.url); req.httpMethod = "PUT"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.upload(for: req, from: sealed.blob)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { try? FileManager.default.removeItem(at: local); return nil }
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

/// One shared voice-note player for every bubble: tap to play / pause, speaker by default, earpiece when held to the ear,
/// ducks other audio, keeps playing on the lock screen, and auto-plays the next unplayed received voice message.
@MainActor
final class VoicePlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayback()
    struct Item: Equatable { let id: String; let media: E2EEPayload.Media; let from: String; let mine: Bool
        static func == (l: Item, r: Item) -> Bool { l.id == r.id } }

    @Published private(set) var currentID: String?
    @Published private(set) var playing = false
    @Published private(set) var loadingID: String?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var rate: Float = { let r = UserDefaults.standard.float(forKey: "voice.rate"); return r == 0 ? 1 : r }()
    @Published private(set) var played: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "voice.played") ?? [])
    private var player: AVAudioPlayer?
    private var order: [Item] = []
    private var timer: Timer?
    var onConsumed: [String: () -> Void] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in VoicePlayback.shared.routeForProximity() }
        }
    }

    /// Bubbles register in on-screen order so "next unplayed" follows the conversation.
    func register(_ item: Item) {
        if let i = order.firstIndex(of: item) { order[i] = item } else { order.append(item) }
    }

    func isCurrent(_ id: String) -> Bool { currentID == id }

    func toggle(_ item: Item) async {
        if currentID == item.id, let player {
            if playing { pause() } else { player.rate = rate; playing = player.play(); startTimer(); announce("Playing") }
            return
        }
        await play(item)
    }

    func pause() {
        player?.pause(); playing = false; timer?.invalidate()
        announce("Paused")
    }

    func play(_ item: Item) async {
        stop(deactivate: false)
        register(item)
        loadingID = item.id
        let data = await VoicePlayerModel.load(item.media)
        loadingID = nil
        guard let data, let p = try? AVAudioPlayer(data: data) else { announce("Couldn't load this voice message"); return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
        try? s.setActive(true)
        UIDevice.current.isProximityMonitoringEnabled = true
        routeForProximity()
        p.enableRate = true; p.rate = rate; p.delegate = self; p.prepareToPlay()
        player = p; currentID = item.id; elapsed = 0
        playing = p.play()
        startTimer()
        markPlayed(item)
    }

    func skip(_ seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(player.duration - 0.1, player.currentTime + seconds))
        elapsed = player.currentTime
        announce(Self.clock(elapsed))
    }

    func setRate(_ r: Float) {
        rate = r; player?.rate = r
        UserDefaults.standard.set(r, forKey: "voice.rate")
        announce("Speed \(VoicePlayerModel.rateLabel(r))")
    }

    func cycleRate() { setRate(rate == 1 ? 1.5 : (rate == 1.5 ? 2 : 1)) }

    func stop(deactivate: Bool = true) {
        player?.stop(); player = nil; playing = false; currentID = nil; elapsed = 0; timer?.invalidate()
        if deactivate {
            UIDevice.current.isProximityMonitoringEnabled = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func routeForProximity() {
        guard player != nil else { return }
        let near = UIDevice.current.proximityState
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(near ? .none : .speaker)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in let me = VoicePlayback.shared; me.elapsed = me.player?.currentTime ?? 0 }
        }
    }

    private func markPlayed(_ item: Item) {
        guard !item.mine else { return }
        played.insert(item.id)
        UserDefaults.standard.set(Array(played.suffix(2000)), forKey: "voice.played")
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        guard let id = currentID, let idx = order.firstIndex(where: { $0.id == id }) else { stop(); return }
        onConsumed[id]?()
        let next = order[(idx + 1)...].first { !$0.mine && !played.contains($0.id) &&
            !($0.media.view_once == true && LocalMessageStore.shared.snapshot.openedViewOnce.contains($0.id)) }
        if let next {
            announce("Next voice message from \(next.from)")
            Task { try? await Task.sleep(nanoseconds: 700_000_000); await self.play(next) }
        } else { stop() }
    }

    private func announce(_ s: String) { UIAccessibility.post(notification: .announcement, argument: s) }
    static func clock(_ t: TimeInterval) -> String { let s = max(0, Int(t.rounded())); return "\(s / 60):" + String(format: "%02d", s % 60) }
}

@MainActor
enum VoicePlayerModel {
    static func rateLabel(_ r: Float) -> String { r == 1 ? "1x" : (r == 1.5 ? "1.5x" : "2x") }

    static func load(_ m: E2EEPayload.Media) async -> Data? {
        if let id = m.attachment_id, let d = try? Data(contentsOf: VoiceSender.cacheDir.appendingPathComponent(id + ".m4a")) { return d }
        if let s = m.url, let u = URL(string: s), u.isFileURL, let d = try? Data(contentsOf: u) { return d }
        guard let key = Data(base64Encoded: m.key), let nonceS = m.nonce, let nonce = Data(base64Encoded: nonceS) else { return nil }
        var url: URL?
        if let id = m.attachment_id { url = try? await SecurityAPI.attachmentURL(id: id) } else if let s = m.url { url = URL(string: s) }
        guard let url, let (blob, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let plain = try? AttachmentCrypto.open(blob, key: key, baseNonce: nonce, plainSize: m.size ?? blob.count, sha256: Data(base64Encoded: m.sha256)) else { return nil }
        if let id = m.attachment_id, m.view_once != true { try? plain.write(to: VoiceSender.cacheDir.appendingPathComponent(id + ".m4a")) }
        return plain
    }
}

/// The whole bubble is one VoiceOver element: double tap plays / pauses; rotor actions for speed, skip and transcript.
struct VoiceBubble: View {
    let media: E2EEPayload.Media
    let from: String
    var msgID: String = ""
    @ObservedObject private var center = VoicePlayback.shared
    @State private var opened = false
    @State private var showTranscript = false
    @State private var cloudTranscript: String?

    private var mine: Bool { from == "You" }
    private var item: VoicePlayback.Item { .init(id: msgID.isEmpty ? (media.attachment_id ?? UUID().uuidString) : msgID, media: media, from: from, mine: mine) }
    private var duration: String { VoicePlayback.clock(media.duration ?? 0) }

    var body: some View {
        let once = media.view_once == true
        let current = center.isCurrent(item.id)
        let gone = once && (opened || LocalMessageStore.shared.snapshot.openedViewOnce.contains(msgID)) && !current
        Group {
            if gone {
                Label("Listen-once voice message, played", systemImage: "ear.badge.checkmark")
                    .padding(10)
                    .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
            } else {
                content(once: once, current: current)
            }
        }
        .onAppear { if !gone { center.register(item) } }
        .sheet(isPresented: $showTranscript) {
            NavigationStack {
                ScrollView { Text(cloudTranscript ?? media.transcript ?? "No transcript for this voice message.").padding().frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("Transcript")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTranscript = false } } }
            }
        }
    }

    private func content(once: Bool, current: Bool) -> some View {
        let isPlaying = current && center.playing
        let loading = center.loadingID == item.id
        let unplayed = !mine && !center.played.contains(item.id)
        let total: Double = max(media.duration ?? 1, 0.1)
        let progress: Double = current ? min(center.elapsed, total) : 0
        let timeText: String = current ? VoicePlayback.clock(center.elapsed) + " / " + duration : duration
        let icon: String = loading ? "hourglass" : (isPlaying ? "pause.circle.fill" : "play.circle.fill")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress, total: total)
                    Text(timeText).font(.caption)
                }
                Text(VoicePlayerModel.rateLabel(center.rate)).font(.caption.bold())
                if unplayed { Circle().fill(Brand.gold).frame(width: 8, height: 8) }
            }
            if !once, let t = media.transcript, !t.isEmpty {
                Text(t).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(10)
        .frame(minWidth: 200, alignment: .leading)
        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { toggle(once) }
        .modifier(VoiceBubbleAccessibility(label: axLabel(once: once, unplayed: unplayed), value: axValue(current: current, isPlaying: isPlaying),
                                           hint: isPlaying ? "Double tap to pause" : (once ? "Double tap to play. It can be heard only once." : "Double tap to play"),
                                           isPlaying: isPlaying, current: current, once: once,
                                           toggle: { toggle(once) }, transcript: { openTranscript() }))
    }

    /// Uses the on-device transcript; when there isn't one (or it's a long note) and Cloud AI Whisper is on,
    /// transcribes on the server only because the user asked for this message's transcript.
    private func openTranscript() {
        let long = (media.duration ?? 0) > 60
        guard CloudAI.isOn(.transcribe), cloudTranscript == nil, (media.transcript ?? "").isEmpty || long else { showTranscript = true; return }
        UIAccessibility.post(notification: .announcement, argument: "Transcribing with Cloud AI")
        Task {
            if let d = await VoicePlayerModel.load(media), case .ok(let t) = await CloudAI.transcribe(d) { cloudTranscript = t }
            showTranscript = true
        }
    }

    private func axLabel(once: Bool, unplayed: Bool) -> String {
        let kind = once ? "Listen-once voice message" : "Voice message"
        return kind + " from " + from + ", " + duration + (unplayed ? ", unplayed" : "")
    }

    private func axValue(current: Bool, isPlaying: Bool) -> String {
        guard current else { return "" }
        let state = isPlaying ? "Playing" : "Paused"
        return state + ", " + VoicePlayback.clock(center.elapsed) + " of " + duration + ", speed " + VoicePlayerModel.rateLabel(center.rate)
    }

    private func toggle(_ once: Bool) {
        let it = item
        center.onConsumed[it.id] = { markOpened(once) }
        Task { await center.toggle(it) }
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

struct VoiceBubbleAccessibility: ViewModifier {
    let label: String, value: String, hint: String
    let isPlaying: Bool, current: Bool, once: Bool
    let toggle: () -> Void, transcript: () -> Void
    func body(content: Content) -> some View {
        let c = VoicePlayback.shared
        return content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAddTraits([.isButton, .startsMediaSession])
            .accessibilityAction { toggle() }
            .accessibilityActions {
                Button(isPlaying ? "Pause" : "Play") { toggle() }
                Button("Speed 1x") { c.setRate(1) }
                Button("Speed 1.5x") { c.setRate(1.5) }
                Button("Speed 2x") { c.setRate(2) }
                Button("Skip back 5 seconds") { if current { c.skip(-5) } }
                Button("Skip ahead 5 seconds") { if current { c.skip(5) } }
                Button("Show transcript") {
                    if once { UIAccessibility.post(notification: .announcement, argument: "Listen-once messages don't show a transcript") } else { transcript() }
                }
            }
    }
}

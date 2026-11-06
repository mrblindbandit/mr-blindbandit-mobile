import AVKit
import SwiftUI

enum BitePlaybackMode: String {
    case video
    case audio
}

enum BiteFeedPolicy {
    static let hiddenStates: Set<String> = ["private", "draft", "deleted", "blocked", "hidden", "reported"]

    /// Missing visibility stays in the shared feed. Explicit private states do not.
    static func includeInSharedFeed(visibility: String?, status: String?) -> Bool {
        let vis = visibility?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let state = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if hiddenStates.contains(vis) || hiddenStates.contains(state) { return false }
        return true
    }

    static func include(_ item: BiteItem) -> Bool {
        includeInSharedFeed(visibility: item.visibility, status: item.status)
    }

    /// Offscreen rows and active calls never emit Bite audio.
    static func shouldEmitSound(visible: Bool, soundEnabled: Bool, inCall: Bool) -> Bool {
        visible && soundEnabled && !inCall
    }
}

/// Native looping player. Starts paused and silent. Sound is a separate control from the picture.
struct BiteLoopingPlayer: View {
    let url: URL
    var inCall: Bool
    @State private var player = AVPlayer()
    @State private var soundOn = false
    @State private var mode: BitePlaybackMode = .video
    @State private var playing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mode == .video {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .accessibilityLabel(playing ? "Bite video, playing, \(soundOn ? "sound on" : "silent")" : "Bite video, paused")
            } else {
                Text(soundOn && !inCall ? "Audio only. The picture is hidden." : "Audio only. Turn sound on to hear this Bite.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Audio mode")
            }
            HStack(spacing: 12) {
                Button(playing ? "Pause" : "Play") { togglePlay() }
                    .accessibilityHint(playing ? "Pauses this Bite" : "Plays this Bite from the start of the loop")
                Button(soundOn ? "Sound off" : "Sound on") { toggleSound() }
                    .disabled(inCall)
                    .accessibilityHint(inCall ? "Unavailable during a call" : "Turns Bite sound on or off")
                Button(mode == .video ? "Audio mode" : "Video mode") { toggleMode() }
            }
            .buttonStyle(.bordered)
            if inCall {
                Text("Call audio stays in charge. Bite sound stays off until the call ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: prepare)
        .onDisappear(perform: pause)
        .onChange(of: inCall) { _, calling in
            if calling { soundOn = false; applySound() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item == player.currentItem else { return }
            player.seek(to: .zero)
            if playing { player.play() }
        }
    }

    private func prepare() {
        if player.currentItem == nil {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        player.volume = 0
        player.pause()
        playing = false
    }

    private func togglePlay() {
        if playing {
            pause()
        } else {
            applySound()
            player.play()
            playing = true
            UIAccessibility.post(notification: .announcement, argument: soundOn && !inCall ? "Playing with sound" : "Playing silently")
        }
    }

    private func pause() {
        player.pause()
        playing = false
    }

    private func toggleSound() {
        guard !inCall else {
            UIAccessibility.post(notification: .announcement, argument: "Bite sound stays off during a call")
            return
        }
        soundOn.toggle()
        applySound()
        UIAccessibility.post(notification: .announcement, argument: soundOn ? "Bite sound on" : "Bite sound off")
    }

    private func toggleMode() {
        mode = mode == .video ? .audio : .video
        UIAccessibility.post(notification: .announcement, argument: mode == .audio ? "Audio mode" : "Video mode")
    }

    private func applySound() {
        let audible = BiteFeedPolicy.shouldEmitSound(visible: true, soundEnabled: soundOn, inCall: inCall)
        player.volume = audible ? 1 : 0
    }
}

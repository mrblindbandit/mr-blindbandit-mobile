import Foundation
import AVFoundation
import Speech
import UIKit
import LiveKit

/// Live call captions: the other people's audio from LiveKit is fed into on-device speech recognition and each
/// finished phrase is announced to VoiceOver (and shown on screen).
final class LiveCaptioner: NSObject, AudioRenderer, @unchecked Sendable {
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    private var lastSpoken = ""
    private var restartWork: DispatchWorkItem?
    var onCaption: (@MainActor (String) -> Void)?

    func begin() {
        guard let recognizer, recognizer.isAvailable else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let r = result {
                let text = r.bestTranscription.formattedString
                self.scheduleFlush(text, final: r.isFinal)
            }
            if error != nil || result?.isFinal == true { self.restart() }
        }
    }

    private func scheduleFlush(_ text: String, final: Bool) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush(text) }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (final ? 0 : 1.2), execute: work)
    }

    private func flush(_ text: String) {
        let new = text.hasPrefix(lastSpoken) ? String(text.dropFirst(lastSpoken.count)) : text
        lastSpoken = text
        let t = new.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let cb = onCaption
        Task { @MainActor in cb?(t) }
    }

    private func restart() {
        request?.endAudio(); task?.cancel(); task = nil; lastSpoken = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in if self?.request != nil { self?.begin() } }
    }

    func end() { request?.endAudio(); request = nil; task?.cancel(); task = nil }

    func render(pcmBuffer: AVAudioPCMBuffer) { request?.append(pcmBuffer) }
}

extension ProductionCommunicationsService {
    /// Turns live captions on for every remote audio track in the current call.
    func setCaptions(_ on: Bool, tracks: [RemoteAudioTrack]) {
        if on {
            Task {
                let ok = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
                guard ok else { UIAccessibility.post(notification: .announcement, argument: "Captions need speech recognition permission"); return }
                let cap = LiveCaptioner()
                cap.onCaption = { [weak self] text in
                    self?.lastCaption = text
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
                cap.begin()
                for t in tracks { t.add(audioRenderer: cap) }
                CaptionsHolder.shared.captioner = cap
                CaptionsHolder.shared.tracks = tracks
                UIAccessibility.post(notification: .announcement, argument: "Live captions on")
            }
        } else {
            if let cap = CaptionsHolder.shared.captioner { for t in CaptionsHolder.shared.tracks { t.remove(audioRenderer: cap) }; cap.end() }
            CaptionsHolder.shared.captioner = nil
            CaptionsHolder.shared.tracks = []
            UIAccessibility.post(notification: .announcement, argument: "Live captions off")
        }
    }
}

final class CaptionsHolder: @unchecked Sendable {
    static let shared = CaptionsHolder()
    var captioner: LiveCaptioner?
    var tracks: [RemoteAudioTrack] = []
}

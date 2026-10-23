import Foundation
import Speech
import AVFoundation
import UIKit

/// 6 + 16: on-device speech recognition (SFSpeechRecognizer with requiresOnDeviceRecognition when supported).
enum Transcriber {
    static func authorize() async -> Bool {
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
    }

    static func transcribe(fileURL: URL, locale: Locale = .current) async -> String? {
        guard await authorize(), let r = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), r.isAvailable else { return nil }
        let req = SFSpeechURLRecognitionRequest(url: fileURL)
        if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true } else { return nil } // never send audio to a server
        req.addsPunctuation = true
        return await withCheckedContinuation { c in
            var done = false
            r.recognitionTask(with: req) { result, error in
                guard !done else { return }
                if let result, result.isFinal { done = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if error != nil { done = true; c.resume(returning: nil) }
            }
        }
    }
}

/// Live dictation for voice-first compose.
@MainActor
final class LiveDictation: ObservableObject {
    @Published var text = ""
    @Published var isListening = false
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard await Transcriber.authorize(), let r = SFSpeechRecognizer(), r.isAvailable, r.supportsOnDeviceRecognition else {
            UIAccessibility.post(notification: .announcement, argument: "On-device dictation isn't available on this iPhone.")
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        try? engine.start()
        isListening = true
        task = r.recognitionTask(with: req) { [weak self] result, _ in
            guard let result else { return }
            let s = result.bestTranscription.formattedString
            Task { @MainActor in self?.text = s }
        }
    }

    func stop() {
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.finish()
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// 17: reads messages with the best installed voice (premium → enhanced → personal voice if authorized).
@MainActor
final class NaturalReader: NSObject, ObservableObject {
    static let shared = NaturalReader()
    private let synth = AVSpeechSynthesizer()

    func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        if #available(iOS 17, *), AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized,
           let p = voices.first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) { return p }
        return voices.first { $0.quality == .premium } ?? voices.first { $0.quality == .enhanced } ?? AVSpeechSynthesisVoice(language: language)
    }

    func speak(_ text: String, language: String? = nil) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        let lang = language ?? LanguageID.detect(text) ?? LanguageID.deviceLanguage
        u.voice = AISettings.isOn(.naturalVoices) ? bestVoice(for: lang) : AVSpeechSynthesisVoice(language: lang)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

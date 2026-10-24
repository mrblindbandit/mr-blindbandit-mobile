import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Translation order: Apple Translation framework (on-device, installed languages) → Foundation Models LLM
/// (covers Cebuano/Tagalog, which Apple Translation doesn't offer) → nothing (the original stays).
/// OPUS-MT Core ML models are not bundled in 2.0.0 (see CHANGELOG); the LLM is the Cebuano/Tagalog fallback.
@MainActor
final class Translator: ObservableObject {
    static let shared = Translator()
    enum Engine: String { case apple = "Apple Translation", llm = "Apple Intelligence" }
    struct Result: Equatable { let text: String; let source: String; let engine: String }

    private var cache: [String: Result] = [:]
    private var showOriginal: Set<String> = []

    func isShowingOriginal(_ id: String) -> Bool { showOriginal.contains(id) }
    func toggleOriginal(_ id: String) {
        if showOriginal.contains(id) { showOriginal.remove(id) } else { showOriginal.insert(id) }
        objectWillChange.send()
    }

    func cached(_ id: String) -> Result? { cache[id] }
    func store(_ r: Result, for id: String) { cache[id] = r; objectWillChange.send() }

    /// Incoming: detect, translate to the device language. Returns nil when no translation is needed or possible.
    func translateIncoming(id: String, text: String, chatKey: String) async -> Result? {
        if let c = cache[id] { return c }
        // Honor both Settings > AI auto-translate AND per-chat Security "Auto-translate".
        let chatPref = ChatSettingsCache.get(chatKey)?.my.translate ?? true
        guard AISettings.isOn(.translate), AISettings.chatAllowed(chatKey), chatPref else { return nil }
        guard let src = LanguageID.detect(text) ?? LanguageID.detectLoose(text) else { return nil }
        let target = LanguageID.deviceLanguage
        guard src != target else { return nil }
        guard let r = await translate(text, from: src, to: target) else { return nil }
        cache[id] = r
        objectWillChange.send()
        return r
    }

    func translate(_ text: String, from src: String, to target: String) async -> Result? {
        #if canImport(Translation)
        if #available(iOS 26, *) {
            let s = Locale.Language(identifier: src), t = Locale.Language(identifier: target)
            let status = await LanguageAvailability().status(from: s, to: t)
            if status == .installed {
                let session = TranslationSession(installedSource: s, target: t)
                if let r = try? await session.translate(text) { return Result(text: r.targetText, source: src, engine: Engine.apple.rawValue) }
            }
        }
        #endif
        let srcName = LanguageID.name(src), tgtName = LanguageID.name(target)
        if let out = await OnDeviceAI.respond(instructions: "Translate the user's message from \(srcName) to \(tgtName). Return only the translation, keep names, emoji and tone.", prompt: text) {
            return Result(text: out, source: src, engine: Engine.llm.rawValue)
        }
        // Cloud fallback — devices without Apple Intelligence / Translation packs still get auto-translate.
        if let out = await CloudAI.translate(text, target: target, source: src), !out.isEmpty {
            return Result(text: out, source: src, engine: "Cloud")
        }
        return nil
    }

    /// Outgoing: translate my draft into the other person's language.
    func translateOutgoing(_ text: String, to target: String) async -> String? {
        let src = LanguageID.detect(text) ?? LanguageID.deviceLanguage
        guard src != target else { return nil }
        return await translate(text, from: src, to: target)?.text
    }

    /// "Translated from Cebuano" for VoiceOver.
    static func spokenSource(_ code: String) -> String { "Translated from \(LanguageID.name(code))" }
}

/// Lets the user download Apple Translation languages (system sheet) from Settings > AI.
struct TranslationDownloadButton: View {
    let source: String
    let target: String
    @State private var trigger = false
    var body: some View {
        if #available(iOS 18, *) {
            DownloadHost(source: source, target: target)
        } else {
            Text("Downloading translation languages needs iOS 18 or later.").font(.footnote)
        }
    }
}

@available(iOS 18, *)
private struct DownloadHost: View {
    let source: String
    let target: String
    @State private var config: TranslationSession.Configuration?
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading) {
            Button("Download \(LanguageID.name(source)) to \(LanguageID.name(target)) for offline translation") {
                config = TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
            }
            if !status.isEmpty { Text(status).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
        }
        .translationTask(config) { session in
            do {
                try await session.prepareTranslation()
                await MainActor.run { status = "Ready."; UIAccessibility.post(notification: .announcement, argument: "Translation languages ready") }
            } catch {
                await MainActor.run { status = "This language pair isn't offered by Apple Translation. Apple Intelligence will translate it instead when available." }
            }
        }
    }
}

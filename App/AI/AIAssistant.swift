import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "@AI <question>" in any chat runs Apple's on-device model on the sender's iPhone. Public answers are posted as an
/// encrypted message labeled "AI (via @handle)"; "@AI private …" or "/ai …" answers stay on this device only.
/// No server is ever asked to generate anything.
@MainActor
enum AIAssistant {
    struct Invocation: Equatable { let question: String; let isPrivate: Bool }

    static func parse(_ text: String) -> Invocation? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower.hasPrefix("/ai ") || lower == "/ai" { return Invocation(question: String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces), isPrivate: true) }
        guard lower.hasPrefix("@ai ") || lower == "@ai" else { return nil }
        var q = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var priv = false
        if q.lowercased().hasPrefix("private") { priv = true; q = String(q.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        return Invocation(question: q, isPrivate: priv)
    }

    // Per-chat switch and the group-admin policy (an encrypted "ai_policy" control every member's app honours).
    static func allowed(chatKey: String) -> Bool {
        !(UserDefaults.standard.stringArray(forKey: "ai.mention.off") ?? []).contains(chatKey) && (ChatSettingsCache.get(chatKey)?.allow_ai ?? true)
    }
    static func setAllowed(_ on: Bool, chatKey: String) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "ai.mention.off") ?? [])
        if on { s.remove(chatKey) } else { s.insert(chatKey) }
        UserDefaults.standard.set(Array(s), forKey: "ai.mention.off")
    }
    static var consentGiven: Bool {
        get { UserDefaults.standard.bool(forKey: "ai.mention.consent") }
        set { UserDefaults.standard.set(newValue, forKey: "ai.mention.consent") }
    }

    enum Intent { case summarize, translate(String), reply, poll, reminder, find, describePhoto, general }

    static func intent(_ q: String) -> Intent {
        let l = q.lowercased()
        if l.contains("summar") || l.contains("catch me up") || l.contains("tl;dr") || l.contains("what did i miss") { return .summarize }
        if l.hasPrefix("translate") {
            let target = ["cebuano": "ceb", "bisaya": "ceb", "tagalog": "tl", "filipino": "tl", "english": "en", "spanish": "es", "japanese": "ja", "korean": "ko", "chinese": "zh", "french": "fr"]
                .first { l.contains($0.key) }?.value ?? LanguageID.deviceLanguage
            return .translate(target)
        }
        if l.contains("reply") || l.contains("respond") || l.contains("draft") { return .reply }
        if l.contains("poll") || l.contains("vote") { return .poll }
        if l.contains("remind") || l.contains("reminder") { return .reminder }
        if l.contains("describe") && (l.contains("photo") || l.contains("picture") || l.contains("image")) { return .describePhoto }
        if l.hasPrefix("find") || l.hasPrefix("when did") || l.hasPrefix("where") || l.contains("search") || l.hasPrefix("who said") { return .find }
        return .general
    }

    struct Context {
        var chatName: String
        var lines: [String]           // "Name: text", oldest first, ≤ 30
        var lastPhoto: UIImage?
    }

    static let instructions = OnDeviceAI.base + " You are @AI inside a group or private chat. Answer the latest question using the chat context when relevant. Keep answers under 120 words."

    /// Streams the answer; `onPartial` gets the growing text. Returns the final answer or a friendly fallback.
    static func answer(_ inv: Invocation, context: Context, onPartial: @escaping @MainActor (String) -> Void) async -> String {
        guard OnDeviceAI.isAvailable else {
            return "@AI needs Apple Intelligence on iOS 26. \(OnDeviceAI.unavailableReason)"
        }
        let ctx = consentGiven ? context.lines.suffix(30).joined(separator: "\n") : ""
        switch intent(inv.question) {
        case .summarize:
            if let s = await CloudAI.summarize(chatName: context.chatName, lines: context.lines) { return s }
            return await OnDeviceAI.catchUp(chatName: context.chatName, lines: context.lines) ?? "Nothing to summarize yet."
        case .translate(let target):
            let text = inv.question.replacingOccurrences(of: #"(?i)^translate( this| to \w+| into \w+)?:?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let src = text.isEmpty ? (context.lines.last ?? "") : text
            if ["ceb", "tl", "fil"].contains(target.lowercased()), let c = await CloudAI.translate(src, target: target == "fil" ? "tl" : target) { return c }
            return await Translator.shared.translateOutgoing(src, to: target) ?? src
        case .reply:
            let r = await OnDeviceAI.smartReplies(lines: context.lines)
            return r.isEmpty ? "No reply ideas right now." : "Reply ideas:\n" + r.map { "• \($0)" }.joined(separator: "\n")
        case .poll:
            if let p = await OnDeviceAI.pollSuggestion(lines: context.lines + [inv.question]) {
                return "Poll idea: \(p.question)\n" + p.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            }
        case .reminder:
            let actions = ActionDetector.detect(inv.question + "\n" + context.lines.suffix(10).joined(separator: "\n"))
            if let a = actions.first(where: { if case .date = $0.kind { return true }; return false }) { return "Suggested: \(a.label). Double-tap the message to add it." }
        case .describePhoto:
            if let img = context.lastPhoto { return await VisionDescriber.describe(img).summary }
            return "I couldn't find a recent photo in this chat."
        case .find, .general:
            break
        }
        let persona = inv.isPrivate ? AIPersona.forPrivate.prompt() : AIPersona.professional.prompt()
        return await stream(persona: persona, prompt: (ctx.isEmpty ? "" : "Recent chat:\n\(ctx)\n\n") + "Question: \(inv.question)", lines: context.lines, onPartial: onPartial)
    }

    private static func stream(persona: String, prompt: String, lines: [String], onPartial: @escaping @MainActor (String) -> Void) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(tools: [FindInChatTool(lines: lines)], instructions: persona + " You are @AI inside a group or private chat. Answer the latest question using the chat context when relevant. Keep answers under 120 words.")
            var last = ""
            do {
                for try await snapshot in session.streamResponse(to: prompt) {
                    last = snapshot.content
                    let s = last
                    await onPartial(s)
                }
                return last.isEmpty ? "I don't have an answer for that." : last
            } catch {
                return last.isEmpty ? "I couldn't answer that on this device." : last
            }
        }
        #endif
        return "@AI isn't available on this iPhone."
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct FindInChatTool: Tool {
    let name = "findInChat"
    let description = "Searches the recent messages of this chat for a word or phrase and returns matching lines."
    let lines: [String]

    @Generable
    struct Arguments {
        @Guide(description: "A word or short phrase to look for")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let q = arguments.query.lowercased()
        let hits = lines.filter { $0.lowercased().contains(q) }
        return hits.isEmpty ? "No messages mention \(arguments.query)." : hits.suffix(8).joined(separator: "\n")
    }
}
#endif


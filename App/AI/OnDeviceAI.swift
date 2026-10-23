import Foundation
import SwiftUI
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Settings > AI. Everything runs on this iPhone; nothing is ever sent to a server.
enum AISettings {
    enum Feature: String, CaseIterable, Identifiable {
        case photoDescriptions, ocr, catchUp, smartReplies, rewrite, voiceSummaries, translate, scamWarnings,
             smartSearch, actions, pollSuggestions, altTextWriter, describeCamera, voiceCompose, naturalVoices, digest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .photoDescriptions: return "Describe received photos"
            case .ocr: return "Read text in images"
            case .catchUp: return "Catch me up summaries"
            case .smartReplies: return "Smart replies"
            case .rewrite: return "Rewrite and tone help"
            case .voiceSummaries: return "Voice message transcripts and summaries"
            case .translate: return "Auto-translate messages"
            case .scamWarnings: return "Scam and spam warnings"
            case .smartSearch: return "Smart search"
            case .actions: return "Dates, addresses and tracking suggestions"
            case .pollSuggestions: return "Poll suggestions in groups"
            case .altTextWriter: return "Write descriptions for photos I send"
            case .describeCamera: return "Describe my camera"
            case .voiceCompose: return "Voice-first compose"
            case .naturalVoices: return "Read messages with natural voices"
            case .digest: return "Smart notification digest"
            }
        }
        /// Features that need Apple Intelligence (Foundation Models). Others use Vision/Speech/NaturalLanguage only.
        var needsLanguageModel: Bool { [.catchUp, .smartReplies, .rewrite, .smartSearch, .pollSuggestions, .digest].contains(self) }
    }
    static func isOn(_ f: Feature) -> Bool { UserDefaults.standard.object(forKey: "ai.\(f.rawValue)") as? Bool ?? true }
    static func set(_ f: Feature, _ on: Bool) { UserDefaults.standard.set(on, forKey: "ai.\(f.rawValue)") }
    /// Per-chat master switch (Chat info > Security & Privacy > On-device AI).
    static func chatAllowed(_ chatKey: String) -> Bool { !(UserDefaults.standard.stringArray(forKey: "ai.offChats") ?? []).contains(chatKey) }
    static func setChat(_ chatKey: String, _ on: Bool) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "ai.offChats") ?? [])
        if on { s.remove(chatKey) } else { s.insert(chatKey) }
        UserDefaults.standard.set(Array(s), forKey: "ai.offChats")
    }
    static func enabled(_ f: Feature, chat: String? = nil) -> Bool {
        guard isOn(f), chat.map(chatAllowed) ?? true else { return false }
        return !f.needsLanguageModel || OnDeviceAI.isAvailable
    }
}

/// Apple Foundation Models (iOS 26+, Apple Intelligence devices). Hidden everywhere else.
enum OnDeviceAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Available on this iPhone."
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence. Vision, OCR, transcription and translation still work."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in the Settings app to use summaries, smart replies and rewrite."
                case .modelNotReady: return "Apple Intelligence is still downloading. Try again later."
                @unknown default: return "Apple Intelligence isn't available right now."
                }
            }
        }
        #endif
        return "Needs iOS 26 with Apple Intelligence. Vision, OCR, transcription and translation still work."
    }

    /// One-shot prompt. Returns nil when the model is unavailable or refuses; callers always have a non-AI fallback.
    static func respond(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard isAvailable else { return nil }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let r = try await session.respond(to: String(prompt.prefix(12000)))
                let text = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch { return nil }
        }
        #endif
        return nil
    }

    static let base = "You help a blind or low-vision person use a private messaging app. Be brief, plain and accurate. Never invent facts. No markdown."

    // 3. Catch-me-up
    static func catchUp(chatName: String, lines: [String]) async -> String? {
        guard !lines.isEmpty else { return nil }
        return await respond(instructions: base + " Summarize unread chat messages in 2 to 4 short sentences. Mention who said what, questions waiting for an answer, and any dates or plans.",
                             prompt: "Chat: \(chatName)\n" + lines.suffix(80).joined(separator: "\n"))
    }

    // 4. Smart replies
    static func smartReplies(lines: [String]) async -> [String] {
        guard let out = await respond(instructions: base + " Suggest exactly 3 short replies (under 8 words each) the user could send next. One per line, no numbering, no quotes.",
                                      prompt: lines.suffix(12).joined(separator: "\n")) else { return [] }
        return out.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•\"0123456789.")) }.filter { !$0.isEmpty }.prefix(3).map { $0 }
    }

    enum Tone: String, CaseIterable, Identifiable {
        case friendlier = "Friendlier", shorter = "Shorter", professional = "More professional", fixSpelling = "Fix spelling and grammar"
        var id: String { rawValue }
    }

    // 5. Rewrite
    static func rewrite(_ text: String, tone: Tone) async -> String? {
        await respond(instructions: base + " Rewrite the user's message. Goal: \(tone.rawValue). Keep the meaning and language. Return only the rewritten message.", prompt: text)
    }

    // 6. Voice-note summary
    static func summarizeTranscript(_ t: String) async -> String? {
        guard t.count > 120 else { return nil }
        return await respond(instructions: base + " Summarize this voice message transcript in one or two sentences.", prompt: t)
    }

    // 11. Smart search
    static func smartSearch(question: String, corpus: [(id: String, line: String)]) async -> [String] {
        let keywordHits = corpus.filter { item in
            question.lowercased().split(separator: " ").filter { $0.count > 3 }.contains { item.line.lowercased().contains($0) }
        }.map(\.id)
        guard let out = await respond(instructions: base + " Given numbered chat messages, return the numbers of the messages that answer the question, comma separated, best first. Return NONE if nothing matches.",
                                      prompt: "Question: \(question)\n" + corpus.suffix(300).enumerated().map { "\($0.offset): \($0.element.line)" }.joined(separator: "\n")) else { return keywordHits }
        let window = Array(corpus.suffix(300))
        let ids = out.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 < window.count }.map { window[$0].id }
        return ids.isEmpty ? keywordHits : ids
    }

    // 13. Poll suggestions
    static func pollSuggestion(lines: [String]) async -> (question: String, options: [String])? {
        guard let out = await respond(instructions: base + " If the group is trying to decide something, write a poll: first line the question, then 2 to 4 option lines. Otherwise answer NONE.",
                                      prompt: lines.suffix(30).joined(separator: "\n")), !out.uppercased().hasPrefix("NONE") else { return nil }
        let parts = out.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•0123456789.)")) }.filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil }
        return (parts[0], Array(parts.dropFirst().prefix(4)))
    }

    // 16. Voice compose cleanup
    static func cleanDictation(_ text: String) async -> String {
        await respond(instructions: base + " Clean up this dictated message: fix punctuation, capitalization and obvious recognition mistakes, remove filler words like um. Keep the wording and language. Return only the message.", prompt: text) ?? text
    }

    // 18. Notification digest
    static func digest(_ lines: [String]) async -> String? {
        await respond(instructions: base + " Write a short digest of these new messages grouped by chat, most important first.", prompt: lines.joined(separator: "\n"))
    }

    // Photo description composition (Vision facts → one natural sentence).
    static func composeDescription(facts: String) async -> String? {
        await respond(instructions: base + " Turn these on-device image analysis results into one or two natural sentences describing the photo for a blind person. Include any readable text. Do not guess identities.", prompt: facts)
    }
}

// MARK: - 9. Scam / phishing / spam detection (NaturalLanguage + rules, Foundation Models when available)

enum ScamDetector {
    static let patterns = ["gift card", "wire transfer", "verify your account", "your account has been suspended", "bitcoin", "crypto investment",
                           "claim your prize", "you have won", "urgent", "password", "otp", "one-time code", "send the code", "bank details",
                           "western union", "remittance", "gcash", "load", "pin code", "click this link", "limited time", "investment opportunity"]

    struct Verdict: Equatable { let suspicious: Bool; let reason: String }

    /// Only used for messages from people you haven't chatted with before.
    static func quickCheck(_ text: String) -> Verdict {
        let t = text.lowercased()
        var score = 0
        var reasons: [String] = []
        let hits = patterns.filter { t.contains($0) }
        score += hits.count * 2
        if !hits.isEmpty { reasons.append("mentions \(hits.prefix(2).joined(separator: " and "))") }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let links = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
            if links.contains(where: { ($0.host ?? "").split(separator: ".").count > 3 || ["bit.ly", "tinyurl.com", "t.co"].contains($0.host ?? "") }) {
                score += 2; reasons.append("contains a shortened or unusual link")
            } else if !links.isEmpty { score += 1 }
        }
        return Verdict(suspicious: score >= 3, reason: reasons.joined(separator: ", "))
    }

    static func check(_ text: String) async -> Verdict {
        let quick = quickCheck(text)
        guard OnDeviceAI.isAvailable else { return quick }
        guard let out = await OnDeviceAI.respond(instructions: "Classify whether a message from a stranger is likely a scam, phishing or spam. Answer SCAM: <short reason> or SAFE.", prompt: text) else { return quick }
        if out.uppercased().hasPrefix("SCAM") {
            return Verdict(suspicious: true, reason: out.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return quick.suspicious ? quick : Verdict(suspicious: false, reason: "")
    }
}

// MARK: - 12. Action detection (dates, addresses, tracking numbers, phone numbers, links)

struct DetectedAction: Identifiable, Equatable {
    enum Kind: Equatable { case date(Date), address(String), tracking(String), phone(String), link(URL) }
    let id = UUID()
    let kind: Kind
    let label: String
    static func == (a: DetectedAction, b: DetectedAction) -> Bool { a.label == b.label }

    var url: URL? {
        switch kind {
        case .address(let a): return URL(string: "maps://?q=\(a.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        case .tracking(let t): return URL(string: "https://parcelsapp.com/en/tracking/\(t)")
        case .phone(let p): return URL(string: "tel:\(p.filter { $0.isNumber || $0 == "+" })")
        case .link(let u): return u
        case .date: return nil
        }
    }
}

enum ActionDetector {
    static func detect(_ text: String) -> [DetectedAction] {
        var out: [DetectedAction] = []
        let types: NSTextCheckingResult.CheckingType = [.date, .address, .phoneNumber, .link]
        if let d = try? NSDataDetector(types: types.rawValue) {
            for m in d.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let s = Range(m.range, in: text).map { String(text[$0]) } ?? ""
                switch m.resultType {
                case .date: if let date = m.date { out.append(.init(kind: .date(date), label: "Add reminder: \(date.formatted(date: .abbreviated, time: .shortened))")) }
                case .address: out.append(.init(kind: .address(s), label: "Open in Maps: \(s)"))
                case .phoneNumber: out.append(.init(kind: .phone(s), label: "Call \(s)"))
                case .link: if let u = m.url, u.scheme?.hasPrefix("http") == true { out.append(.init(kind: .link(u), label: "Open link \(u.host ?? "")")) }
                default: break
                }
            }
        }
        // UPS / USPS / FedEx / DHL / LBC style tracking numbers.
        let pattern = #"\b(1Z[0-9A-Z]{16}|\d{12,22}|[A-Z]{2}\d{9}[A-Z]{2})\b"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text) { out.append(.init(kind: .tracking(String(text[r])), label: "Track package \(text[r])")) }
            }
        }
        return out
    }
}

// MARK: - Language detection

enum LanguageID {
    static func detect(_ text: String) -> String? {
        guard text.count >= 8 else { return nil }
        let r = NLLanguageRecognizer()
        r.processString(text)
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first, p > 0.6 else {
            return CebuanoHeuristic.guess(text)
        }
        return lang.rawValue
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    static var deviceLanguage: String { Locale.current.language.languageCode?.identifier ?? "en" }
}

/// NLLanguageRecognizer has no Cebuano model; these function words are very common in Bisaya and rare elsewhere.
enum CebuanoHeuristic {
    static let ceb: Set<String> = ["ang", "nga", "sa", "ko", "ka", "kaayo", "unsa", "asa", "ikaw", "akong", "imong", "dili", "wala", "naa", "diha", "ayo", "salamat", "maayong", "lagi", "jud", "gyud", "kini", "kana", "unya", "karon", "ugma", "ganina"]
    static let tl: Set<String> = ["ang", "ng", "mga", "sa", "ako", "ikaw", "hindi", "wala", "po", "opo", "salamat", "ano", "saan", "bakit", "kasi", "naman", "talaga", "kita", "tayo", "bukas", "ngayon", "kanina", "lang"]
    static func guess(_ text: String) -> String? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard words.count >= 3 else { return nil }
        let c = words.filter { ceb.contains($0) && !tl.contains($0) }.count
        let t = words.filter { tl.contains($0) && !ceb.contains($0) }.count
        if c >= 2 && c > t { return "ceb" }
        if t >= 2 && t > c { return "tl" }
        return nil
    }
}

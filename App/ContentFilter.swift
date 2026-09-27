import Foundation

/// On-device filter for objectionable language in messages from other people
/// (App Store Review Guideline 1.2, Google Play User Generated Content policy).
/// Matching words are masked before they are shown or read aloud by VoiceOver. The filter is on
/// by default and can be turned off in Settings > Safety. Reports, blocking and moderator review
/// on the Blindbandit server remain the primary protections.
enum ContentFilter {
    static let settingKey = "filterOffensiveLanguage"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Word stems for severe profanity, slurs and sexual terms. Matching is case-insensitive,
    /// on whole words, and also catches common suffixes (plural, -ed, -er, -ing, -y and so on).
    /// Stems that are also the start of everyday words are deliberately left out.
    static let blockedStems: [String] = [
        "fuck", "motherfuck", "shit", "bullshit", "bitch", "cunt", "asshole", "bastard", "pussy",
        "whore", "slut", "twat", "wanker", "porn", "nude", "rape", "raped", "raping", "rapist",
        "nigger", "nigga", "faggot", "fag", "retard", "chink", "kike", "tranny", "dyke", "wetback",
        "raghead", "beaner", "kys"
    ]

    private static let regex: NSRegularExpression? = {
        let alternatives = blockedStems
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try? NSRegularExpression(pattern: "\\b(?:\(alternatives))(?:s|es|ed|er|ers|ing|in|y|ty|ies|head|heads|face)?\\b", options: [.caseInsensitive])
    }()

    /// Returns `text` with each matching word replaced by asterisks of the same length.
    static func mask(_ text: String) -> String {
        guard let regex else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            result.replaceCharacters(in: match.range, with: String(repeating: "*", count: match.range.length))
        }
        return result as String
    }

    static func containsBlockedLanguage(_ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Text to display for a message from someone else, honouring the Settings toggle.
    static func display(_ text: String, enabled: Bool = ContentFilter.isEnabled) -> String {
        enabled ? mask(text) : text
    }
}

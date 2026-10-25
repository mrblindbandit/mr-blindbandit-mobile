import AppIntents
import Foundation

struct CallHandleIntent: AppIntent {
    static var title: LocalizedStringResource = "Call Blind Bandit"
    static var description = IntentDescription("Start a Blind Bandit call with a @handle.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Handle")
    var handle: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let cleaned = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return .result() }
        NotificationCenter.default.post(
            name: .blindbanditCallDeepLinkReceived,
            object: nil,
            userInfo: ["handle": cleaned, "source": "appIntent"]
        )
        return .result()
    }
}

struct MessageHandleIntent: AppIntent {
    static var title: LocalizedStringResource = "Message Blind Bandit"
    static var description = IntentDescription("Open a Blind Bandit chat with a @handle.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Handle")
    var handle: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let cleaned = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleaned.isEmpty else { return .result() }
        NotificationCenter.default.post(
            name: .blindbanditMessageDeepLinkReceived,
            object: nil,
            userInfo: ["handle": cleaned, "source": "appIntent"]
        )
        return .result()
    }
}

struct WhatsNewOnBanditFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "What’s new on Bandit Feed"
    static var description = IntentDescription("Open Blind Bandit Bites / Bandit Feed.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .banditOpenBitesTab, object: nil)
        return .result()
    }
}

struct StartBanditAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Blind Bandit AI"
    static var description = IntentDescription("Open Blind Bandit AI chat.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .banditOpenAIChat, object: nil)
        return .result()
    }
}

/// App Shortcuts only for parameter-free intents (String @Parameter is not allowed in utterances).
struct BanditAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNewOnBanditFeedIntent(),
            phrases: [
                "What’s new on Bandit Feed in \(.applicationName)",
                "Open Bandit Feed in \(.applicationName)",
            ],
            shortTitle: "Bandit Feed",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: StartBanditAIIntent(),
            phrases: [
                "Start AI in \(.applicationName)",
                "Open Blind Bandit AI in \(.applicationName)",
            ],
            shortTitle: "AI",
            systemImageName: "brain.head.profile"
        )
    }
}

extension Notification.Name {
    static let banditOpenBitesTab = Notification.Name("banditOpenBitesTab")
    static let banditOpenAIChat = Notification.Name("banditOpenAIChat")
    static let banditFocusFilterChanged = Notification.Name("banditFocusFilterChanged")
}

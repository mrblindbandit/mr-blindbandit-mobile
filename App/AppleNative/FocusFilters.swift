import AppIntents
import Foundation
import SwiftUI

struct BanditFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Blind Bandit Focus"
    static var description = IntentDescription("Quiet Hours / Work: hide Bites or mute notification categories the system Focus way.")

    @Parameter(title: "Hide Bites tab")
    var hideBites: Bool

    @Parameter(title: "Mute message banners")
    var muteMessages: Bool

    @Parameter(title: "Mute call banners (non-VoIP)")
    var muteCalls: Bool

    @Parameter(title: "Mute Bandit Feed alerts")
    var muteBites: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Blind Bandit", subtitle: hideBites ? "Bites hidden" : "Full feed")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        BanditSharedStore.focusHideBites = hideBites
        let defaults = UserDefaults.standard
        if muteMessages { defaults.set(false, forKey: SettingsKey.notifyMessages) }
        if muteCalls { defaults.set(false, forKey: SettingsKey.notifyCalls) }
        if muteBites {
            defaults.set(false, forKey: SettingsKey.bitesNotifyComments)
            defaults.set(false, forKey: SettingsKey.bitesNotifyMentions)
            defaults.set(false, forKey: SettingsKey.bitesNotifyNewFollowers)
        }
        var muted: [String] = []
        if muteMessages { muted.append("messages") }
        if muteCalls { muted.append("calls") }
        if muteBites { muted.append("bites") }
        BanditSharedStore.defaults.set(muted, forKey: BanditSharedStore.Key.focusMuteCategories)
        NotificationCenter.default.post(name: .banditFocusFilterChanged, object: nil, userInfo: [
            "hideBites": hideBites,
            "muted": muted,
        ])
        return .result()
    }
}

import Foundation

/// App Group bridge for widgets, Watch, Live Activities, and the main app.
enum BanditSharedStore {
    static let suiteName = "group.net.mrblindbandit.app"
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    enum Key {
        static let unreadDMCount = "widget.unreadDMCount"
        static let latestBiteBody = "widget.latestBiteBody"
        static let latestBiteAuthor = "widget.latestBiteAuthor"
        static let latestBiteID = "widget.latestBiteID"
        static let activeCallHandle = "live.activeCallHandle"
        static let activeCallState = "live.activeCallState" // idle|ringing|connected
        static let activeCallStartedAt = "live.activeCallStartedAt"
        static let myHandle = "shared.myHandle"
        static let focusHideBites = "focus.hideBites"
        static let focusMuteCategories = "focus.muteCategories"
        static let widgetAuthHint = "widget.authHint" // opaque deeplink token hint only
    }

    static func publishUnreadDMs(_ count: Int) {
        defaults.set(count, forKey: Key.unreadDMCount)
    }

    static func publishLatestBite(id: String, author: String, body: String) {
        defaults.set(id, forKey: Key.latestBiteID)
        defaults.set(author, forKey: Key.latestBiteAuthor)
        defaults.set(String(body.prefix(280)), forKey: Key.latestBiteBody)
    }

    static func publishCall(handle: String, state: String, startedAt: Date?) {
        defaults.set(handle, forKey: Key.activeCallHandle)
        defaults.set(state, forKey: Key.activeCallState)
        if let startedAt {
            defaults.set(startedAt.timeIntervalSince1970, forKey: Key.activeCallStartedAt)
        } else {
            defaults.removeObject(forKey: Key.activeCallStartedAt)
        }
    }

    static var unreadDMCount: Int { defaults.integer(forKey: Key.unreadDMCount) }
    static var latestBiteBody: String { defaults.string(forKey: Key.latestBiteBody) ?? "" }
    static var latestBiteAuthor: String { defaults.string(forKey: Key.latestBiteAuthor) ?? "" }
    static var latestBiteID: String { defaults.string(forKey: Key.latestBiteID) ?? "" }
    static var myHandle: String {
        get { defaults.string(forKey: Key.myHandle) ?? "" }
        set { defaults.set(newValue, forKey: Key.myHandle) }
    }
    static var focusHideBites: Bool {
        get { defaults.bool(forKey: Key.focusHideBites) }
        set { defaults.set(newValue, forKey: Key.focusHideBites) }
    }
}

import Foundation

/// Debug-only mode used by `.github/workflows/store-screenshots.yml` to capture App Store
/// screenshots of the signed-in screens in the simulator without a real account.
/// It is compiled out of Release builds, so the shipping app can never skip sign-in.
///
///     xcrun simctl launch booted net.mrblindbandit.privateapp -StoreScreenshots YES -StoreScreenshotScreen listen
enum StoreScreenshotMode {
    #if DEBUG
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-StoreScreenshots") }
    /// One of: home, create, connect, listen, more, settings, music, community, profile, bites.
    static var screen: String { UserDefaults.standard.string(forKey: "StoreScreenshotScreen") ?? "home" }
    #else
    static let isActive = false
    static let screen = "home"
    #endif

    /// Public mrblindbandit.net pages shown in the in-app browser for web-based screens.
    static var webPage: (path: String, title: String)? {
        guard isActive else { return nil }
        switch screen {
        case "music": return ("/music/", "Music")
        case "community": return ("/mobile", "Community")
        case "profile": return ("/mobile/u/mrblindbandit", "Mr. Blindbandit")
        case "bites": return ("/mobile/bites", "BanditBites")
        default: return nil
        }
    }
}

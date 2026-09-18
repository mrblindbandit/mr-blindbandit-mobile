import Foundation

/// Central client configuration. Reusable backend secrets never ship in the binary.
enum AppConfig {
    static let appDisplayName = "Mr. Blind Bandit"
    static let marketingVersion = "1.5"
    static let webBaseURL = URL(string: "https://mrblindbandit.net")!
    static let apiBaseURL = URL(string: "https://api.mrblindbandit.net")!
    static let defaultLiveKitRoom = "mrblindbandit"

    static var clerkPublishableKey: String { AppSecrets.clerkPublishableKey }
    static var liveKitURL: String { AppSecrets.liveKitURL }
    static var liveKitScaffoldToken: String { AppSecrets.liveKitScaffoldToken }
    static var googleOAuthClientID: String { AppSecrets.googleOAuthClientID }

    static var isClerkConfigured: Bool { clerkPublishableKey.hasPrefix("pk_") }
    static var isLiveKitConfigured: Bool { liveKitURL.hasPrefix("wss://") }
}

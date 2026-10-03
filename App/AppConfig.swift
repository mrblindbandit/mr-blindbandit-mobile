import Foundation

/// Central client configuration. Reusable backend secrets never ship in the binary.
enum AppConfig {
    /// Store name on the App Store and Google Play. The Home Screen label is the shorter
    /// "BlindBandit" (CFBundleDisplayName) because iOS truncates labels longer than about 12 characters.
    static let appDisplayName = "Mr. BlindBandit Mobile"
    static let homeScreenName = "BlindBandit"
    static let marketingVersion = "1.7"
    static let webBaseURL = URL(string: "https://mrblindbandit.net")!
    static let apiBaseURL = URL(string: "https://api.mrblindbandit.net")!
    static let defaultLiveKitRoom = "mrblindbandit"

    static let privacyURL = URL(string: "https://mrblindbandit.net/privacy/")!
    static let termsURL = URL(string: "https://mrblindbandit.net/terms/")!
    static let supportURL = URL(string: "https://mrblindbandit.net/support/")!
    static let accessibilityURL = URL(string: "https://mrblindbandit.net/accessibility/")!
    static let accountURL = URL(string: "https://mrblindbandit.net/account")!
    /// Public web page where anyone can request account deletion without the app (Google Play requirement).
    static let accountDeletionURL = URL(string: "https://mrblindbandit.net/account/delete")!
    static let supportEmail = "business@mrblindbandit.net"

    static var clerkPublishableKey: String { AppSecrets.clerkPublishableKey }
    static var liveKitURL: String { AppSecrets.liveKitURL }

    static var isClerkConfigured: Bool { clerkPublishableKey.hasPrefix("pk_") }

    static let communityGuidelinesURL = URL(string: "https://mrblindbandit.net/community-guidelines/")!
    static let trustAndSafetyURL = URL(string: "https://mrblindbandit.net/mobile/trust-safety/")!
    static let reportContentURL = URL(string: "https://mrblindbandit.net/report-content/")!

    /// Clerk production instance "mr. blindbandit - Blindbandit Records" (clerk.mrblindbandit.net).
    /// Social buttons follow the providers enabled in Clerk; see `SignInProviderPolicy`
    /// (App Store Review Guideline 4.8).
}

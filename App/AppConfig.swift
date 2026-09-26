import Foundation

/// Central client configuration. Reusable backend secrets never ship in the binary.
enum AppConfig {
    static let appDisplayName = "Mr. Blindbandit"
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

    /// Clerk production instance "mr. blindbandit - Blindbandit Records" (clerk.mrblindbandit.net).
    /// Email + password, Google, and Sign in with Apple. Apple is required by App Store Review
    /// Guideline 4.8 because Google sign-in is offered; the Apple provider must be enabled in Clerk.
    static var enableSignInWithApple: Bool { true }
}

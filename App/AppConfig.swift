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
    static var hasLiveKitScaffoldToken: Bool { !liveKitScaffoldToken.isEmpty }


    /// Clerk Production app: "mr. blindbandit - Blindbandit Records" on mrblindbandit.net
    /// Email (code+link) ON, Google OAuth ON, Apple OFF, Phone OFF.
    /// Hosted OAuth callback: https://clerk.mrblindbandit.net/v1/oauth_callback
    /// Mobile deep link registered for SDK return:
    static let oauthCallbackURLScheme = "blindbandit"
    static let oauthCallbackURL = URL(string: "blindbandit://oauth-callback")!
    static let clerkOAuthHostedCallback = URL(string: "https://clerk.mrblindbandit.net/v1/oauth_callback")!

    /// Sign in with Apple requires an Apple Developer account + Clerk Apple strategy.
    /// Default off until App Store submission with SIWA entitlement configured.
    static var enableSignInWithApple: Bool { false }

    /// Phone OTP via Clerk — enable only when the Clerk instance has SMS/OTP configured (often paid).
    static var enablePhoneOTP: Bool { false }
}


import Foundation

/// Central client configuration. Reusable backend secrets never ship in the binary.
enum AppConfig {
    static let appDisplayName = "Mr. Blind Bandit"
    static let marketingVersion = "1.6"
    static let webBaseURL = URL(string: "https://mrblindbandit.net")!
    static let apiBaseURL = URL(string: "https://api.mrblindbandit.net")!
    static let defaultLiveKitRoom = "mrblindbandit"

    static var clerkPublishableKey: String { AppSecrets.clerkPublishableKey }
    static var liveKitURL: String { AppSecrets.liveKitURL }
    static var googleOAuthClientID: String { AppSecrets.googleOAuthClientID }

    static var isClerkConfigured: Bool { clerkPublishableKey.hasPrefix("pk_") }
    static var isLiveKitConfigured: Bool { liveKitURL.hasPrefix("wss://") }

    /// Clerk Production app: "mr. blindbandit - Blindbandit Records" on mrblindbandit.net.
    /// Email/password, Google OAuth, and Sign in with Apple are supported by the native app.
    static let oauthCallbackURLScheme = "blindbandit"
    static let oauthCallbackURL = URL(string: "blindbandit://oauth-callback")!
    static let clerkOAuthHostedCallback = URL(string: "https://clerk.mrblindbandit.net/v1/oauth_callback")!

    /// Required as an equivalent privacy-preserving login option when Google is offered on iOS.
    static var enableSignInWithApple: Bool { true }

    /// Phone OTP remains off until the Clerk instance has SMS/OTP configured.
    static var enablePhoneOTP: Bool { false }
}

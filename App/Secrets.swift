import Foundation

/// Client-safe production configuration only. These values are identifiers/endpoints that are
/// intentionally shipped in the app binary. Reusable server credentials must NEVER be added here.
enum ProductionPublicConfig {
    static let clerkPublishableKey = "pk_live_Y2xlcmsubXJibGluZGJhbmRpdC5uZXQk"
    static let liveKitURL = "wss://mrblindbandit-net-bpd8we2l.livekit.cloud"
    static let googleOAuthClientID = "734579493984-oiet9j1hv9lhp7rkcjs9cqhf02biuatg.apps.googleusercontent.com"
}

/// Local development overrides. `Secrets.local.swift` is gitignored and may populate these at build time.
enum _LocalSecretsBridge {
    static var clerkPublishableKey = ""
    static var liveKitURL = ""
    static var liveKitScaffoldToken = ""
    static var googleOAuthClientID = ""
}

enum AppSecrets {
    static var clerkPublishableKey: String {
        if !_LocalSecretsBridge.clerkPublishableKey.isEmpty { return _LocalSecretsBridge.clerkPublishableKey }
        if let env = ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"], !env.isEmpty { return env }
        return ProductionPublicConfig.clerkPublishableKey
    }

    static var liveKitURL: String {
        if !_LocalSecretsBridge.liveKitURL.isEmpty { return _LocalSecretsBridge.liveKitURL }
        if let env = ProcessInfo.processInfo.environment["LIVEKIT_URL"], !env.isEmpty { return env }
        return ProductionPublicConfig.liveKitURL
    }

    /// Development-only fallback. Production should obtain short-lived participant tokens from the server.
    static var liveKitScaffoldToken: String {
        if !_LocalSecretsBridge.liveKitScaffoldToken.isEmpty { return _LocalSecretsBridge.liveKitScaffoldToken }
        return ProcessInfo.processInfo.environment["LIVEKIT_TOKEN"] ?? ""
    }

    static var googleOAuthClientID: String {
        if !_LocalSecretsBridge.googleOAuthClientID.isEmpty { return _LocalSecretsBridge.googleOAuthClientID }
        if let env = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"], !env.isEmpty { return env }
        return ProductionPublicConfig.googleOAuthClientID
    }
}

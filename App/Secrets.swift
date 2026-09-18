import Foundation

/// Default empty secrets bridge. Filled at load by gitignored `Secrets.local.swift` when present.
enum _LocalSecretsBridge {
    static var clerkPublishableKey = ""
    static var liveKitURL = ""
    static var liveKitScaffoldToken = ""
    static var googleOAuthClientID = ""
}

enum AppSecrets {
    static var clerkPublishableKey: String {
        if !_LocalSecretsBridge.clerkPublishableKey.isEmpty { return _LocalSecretsBridge.clerkPublishableKey }
        return ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"] ?? ""
    }

    static var liveKitURL: String {
        if !_LocalSecretsBridge.liveKitURL.isEmpty { return _LocalSecretsBridge.liveKitURL }
        return ProcessInfo.processInfo.environment["LIVEKIT_URL"] ?? ""
    }

    static var liveKitScaffoldToken: String {
        if !_LocalSecretsBridge.liveKitScaffoldToken.isEmpty { return _LocalSecretsBridge.liveKitScaffoldToken }
        return ProcessInfo.processInfo.environment["LIVEKIT_TOKEN"] ?? ""
    }

    static var googleOAuthClientID: String {
        if !_LocalSecretsBridge.googleOAuthClientID.isEmpty { return _LocalSecretsBridge.googleOAuthClientID }
        return ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] ?? ""
    }
}

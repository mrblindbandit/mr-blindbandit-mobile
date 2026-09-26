import Foundation

/// Client-safe production configuration only. These values are identifiers/endpoints that are
/// intentionally shipped in the app binary. Reusable server credentials must NEVER be added here.
enum ProductionPublicConfig {
    static let clerkPublishableKey = "pk_live_Y2xlcmsubXJibGluZGJhbmRpdC5uZXQk"
    static let liveKitURL = "wss://mrblindbandit-net-bpd8we2l.livekit.cloud"
}

/// Local development overrides. `Secrets.local.swift` is gitignored and may populate these at build time.
enum _LocalSecretsBridge {
    static var clerkPublishableKey = ""
    static var liveKitURL = ""
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
}

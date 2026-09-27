import Foundation

/// Decides which social sign-in buttons the iOS sign-in screen shows, based on the providers that
/// are actually enabled in the production Clerk instance.
///
/// App Store Review Guideline 4.8: an app that offers Google sign-in for the primary account must
/// also offer an equivalent privacy-focused login (Sign in with Apple). So on iOS:
/// - Sign in with Apple appears only when the Apple connection is enabled in Clerk (otherwise the
///   button would fail, which App Review treats as a bug under Guideline 2.1).
/// - Google appears only when Sign in with Apple is available too.
/// - Email and password is always available.
/// When the owner enables Apple in the Clerk dashboard, both buttons appear without an app update.
enum SignInProviderPolicy {
    struct Visible: Equatable {
        let google: Bool
        let apple: Bool
    }

    static func visible(enabledStrategies: Set<String>) -> Visible {
        let apple = enabledStrategies.contains("oauth_apple")
        let google = apple && enabledStrategies.contains("oauth_google")
        return Visible(google: google, apple: apple)
    }

    /// The Clerk Frontend API host is the base64 payload of the publishable key, ending in "$".
    static func frontendAPIHost(fromPublishableKey key: String) -> String? {
        let parts = key.split(separator: "_", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "pk" else { return nil }
        var payload = parts[2]
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        let host = decoded.hasSuffix("$") ? String(decoded.dropLast()) : decoded
        guard !host.isEmpty, !host.contains("/"), host.contains(".") else { return nil }
        return host
    }

    /// Reads `user_settings.social.<strategy>.enabled` from Clerk's public environment document.
    static func enabledStrategies(fromEnvironmentJSON data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = root["user_settings"] as? [String: Any],
              let social = settings["social"] as? [String: Any] else { return [] }
        var result = Set<String>()
        for (strategy, value) in social {
            if let entry = value as? [String: Any], entry["enabled"] as? Bool == true {
                result.insert(strategy)
            }
        }
        return result
    }
}

@MainActor
final class SignInOptions: ObservableObject {
    @Published private(set) var showGoogle = false
    @Published private(set) var showApple = false
    @Published private(set) var loaded = false

    func load() async {
        guard !loaded else { return }
        guard let host = SignInProviderPolicy.frontendAPIHost(fromPublishableKey: AppConfig.clerkPublishableKey),
              let url = URL(string: "https://\(host)/v1/environment") else {
            loaded = true
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let strategies: Set<String>
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                strategies = SignInProviderPolicy.enabledStrategies(fromEnvironmentJSON: data)
            } else {
                strategies = []
            }
        } catch {
            strategies = []
        }
        let visible = SignInProviderPolicy.visible(enabledStrategies: strategies)
        showGoogle = visible.google
        showApple = visible.apple
        loaded = true
    }
}

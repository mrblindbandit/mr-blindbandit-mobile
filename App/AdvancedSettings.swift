import SwiftUI
import Security

struct KeychainStore {
    static let service = "net.mrblindbandit.privateapp.owner-access"

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error { case status(OSStatus) }
}

@MainActor
final class SiteConnectionSettings: ObservableObject {
    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: "apiBaseURL") }
    }
    @Published var publicClientKey: String {
        didSet { UserDefaults.standard.set(publicClientKey, forKey: "publicClientKey") }
    }
    @Published var ownerToken: String = ""
    @Published var statusMessage = ""

    init() {
        apiBaseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "https://api.mrblindbandit.net"
        publicClientKey = UserDefaults.standard.string(forKey: "publicClientKey") ?? ""
        ownerToken = KeychainStore.read(account: "owner-token")
    }

    func saveOwnerToken() {
        do {
            if ownerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainStore.delete(account: "owner-token")
                statusMessage = "Owner token removed from this device."
            } else {
                try KeychainStore.save(ownerToken, account: "owner-token")
                statusMessage = "Owner token saved securely in this device Keychain."
            }
        } catch {
            statusMessage = "The owner token could not be saved."
        }
    }

    func clearOwnerToken() {
        ownerToken = ""
        KeychainStore.delete(account: "owner-token")
        statusMessage = "Owner token removed from this device."
    }
}

struct AdvancedSettingsView: View {
    @StateObject private var site = SiteConnectionSettings()
    @State private var revealToken = false

    var body: some View {
        Form {
            Section("Site connection") {
                TextField("API base URL", text: $site.apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .accessibilityHint("The HTTPS address used for Mr. Blind Bandit API requests.")

                TextField("Public client key", text: $site.publicClientKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityHint("A public client identifier that is safe to ship in the app.")
            }

            Section("Private owner access") {
                Group {
                    if revealToken {
                        TextField("Owner access token", text: $site.ownerToken)
                    } else {
                        SecureField("Owner access token", text: $site.ownerToken)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityHint("Stored only in the iPhone Keychain when you choose Save owner token.")

                Toggle("Show owner token", isOn: $revealToken)
                Button("Save owner token") { site.saveOwnerToken() }
                Button("Remove owner token", role: .destructive) { site.clearOwnerToken() }
                    .disabled(site.ownerToken.isEmpty && KeychainStore.read(account: "owner-token").isEmpty)

                Text("Use a short-lived, scoped owner token here. Do not put a permanent master server secret in an iPhone app; client apps can be inspected. The token is stored with This Device Only Keychain protection and is not written to UserDefaults.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Connection policy") {
                LabeledContent("Primary site", value: "mrblindbandit.net")
                LabeledContent("Transport", value: "HTTPS only")
                LabeledContent("Private token storage", value: "iOS Keychain")
                LabeledContent("Public settings storage", value: "On device")
            }

            if !site.statusMessage.isEmpty {
                Section("Status") {
                    Text(site.statusMessage)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .navigationTitle("Advanced Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

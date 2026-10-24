import SwiftUI
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Encryption passcode (2.0.6). The identity is wrapped with PBKDF2-SHA256 (600 000 iterations) + AES-GCM on this
/// iPhone; only the ciphertext is stored on the server (PUT /v1/keys/backup). Restoring on a new device or after a
/// reinstall keeps the same identity, so the security number doesn't change.
enum EncryptionPasscode {
    static func key(_ handle: String) -> String { "e2ee.passcodeSet.\(handle.lowercased())" }
    static func isSet(_ handle: String) -> Bool { UserDefaults.standard.bool(forKey: key(handle)) }
    static func markSet(_ handle: String) { UserDefaults.standard.set(true, forKey: key(handle)) }
    static func isValid(_ p: String) -> Bool { p.count >= 6 && p.allSatisfy { $0.isLetter || $0.isNumber } }

    /// Server stores base64url ciphertext + a kdf object (returned as a JSON string).
    static func seal(_ identity: Data, pass: String) throws -> [String: Any] {
        let salt = E2EECrypto.random(16)
        let box = try AES.GCM.seal(identity, using: RecoveryPassphrase.derive(pass, salt: salt))
        return ["ciphertext": E2EECrypto.b64u(box.combined!),
                "kdf": ["v": 1, "alg": "pbkdf2-sha256", "iterations": 600_000, "salt": E2EECrypto.b64u(salt), "aead": "aes-256-gcm"]]
    }

    static func open(_ backup: [String: Any], pass: String) -> Data? {
        var kdf = backup["kdf"] as? [String: Any]
        if kdf == nil, let s = backup["kdf"] as? String, let d = s.data(using: .utf8) { kdf = try? JSONSerialization.jsonObject(with: d) as? [String: Any] }
        guard let saltS = kdf?["salt"] as? String, let salt = try? E2EECrypto.unb64u(saltS),
              let cS = backup["ciphertext"] as? String, let c = try? E2EECrypto.unb64u(cS),
              let sealed = try? AES.GCM.SealedBox(combined: c) else { return RecoveryPassphrase.unwrap(backup, pass: pass) }
        return try? AES.GCM.open(sealed, using: RecoveryPassphrase.derive(pass, salt: salt))
    }
}

struct EncryptionPasscodePrompt: ViewModifier {
    @ObservedObject private var e2ee = E2EEService.shared
    func body(content: Content) -> some View {
        content.sheet(isPresented: $e2ee.needsPasscode) {
            NavigationStack { EncryptionPasscodeView() }.interactiveDismissDisabled(false)
        }
    }
}

struct EncryptionPasscodeView: View {
    enum Mode { case loading, create, restore }
    @ObservedObject private var e2ee = E2EEService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .loading
    @State private var backup: [String: Any] = [:]
    @State private var pass = ""
    @State private var confirm = ""
    @State private var status = ""
    @State private var busy = false
    @State private var confirmForgot = false
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        Form {
            switch mode {
            case .loading:
                ProgressView("Checking for an encryption backup…")
            case .create:
                Section {
                    SecureField("Passcode, at least 6 digits or letters", text: $pass).textContentType(.newPassword)
                    SecureField("Enter it again", text: $confirm).textContentType(.newPassword)
                    Button("Create passcode") { Task { await create() } }
                        .disabled(busy || !EncryptionPasscode.isValid(pass) || pass != confirm)
                } header: { Text("Create your encryption passcode").accessibilityAddTraits(.isHeader) } footer: {
                    Text("Use 6 or more digits or letters. It protects a server backup of your encryption keys. Your identity also syncs through iCloud Keychain (end-to-end encrypted by Apple), so a new iPhone on the same Apple Account can restore automatically. We can't see your passcode or reset it for you.")
                }
            case .restore:
                Section {
                    SecureField("Encryption passcode", text: $pass).textContentType(.password)
                    Button("Restore my keys") { Task { await restore() } }.disabled(busy || pass.count < 6)
                    Button("Restore from iCloud Keychain") { Task { await restoreFromICloud() } }
                        .accessibilityHint("Uses the encryption identity already synced to this Apple Account. Prefer this before resetting.")
                    Button("Forgot passcode", role: .destructive) { confirmForgot = true }
                } header: { Text("Enter your encryption passcode").accessibilityAddTraits(.isHeader) } footer: {
                    Text("This restores your encryption keys so your contacts' security numbers stay the same. Try iCloud Keychain first if you forgot the passcode — resetting creates a new security number.")
                }
            }
            if !status.isEmpty {
                Section { Text(status).accessibilityFocused($statusFocused) }
            }
        }
        .navigationTitle("Encryption passcode")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } } }
        .task { await loadBackup() }
        .confirmationDialog("Reset your encryption keys? Try Restore from iCloud Keychain first. Resetting means your contacts will see that your security number changed, and old encrypted messages may not open on this iPhone.",
                            isPresented: $confirmForgot, titleVisibility: .visible) {
            Button("Try iCloud Keychain first") { Task { await restoreFromICloud() } }
            Button("Reset keys anyway", role: .destructive) { forgot() }
        }
    }

    private func say(_ s: String) {
        status = s
        statusFocused = true
        UIAccessibility.post(notification: .announcement, argument: s)
    }

    private func loadBackup() async {
        if let d = try? await BlindbanditAPI.request("v1/keys/backup"),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let inner = (o["data"] as? [String: Any]) ?? o
            if inner["ciphertext"] != nil || inner["blob"] != nil { backup = inner; mode = .restore; return }
        }
        mode = .create
    }

    private func create() async {
        guard let id = IdentityStore.shared.exportIdentity() else { say("Your keys aren't ready yet. Try again in a moment."); return }
        busy = true; defer { busy = false }
        do {
            let body = try EncryptionPasscode.seal(id, pass: pass)
            _ = try await BlindbanditAPI.request("v1/keys/backup", method: "PUT", body: body)
            EncryptionPasscode.markSet(e2ee.myHandle)
            pass = ""; confirm = ""
            say("Encryption passcode created.")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch { say("Couldn't save the backup: \(error.localizedDescription)") }
    }

    private func restore() async {
        busy = true; defer { busy = false }
        guard let data = EncryptionPasscode.open(backup, pass: pass) else { say("That passcode didn't work. Try again."); return }
        if data != IdentityStore.shared.exportIdentity() {
            guard IdentityStore.shared.importIdentity(data) else { say("The backup couldn't be read."); return }
            await e2ee.bootstrap(handle: e2ee.myHandle)
        }
        EncryptionPasscode.markSet(e2ee.myHandle)
        pass = ""
        say("Your encryption keys are restored. Your security numbers stay the same.")
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        dismiss()
    }

    /// Prefer keeping the iCloud-synced identity: clear only the passcode-set flag and go to create.
    private func restoreFromICloud() async {
        busy = true; defer { busy = false }
        // IdentityStore already reads the synchronizable Keychain item. If it is present, keep it.
        if IdentityStore.shared.identity(handle: e2ee.myHandle, createIfMissing: false) != nil {
            UserDefaults.standard.set(false, forKey: EncryptionPasscode.key(e2ee.myHandle))
            await e2ee.bootstrap(handle: e2ee.myHandle)
            mode = .create
            pass = ""; confirm = ""
            let fromCloud = IdentityStore.shared.restoredFromICloud
            say(fromCloud
                ? "Restored encryption keys from iCloud Keychain. Create a new passcode to protect the backup."
                : "Encryption keys are still on this iPhone. Create a new passcode to protect the backup. Your security number stays the same.")
            return
        }
        say("No encryption keys found in iCloud Keychain on this Apple Account. You can reset to create new keys.")
    }

    private func forgot() {
        // Last resort after the user confirms they do not want iCloud restore.
        IdentityStore.shared.resetIdentity()
        KeySetupLog.record("Encryption keys reset after forgotten passcode.")
        Task {
            await e2ee.bootstrap(handle: e2ee.myHandle)
            mode = .create
            say("New keys created. Now create a new encryption passcode.")
        }
    }
}

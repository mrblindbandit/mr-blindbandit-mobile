import SwiftUI
import UIKit
import AVFoundation
import CryptoKit
import CommonCrypto

/// QR scanner for safety numbers. VoiceOver announces the result; there is a manual "Mark as verified" fallback.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerVC { let v = ScannerVC(); v.onCode = onCode; return v }
    func updateUIViewController(_ vc: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var done = false
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            view.accessibilityLabel = "Camera. Point it at the other person's safety number QR code."
            view.isAccessibilityElement = true
            guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.frame = view.bounds
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            done = true
            onCode?(s)
        }
    }
}

/// App-level protections (§23).
enum AppSecurity {
    static let relockKey = "sec.relockSeconds"
    static let blurKey = "sec.blurSwitcher"
    static var relockSeconds: Int { UserDefaults.standard.object(forKey: relockKey) as? Int ?? -1 } // -1 = cold launch only (1.8 behaviour)
    static var blurSwitcher: Bool { UserDefaults.standard.object(forKey: blurKey) as? Bool ?? true }

    /// Best-effort jailbreak heuristics: warn only, never block.
    static var looksJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let paths = ["/Applications/Cydia.app", "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash", "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt/", "/var/jb"]
        if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return true }
        let probe = "/private/bb_jb_probe.txt"
        if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probe)
            return true
        }
        return false
        #endif
    }
}

/// Optional recovery passphrase (§13, off by default). It wraps the identity with a PBKDF2-SHA256 (600k) derived key and
/// AES-GCM. The wrapped blob is uploaded via PUT v1/keys/backup when that route exists.
enum RecoveryPassphrase {
    static func derive(_ pass: String, salt: Data) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(pass.utf8)
        _ = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                 s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, &out, 32)
        }
        return SymmetricKey(data: out)
    }

    static func wrap(identity: Data, pass: String) throws -> [String: Any] {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let box = try AES.GCM.seal(identity, using: derive(pass, salt: salt))
        let c = box.combined!.base64EncodedString()
        return ["v": 1, "kdf": "pbkdf2-sha256", "iterations": 600_000, "salt": salt.base64EncodedString(),
                "blob": c, "ciphertext": c,
                "metadata": ["v": 1, "kdf": "pbkdf2-sha256", "iterations": 600_000, "salt": salt.base64EncodedString()]]
    }

    static func unwrap(_ blob: [String: Any], pass: String) -> Data? {
        let blob = (blob["data"] as? [String: Any]) ?? blob
        let meta = blob["metadata"] as? [String: Any] ?? [:]
        guard let s = ((blob["salt"] ?? meta["salt"]) as? String).flatMap({ Data(base64Encoded: $0) }),
              let b = ((blob["ciphertext"] ?? blob["blob"]) as? String).flatMap({ Data(base64Encoded: $0) }),
              let sealed = try? AES.GCM.SealedBox(combined: b) else { return nil }
        return try? AES.GCM.open(sealed, using: derive(pass, salt: s))
    }
}

struct AppSecurityView: View {
    @AppStorage(AppSecurity.relockKey) private var relock = -1
    @AppStorage(AppSecurity.blurKey) private var blur = true
    @AppStorage("sec.recoveryEnabled") private var recoveryEnabled = false
    @ObservedObject private var e2ee = E2EEService.shared
    @State private var pass = ""
    @State private var status = ""
    @State private var confirmReset = false

    var body: some View {
        Form {
            if AppSecurity.looksJailbroken {
                Section { Label("This iPhone looks jailbroken. Other apps may be able to read your messages.", systemImage: "exclamationmark.shield.fill").foregroundStyle(.orange) }
            }
            Section {
                Picker("Lock again after", selection: $relock) {
                    Text("Only when the app restarts").tag(-1)
                    Text("Immediately").tag(0)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3600)
                }
                Toggle("Hide content in the app switcher", isOn: $blur)
            } header: { Text("App lock").accessibilityAddTraits(.isHeader) }
            Section {
                NavigationLink { DevicesSessionsView() } label: { Label("Devices and sessions", systemImage: "iphone.and.arrow.forward") }
                NavigationLink { AppPINSettingsView() } label: { Label("PIN and duress PIN", systemImage: "number.square") }
                NavigationLink { HistoryBackupView() } label: { Label("Message history backup", systemImage: "clock.arrow.circlepath") }
                NavigationLink { AIChatBackupView() } label: { Label("AI chat backup", systemImage: "sparkles") }
                NavigationLink { FoldersManagerView() } label: { Label("Chat folders and hidden chats", systemImage: "folder") }
                LabeledContent("This device", value: IdentityStore.shared.deviceID ?? "Not registered")
                LabeledContent("Encryption", value: e2ee.ready ? "On, keys in iCloud Keychain" : (ServerFeatures.shared.isAvailable(.keys) ? "Setting up" : ServerFeatures.needsUpdateText))
                Button("Reset encryption keys on this device", role: .destructive) { confirmReset = true }
            } header: { Text("Encryption keys").accessibilityAddTraits(.isHeader) } footer: {
                Text("Your identity key syncs through iCloud Keychain (end-to-end encrypted by Apple), so signing in on a new iPhone restores it automatically.")
            }
            Section {
                Toggle("Recovery passphrase", isOn: $recoveryEnabled)
                if recoveryEnabled {
                    SecureField("Passphrase (12+ characters)", text: $pass)
                    Button("Save passphrase backup") { Task { await saveBackup() } }
                        .disabled(pass.count < 12 || !ServerFeatures.shared.isAvailable(.keyWrap))
                    if !ServerFeatures.shared.isAvailable(.keyWrap) { Text(ServerFeatures.needsUpdateText) }
                }
            } header: { Text("Recovery").accessibilityAddTraits(.isHeader) } footer: {
                Text("Off by default. Only needed if you don't use iCloud Keychain. If you forget it, nobody can recover your keys.")
            }
            if !status.isEmpty { Section { Text(status) } }
        }
        .navigationTitle("Security")
        .confirmationDialog("Reset keys on this device? Your contacts will see a safety number change.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { IdentityStore.shared.resetDevice(); Task { await e2ee.bootstrap(handle: e2ee.myHandle) } }
        }
    }

    private func saveBackup() async {
        guard let id = Keychain.get("identity.v1") else { status = "No identity yet."; return }
        do {
            let blob = try RecoveryPassphrase.wrap(identity: id, pass: pass)
            try await SecurityAPI.gated(.keyWrap) {
                _ = try await BlindbanditAPI.request("v1/keys/backup", method: "PUT", body: blob)
            }
            pass = ""
            status = "Recovery backup saved."
        } catch { status = (error as? NeedsServerUpdate) != nil ? ServerFeatures.needsUpdateText : error.localizedDescription }
        UIAccessibility.post(notification: .announcement, argument: status)
    }
}

struct DevicesSessionsView: View {
    @State private var sessions: [SessionInfo] = []
    @State private var note = ""
    var body: some View {
        List {
            if !note.isEmpty { Text(note) }
            ForEach(sessions) { s in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(s.device_name), \(s.platform)" + (s.current ? " (this device)" : ""))
                        if let seen = s.last_active_at { Text("Last active \(Date(timeIntervalSince1970: seen > 100_000_000_000 ? seen / 1000 : seen).formatted())").font(.caption) }
                    }
                    Spacer()
                    if !s.current {
                        Button("Sign out", role: .destructive) { Task {
                            try? await SecurityAPI.signOut(session: s.id)
                            UIAccessibility.post(notification: .announcement, argument: "Signed out \(s.device_name)")
                            await load()
                        } }.buttonStyle(.borderless)
                    }
                }.accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Devices and sessions")
        .task { await load() }
    }
    private func load() async {
        do { sessions = try await SecurityAPI.sessions(); note = "" }
        catch is NeedsServerUpdate { note = ServerFeatures.needsUpdateText } catch { note = error.localizedDescription }
    }
}

struct AISettingsView: View {
    @State private var refresh = 0
    var body: some View {
        Form {
            Section {
                Label(OnDeviceAI.isAvailable ? "Apple Intelligence is ready on this iPhone" : OnDeviceAI.unavailableReason,
                      systemImage: OnDeviceAI.isAvailable ? "checkmark.seal" : "info.circle")
            } footer: { Text("Every AI feature runs on this iPhone. Your messages are never sent to a server for AI.") }
            AIStyleSection()
            CloudAISection()
            Section("Music debug log") {
                Text(MusicLog.lastError.isEmpty ? "No Apple Music errors." : MusicLog.lastError)
                    .font(.footnote).textSelection(.enabled)
            }
            Section {
                Toggle("Allow AI web search", isOn: Binding(get: { WebSearch.allowed }, set: { WebSearch.allowed = $0; AIChatStore.shared.resetSession() }))
            } header: { Text("Web search").accessibilityAddTraits(.isHeader) } footer: {
                Text("When the AI needs current information it sends only a short search query through mrblindbandit.net. Your chats and messages are never sent.")
            }
            Section {
                ForEach(AISettings.Feature.allCases, id: \.self) { f in
                    Toggle(f.title, isOn: Binding(get: { _ = refresh; return AISettings.isOn(f) }, set: { AISettings.set(f, $0); refresh += 1 }))
                }
            } header: { Text("Features").accessibilityAddTraits(.isHeader) }
            Section {
                TranslationDownloadButton(source: "en", target: Locale.current.language.languageCode?.identifier ?? "en")
                NavigationLink { NaturalVoicesInfo() } label: { Text("Natural voices") }
            } header: { Text("Translation and voices").accessibilityAddTraits(.isHeader) } footer: {
                Text("Cebuano and Tagalog use the on-device language model when Apple Translation doesn't support them.")
            }
        }
        .navigationTitle("AI")
    }
}

struct NaturalVoicesInfo: View {
    var body: some View {
        List {
            Text("Current voice: \(NaturalReader.shared.bestVoice(for: LanguageID.deviceLanguage)?.name ?? "Default")")
            Text("Download Premium or Enhanced voices in Settings > Accessibility > Spoken Content > Voices. Personal Voice can be used after you allow it.")
            Button("Allow Personal Voice") { AVSpeechSynthesizer.requestPersonalVoiceAuthorization { _ in } }
            Button("Preview") { NaturalReader.shared.speak("This is how messages will sound.") }
        }
        .navigationTitle("Natural voices")
    }
}

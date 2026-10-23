import Foundation
import SwiftUI
import LocalAuthentication
import CryptoKit
import UIKit

// MARK: - Notes to self (encrypted on device, mirrored to the server self-chat when that route exists)

@MainActor
enum NotesToSelf {
    static var notes: [LocalMessageStore.NoteToSelf] { LocalMessageStore.shared.snapshot.notes }
    static func add(_ text: String, transcript: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        LocalMessageStore.shared.mutate { $0.notes.append(.init(body: t, createdAt: Date().timeIntervalSince1970, transcript: transcript)) }
        Task { _ = try? await SecurityAPI.gated(.envelopeFetch) { try await BlindbanditAPI.request("v1/social/messages/self", method: "POST", body: ["body": t, "kind": "note"]) } }
    }
    static func delete(_ id: String) { LocalMessageStore.shared.mutate { $0.notes.removeAll { $0.id == id } } }
}

struct NotesToSelfView: View {
    @State private var draft = ""
    @State private var notes = NotesToSelf.notes
    @StateObject private var dictation = LiveDictation()
    var body: some View {
        VStack(spacing: 0) {
            List {
                if notes.isEmpty { Text("Jot down anything: links, ideas, lists. Notes are encrypted on this iPhone.") }
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.body)
                        Text(Date(timeIntervalSince1970: n.createdAt).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Read aloud") { NaturalReader.shared.speak(n.body) }
                    .accessibilityAction(named: "Copy") { UIPasteboard.general.string = n.body }
                    .accessibilityAction(named: "Delete") { NotesToSelf.delete(n.id); notes = NotesToSelf.notes }
                    .swipeActions { Button("Delete", role: .destructive) { NotesToSelf.delete(n.id); notes = NotesToSelf.notes } }
                }
            }
            HStack {
                Button { Task { if dictation.isListening { dictation.stop(); draft = dictation.text } else { await dictation.start() } } } label: {
                    Image(systemName: dictation.isListening ? "stop.circle.fill" : "mic.circle").font(.title2)
                }.accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate note")
                TextField("Note to self", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder)
                Button { NotesToSelf.add(draft); draft = ""; notes = NotesToSelf.notes; UIAccessibility.post(notification: .announcement, argument: "Saved") } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }.accessibilityLabel("Save note").disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding()
        }
        .navigationTitle("Notes to self")
        .onChange(of: dictation.text) { _, t in if dictation.isListening { draft = t } }
    }
}

struct NotesToSelfRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text").font(.title2).frame(width: 44, height: 44).background(Circle().fill(Color.secondary.opacity(0.15)))
            VStack(alignment: .leading) {
                Text("Notes to self").font(.headline)
                Text(NotesToSelf.notes.last?.body ?? "Your private notes").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notes to self, pinned. " + (NotesToSelf.notes.last.map { "Last: \($0.body)" } ?? ""))
    }
}

// MARK: - Polls (E2EE: poll + vote payloads travel in envelopes; plaintext groups use the server poll routes)

enum PollSender {
    @MainActor
    static func send(question: String, options: [String], multiple: Bool, chat: ChatRef, handle: String) async -> Bool {
        let payload = E2EEPayload(t: "poll", body: question, poll: .init(question: question, options: options, multiple: multiple))
        switch chat {
        case .group(let gid):
            if (try? await E2EEService.shared.sendGroup(id: gid, payload: payload)) == true { return true }
            let r = try? await SecurityAPI.gated(.polls) {
                try await BlindbanditAPI.request("v1/social/groups/\(ChatRef.escape(gid))/polls", method: "POST",
                                                 body: ["question": question, "options": options, "multi": multiple, "anonymous": false])
            }
            if r != nil { return true }
        case .dm:
            if (try? await E2EEService.shared.sendDM(handle: handle, payload: payload, chatKey: chat.key)) != nil { return true }
        }
        // Last resort: a readable text poll so the chat still works.
        let text = "📊 Poll: \(question)\n" + options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\nReply with a number."
        if case .group(let gid) = chat { return (try? await BlindbanditAPI.sendGroupMessage(id: gid, body: text)) != nil }
        return (try? await BlindbanditAPI.sendMessage(handle: handle, body: text)) != nil
    }

    @MainActor
    static func vote(pollMsgID: String, options: [Int], chat: ChatRef, handle: String, me: String) async {
        LocalMessageStore.shared.mutate { $0.votes[pollMsgID, default: [:]][me] = options }
        let p = E2EEPayload(t: "vote", vote: options, target_msg_id: pollMsgID)
        if case .group(let gid) = chat { _ = try? await E2EEService.shared.sendGroup(id: gid, payload: p) }
        else { _ = try? await E2EEService.shared.sendDM(handle: handle, payload: p, chatKey: chat.key) }
        UIAccessibility.post(notification: .announcement, argument: "Vote sent")
    }
}

struct PollComposerSheet: View {
    let chat: ChatRef
    let handle: String
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var multiple = false
    @State private var sending = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Question") { TextField("Ask something", text: $question) }
                Section("Options") {
                    ForEach(options.indices, id: \.self) { i in TextField("Option \(i + 1)", text: $options[i]) }
                    if options.count < 12 { Button("Add option") { options.append("") } }
                }
                Toggle("Allow more than one answer", isOn: $multiple)
            }
            .navigationTitle("New poll")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sending = true
                        let opts = options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        Task {
                            let ok = await PollSender.send(question: question, options: opts, multiple: multiple, chat: chat, handle: handle)
                            UIAccessibility.post(notification: .announcement, argument: ok ? "Poll sent" : "Poll not sent")
                            dismiss()
                        }
                    }
                    .disabled(sending || question.isEmpty || options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count < 2)
                }
            }
        }
    }
}

struct PollCard: View {
    let poll: E2EEPayload.Poll
    let msgID: String
    let chat: ChatRef
    let handle: String
    let me: String
    @State private var tick = 0
    var body: some View {
        let votes = LocalMessageStore.shared.snapshot.votes[msgID] ?? [:]
        let mine = Set(votes[me] ?? [])
        let total = max(1, votes.count)
        VStack(alignment: .leading, spacing: 8) {
            Text("Poll: \(poll.question)").font(.headline)
            ForEach(Array(poll.options.enumerated()), id: \.offset) { i, opt in
                let n = votes.values.filter { $0.contains(i) }.count
                Button {
                    var pick = mine
                    if poll.multiple == true { if pick.contains(i) { pick.remove(i) } else { pick.insert(i) } } else { pick = [i] }
                    Task { await PollSender.vote(pollMsgID: msgID, options: Array(pick).sorted(), chat: chat, handle: handle, me: me); tick += 1 }
                } label: {
                    HStack {
                        Image(systemName: mine.contains(i) ? "checkmark.circle.fill" : "circle")
                        Text(opt)
                        Spacer()
                        Text("\(n)")
                    }
                }
                .accessibilityLabel("\(opt), \(n) vote\(n == 1 ? "" : "s"), \(n * 100 / total) percent\(mine.contains(i) ? ", your vote" : "")")
                .accessibilityAddTraits(mine.contains(i) ? .isSelected : [])
            }
            Text(poll.multiple == true ? "Choose one or more" : "Choose one").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .id(tick)
    }
}

// MARK: - Folders and the hidden folder (Face ID to open)

struct ChatFolder: Codable, Identifiable, Equatable, Hashable {
    var id = UUID().uuidString
    var name: String
    var chatKeys: [String] = []
    var hidden = false
    var order = 0
}

@MainActor
final class ChatFolders: ObservableObject {
    static let shared = ChatFolders()
    @Published private(set) var folders: [ChatFolder] = []
    @Published var hiddenUnlocked = false
    private let key = "chatFolders.v1"

    init() {
        folders = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([ChatFolder].self, from: $0) } ?? []
        if !folders.contains(where: { $0.hidden }) { folders.append(ChatFolder(name: "Hidden", hidden: true, order: 99)) }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(folders), forKey: key)
        let body: [[String: Any]] = folders.map { ["id": $0.id, "name": $0.name, "chat_keys": $0.chatKeys, "hidden": $0.hidden, "order": $0.order] }
        Task { _ = try? await SecurityAPI.gated(.folders) { try await BlindbanditAPI.request("v1/social/folders", method: "PUT", body: ["folders": body]) } }
    }

    func add(_ name: String) { folders.append(ChatFolder(name: name, order: folders.count)); save() }
    func remove(_ f: ChatFolder) { guard !f.hidden else { return }; folders.removeAll { $0.id == f.id }; save() }
    func toggle(_ chatKey: String, in f: ChatFolder) {
        guard let i = folders.firstIndex(of: f) else { return }
        if let j = folders[i].chatKeys.firstIndex(of: chatKey) { folders[i].chatKeys.remove(at: j) } else { folders[i].chatKeys.append(chatKey) }
        save()
    }
    var hiddenKeys: Set<String> { Set(folders.filter { $0.hidden }.flatMap { $0.chatKeys }) }
    func isHidden(_ chatKey: String) -> Bool { hiddenKeys.contains(chatKey) }

    func unlockHidden() async {
        hiddenUnlocked = await ChatLock.authenticate(reason: "Open your hidden chats")
        UIAccessibility.post(notification: .announcement, argument: hiddenUnlocked ? "Hidden chats shown" : "Not unlocked")
    }
}

struct FolderAssignMenu: View {
    let chatKey: String
    @ObservedObject private var store = ChatFolders.shared
    var body: some View {
        ForEach(store.folders) { f in
            Button { store.toggle(chatKey, in: f) } label: {
                Label(f.chatKeys.contains(chatKey) ? "Remove from \(f.name)" : (f.hidden ? "Hide chat (Face ID to open)" : "Add to \(f.name)"),
                      systemImage: f.hidden ? "eye.slash" : "folder")
            }
        }
    }
}

struct FoldersManagerView: View {
    @ObservedObject private var store = ChatFolders.shared
    @State private var newName = ""
    var body: some View {
        Form {
            Section("Folders") {
                ForEach(store.folders) { f in
                    HStack { Text(f.name); Spacer(); Text("\(f.chatKeys.count) chats").foregroundStyle(.secondary) }
                        .accessibilityElement(children: .combine)
                        .swipeActions { if !f.hidden { Button("Delete", role: .destructive) { store.remove(f) } } }
                        .accessibilityAction(named: "Delete folder") { store.remove(f) }
                }
                HStack {
                    TextField("New folder name", text: $newName)
                    Button("Add") { store.add(newName); newName = "" }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section { Text("Chats in Hidden never appear in your list until you unlock with Face ID. Add chats to folders from a chat's settings.") }
        }
        .navigationTitle("Chat folders")
    }
}

// MARK: - Duress / decoy PIN for the app lock

/// Optional app PIN. Entering the duress PIN instead opens an empty decoy app: no chats, no AI history, no notes.
@MainActor
enum AppPIN {
    // Hashes live in the keychain; if the keychain is unavailable (simulator test host) they fall back to defaults.
    private static func load(_ k: String) -> Data? { Keychain.get(k) ?? UserDefaults.standard.data(forKey: k) }
    private static func save(_ d: Data, _ k: String) { if !Keychain.set(d, account: k) { UserDefaults.standard.set(d, forKey: k) } }
    private static func remove(_ k: String) { Keychain.delete(k); UserDefaults.standard.removeObject(forKey: k) }
    static var isSet: Bool { load("pin.real.v1") != nil }
    static var duressSet: Bool { load("pin.duress.v1") != nil }
    static var decoyActive: Bool {
        get { UserDefaults.standard.bool(forKey: "pin.decoyActive") }
        set { UserDefaults.standard.set(newValue, forKey: "pin.decoyActive") }
    }
    private static func hash(_ pin: String) -> Data {
        let salt = load("pin.salt.v1") ?? { let s = E2EECrypto.random(16); save(s, "pin.salt.v1"); return s }()
        return Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
    static func set(real: String) { save(hash(real), "pin.real.v1") }
    static func set(duress: String) { save(hash(duress), "pin.duress.v1") }
    static func clear() { remove("pin.real.v1"); remove("pin.duress.v1"); decoyActive = false }
    enum Result { case real, duress, wrong }
    static func check(_ pin: String) -> Result {
        let h = hash(pin)
        if let r = load("pin.real.v1"), r == h { decoyActive = false; return .real }
        if let d = load("pin.duress.v1"), d == h { decoyActive = true; return .duress }
        return .wrong
    }
}

struct AppPINSettingsView: View {
    @State private var real = ""
    @State private var duress = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section {
                SecureField("App PIN (4 to 8 digits)", text: $real).keyboardType(.numberPad)
                Button("Save app PIN") { AppPIN.set(real: real); real = ""; status = "App PIN saved"; announce() }.disabled(real.count < 4)
            } header: { Text("App PIN").accessibilityAddTraits(.isHeader) } footer: { Text("Unlock with this PIN when Face ID isn't available or you prefer a PIN.") }
            Section {
                SecureField("Duress PIN (different from app PIN)", text: $duress).keyboardType(.numberPad)
                Button("Save duress PIN") { AppPIN.set(duress: duress); duress = ""; status = "Duress PIN saved"; announce() }.disabled(duress.count < 4 || !AppPIN.isSet)
            } header: { Text("Duress PIN").accessibilityAddTraits(.isHeader) } footer: {
                Text("If someone forces you to unlock, enter the duress PIN. The app opens with no chats, no AI history and no notes. Your real data stays safe and returns next time you unlock with your real PIN or Face ID.")
            }
            if AppPIN.isSet { Button("Remove PINs", role: .destructive) { AppPIN.clear(); status = "PINs removed"; announce() } }
            if !status.isEmpty { Text(status) }
        }
        .navigationTitle("PIN and duress PIN")
    }
    private func announce() { UIAccessibility.post(notification: .announcement, argument: status) }
}

struct PINEntryView: View {
    let onResult: (AppPIN.Result) -> Void
    @State private var pin = ""
    @State private var wrong = false
    var body: some View {
        VStack(spacing: 12) {
            SecureField("Enter app PIN", text: $pin).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
            Button("Unlock with PIN") {
                let r = AppPIN.check(pin); pin = ""
                if r == .wrong { wrong = true; UIAccessibility.post(notification: .announcement, argument: "Wrong PIN") }
                onResult(r)
            }.disabled(pin.count < 4)
            if wrong { Text("Wrong PIN").foregroundStyle(.red) }
        }
    }
}

// MARK: - Encrypted message-history backup and restore (SPEC §13)

/// Backs up the decrypted-message cache, encrypted with a key that lives only in the synced iCloud Keychain, to
/// PUT v1/backups/history. A new iPhone gets the key through iCloud Keychain and restores automatically.
@MainActor
enum HistoryBackup {
    private static var key: SymmetricKey {
        if let d = Keychain.get("history-backup-key.v1"), d.count == 32 { return SymmetricKey(data: d) }
        let d = E2EECrypto.random(32)
        _ = Keychain.set(d, account: "history-backup-key.v1", synced: true)
        return SymmetricKey(data: d)
    }
    static var lastBackup: Date? { UserDefaults.standard.object(forKey: "history.lastBackup") as? Date }

    static func backup() async -> String {
        guard let plain = try? JSONEncoder().encode(LocalMessageStore.shared.snapshot),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return "Couldn't prepare the backup." }
        do {
            _ = try await SecurityAPI.gated(.historyBackup) {
                try await BlindbanditAPI.request("v1/backups/history", method: "PUT",
                    body: BackupEnvelope.body(sealed, kind: "history"))
            }
            UserDefaults.standard.set(Date(), forKey: "history.lastBackup")
            return "Backed up \(LocalMessageStore.shared.snapshot.payloads.count) messages."
        } catch is NeedsServerUpdate { return "History backup: " + ServerFeatures.needsUpdateText } catch { return error.localizedDescription }
    }

    /// Called once after sign-in on a device with an empty cache.
    static func restoreIfNeeded() async {
        guard LocalMessageStore.shared.snapshot.payloads.isEmpty, !UserDefaults.standard.bool(forKey: "history.restoredOnce") else { return }
        _ = await restore()
    }

    static func restore() async -> String {
        guard let data = try? await SecurityAPI.gated(.historyBackup, { try await BlindbanditAPI.request("v1/backups/history") }),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              case let inner = (obj["data"] as? [String: Any]) ?? obj,
              let b64 = (inner["blob"] as? String) ?? (inner["ciphertext"] as? String),
              let blob = Data(base64Encoded: b64), let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key),
              let snap = try? JSONDecoder().decode(LocalMessageStore.Snapshot.self, from: plain) else { return "No history backup found yet." }
        LocalMessageStore.shared.mutate { s in
            s.payloads.merge(snap.payloads) { a, _ in a }; s.senders.merge(snap.senders) { a, _ in a }
            s.starred.formUnion(snap.starred); s.notes += snap.notes.filter { n in !s.notes.contains { $0.id == n.id } }
            s.votes.merge(snap.votes) { a, _ in a }; s.pinned.merge(snap.pinned) { a, _ in a }
        }
        UserDefaults.standard.set(true, forKey: "history.restoredOnce")
        return "Restored \(snap.payloads.count) messages."
    }
}

struct HistoryBackupView: View {
    @State private var status = ""
    @AppStorage("history.autoBackup") private var auto = true
    var body: some View {
        Form {
            Toggle("Back up message history automatically", isOn: $auto)
            Button("Back up now") { Task { status = await HistoryBackup.backup(); UIAccessibility.post(notification: .announcement, argument: status) } }
            Button("Restore from backup") { Task { status = await HistoryBackup.restore(); UIAccessibility.post(notification: .announcement, argument: status) } }
            if let d = HistoryBackup.lastBackup { LabeledContent("Last backup", value: d.formatted()) }
            if !status.isEmpty { Text(status) }
            Section { Text("Your history is encrypted with a key only your iCloud Keychain has. Our server stores an unreadable blob. A new iPhone signed into your Apple Account restores it automatically.") }
        }
        .navigationTitle("Message history backup")
    }
}

// MARK: - Smart search, digest, describe camera

struct SmartSearchView: View {
    @State private var query = ""
    @State private var results: [String] = []
    @State private var searching = false
    var body: some View {
        List {
            Section {
                TextField("Ask, like \"when is the gig\" or \"address Mark sent\"", text: $query)
                    .onSubmit { Task { await run() } }
                Button("Search") { Task { await run() } }.disabled(query.isEmpty || searching)
            }
            if searching { ProgressView("Searching on this iPhone") }
            Section("Results") {
                if results.isEmpty && !searching { Text("No results yet") }
                ForEach(results, id: \.self) { r in Text(r).accessibilityAction(named: "Copy") { UIPasteboard.general.string = r } }
            }
        }
        .navigationTitle("Smart search")
    }
    private func run() async {
        searching = true; defer { searching = false }
        let corpus = AIChatStore.shared.corpus
        let indexed = corpus.enumerated().map { (id: String($0.offset), line: $0.element) }
        var hits = await OnDeviceAI.smartSearch(question: query, corpus: indexed)
        hits = hits.compactMap { id in Int(id).flatMap { $0 < corpus.count ? corpus[$0] : nil } ?? id }
        if hits.isEmpty { hits = AIToolbox.search(query, corpus: corpus).components(separatedBy: "\n").filter { !$0.hasPrefix("I didn't") } }
        results = hits
        UIAccessibility.post(notification: .announcement, argument: "\(results.count) results")
    }
}

/// Daily digest of unread chats, summarized on device. Also offered as a 8 PM local notification.
struct DigestView: View {
    @EnvironmentObject private var comms: ProductionCommunicationsService
    @State private var digest = ""
    var body: some View {
        List {
            Text(digest.isEmpty ? "Building your digest…" : digest)
            Button("Refresh") { Task { await build() } }
        }
        .navigationTitle("Today's digest")
        .task { await build() }
    }
    private func build() async {
        let lines = comms.conversations.compactMap { c -> String? in
            guard let m = c.last_message, m.sender_id != comms.myProfileID else { return nil }
            return "\(c.other?.display_name ?? "Someone"): \(m.body)"
        }
        if lines.isEmpty { digest = "You're all caught up."; return }
        digest = await OnDeviceAI.digest(lines) ?? ("You have \(lines.count) chats waiting. " + lines.prefix(8).joined(separator: ". "))
        UIAccessibility.post(notification: .announcement, argument: digest)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .savedPhotosAlbum
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

struct DescribeCameraView: View {
    @State private var showCamera = false
    @State private var description = ""
    @State private var working = false
    var body: some View {
        List {
            Button { showCamera = true } label: { Label("Take a photo to describe", systemImage: "camera") }
            if working { ProgressView("Looking…") }
            if !description.isEmpty {
                Text(description)
                Button("Ask AI about it") { Task { AIChatStore.shared.lastPhoto = lastImage } }
            }
        }
        .navigationTitle("Describe my camera")
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                lastImage = img
                Task { working = true; description = await AIToolbox.describe(img); working = false
                    UIAccessibility.post(notification: .announcement, argument: description) }
            }.ignoresSafeArea()
        }
    }
    @State private var lastImage: UIImage?
}

// MARK: - Sensitive content (Apple's SensitiveContentAnalysis; active only when the user turned on
// Sensitive Content Warning / Communication Safety and the app has the entitlement)

#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

enum SensitiveContent {
    static func isSensitive(_ image: UIImage) async -> Bool {
        #if canImport(SensitiveContentAnalysis)
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled, let cg = image.cgImage else { return false }
        return (try? await analyzer.analyzeImage(cg))?.isSensitive ?? false
        #else
        return false
        #endif
    }
}

struct SensitiveImageView: View {
    let image: UIImage
    let alt: String
    @State private var sensitive = false
    @State private var revealed = false
    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .blur(radius: sensitive && !revealed ? 40 : 0)
            .overlay { if sensitive && !revealed { Button("This may be sensitive. Show anyway") { revealed = true } .buttonStyle(.borderedProminent) } }
            .accessibilityLabel(sensitive && !revealed ? "Possibly sensitive image, hidden" : alt)
            .task { sensitive = await SensitiveContent.isSensitive(image) }
    }
}


// MARK: - Shared lenient backup envelope ({ciphertext, metadata, updated_at} or {v, blob})

enum BackupEnvelope {
    static func body(_ sealed: Data, kind: String) -> [String: Any] {
        let b64 = sealed.base64EncodedString()
        return ["ciphertext": b64, "metadata": ["v": 1, "alg": "AES-GCM", "kind": kind],
                "v": 1, "blob": b64, "updated_at": Int(Date().timeIntervalSince1970 * 1000)]
    }
    static func ciphertext(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let inner = (obj["data"] as? [String: Any]) ?? (obj["backup"] as? [String: Any]) ?? obj
        guard let b64 = (inner["ciphertext"] as? String) ?? (inner["blob"] as? String) else { return nil }
        return Data(base64Encoded: b64)
    }
}

// MARK: - AI chat backup (v1/backups/ai-chat)

@MainActor
enum AIChatBackup {
    struct Payload: Codable { var lines: [AIChatStore.Line]; var memory: AIChatStore.Memory }
    private static var key: SymmetricKey {
        if let d = Keychain.get("aichat-backup-key.v1"), d.count == 32 { return SymmetricKey(data: d) }
        let d = E2EECrypto.random(32)
        _ = Keychain.set(d, account: "aichat-backup-key.v1", synced: true)
        return SymmetricKey(data: d)
    }
    static var lastBackup: Date? { UserDefaults.standard.object(forKey: "aichat.lastBackup") as? Date }

    static func seal(_ p: Payload, key k: SymmetricKey) -> Data? {
        guard let plain = try? JSONEncoder().encode(p) else { return nil }
        return try? AES.GCM.seal(plain, using: k).combined
    }
    static func open(_ response: Data, key k: SymmetricKey) -> Payload? {
        guard let c = BackupEnvelope.ciphertext(response), let box = try? AES.GCM.SealedBox(combined: c),
              let plain = try? AES.GCM.open(box, using: k) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: plain)
    }

    static func backup() async -> String {
        let s = AIChatStore.shared
        guard let sealed = seal(Payload(lines: s.lines, memory: s.memory), key: key) else { return "Couldn't prepare the AI chat backup." }
        do {
            _ = try await SecurityAPI.gated(.aiBackup) {
                try await BlindbanditAPI.request("v1/backups/ai-chat", method: "PUT", body: BackupEnvelope.body(sealed, kind: "ai-chat"))
            }
            UserDefaults.standard.set(Date(), forKey: "aichat.lastBackup")
            return "AI chat backed up, \(s.lines.count) messages and \(s.memory.facts.count) memories."
        } catch is NeedsServerUpdate { return "AI chat backup: " + ServerFeatures.needsUpdateText } catch { return error.localizedDescription }
    }

    static func restore() async -> String {
        guard let data = try? await SecurityAPI.gated(.aiBackup, { try await BlindbanditAPI.request("v1/backups/ai-chat") }),
              let p = open(data, key: key) else { return "No AI chat backup found yet." }
        AIChatStore.shared.replaceAll(lines: p.lines, memory: p.memory)
        return "AI chat restored, \(p.lines.count) messages."
    }

    /// After sign-in on a new iPhone with an empty AI chat.
    static func restoreIfNeeded() async {
        guard AIChatStore.shared.lines.isEmpty, !UserDefaults.standard.bool(forKey: "aichat.restoredOnce") else { return }
        _ = await restore()
        UserDefaults.standard.set(true, forKey: "aichat.restoredOnce")
    }
}

struct AIChatBackupView: View {
    @State private var status = ""
    var body: some View {
        Form {
            Button("Back up AI chat now") { Task { status = await AIChatBackup.backup(); UIAccessibility.post(notification: .announcement, argument: status) } }
            Button("Restore AI chat from backup") { Task { status = await AIChatBackup.restore(); UIAccessibility.post(notification: .announcement, argument: status) } }
            if let d = AIChatBackup.lastBackup { LabeledContent("Last backup", value: d.formatted()) }
            if !status.isEmpty { Text(status).accessibilityAddTraits(.updatesFrequently) }
            Section { Text("Your AI chat and what it remembers are encrypted with a key in your iCloud Keychain before upload. The server only stores ciphertext.") }
        }
        .navigationTitle("AI chat backup")
    }
}

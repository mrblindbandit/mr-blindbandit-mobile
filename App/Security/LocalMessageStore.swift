import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Decrypted plaintext cache. Message keys are single-use, so the first successful decrypt is stored here,
/// encrypted at rest with a device-only key kept in the keychain (never synced, never sent anywhere).
@MainActor
final class LocalMessageStore {
    static let shared = LocalMessageStore()

    struct RelayMessage: Codable, Equatable {
        var id: String
        var chatKey: String
        var senderID: String
        var senderHandle: String
        var createdAt: Double
        var msgID: String
    }

    struct Snapshot: Codable {
        var payloads: [String: E2EEPayload] = [:]          // envelope msg_id → payload
        var senders: [String: String] = [:]                 // envelope msg_id → sender handle (signer)
        var deleted: Set<String> = []                       // envelope msg_ids or server ids unsent for everyone
        var hiddenForMe: Set<String> = []
        var votes: [String: [String: [Int]]] = [:]          // poll msg_id → voter → option indexes
        var starred: Set<String> = []
        var pinned: [String: [String]] = [:]                // chat key → server message ids
        var expiresAt: [String: Double] = [:]               // msg_id → epoch seconds
        var relay: [String: [RelayMessage]] = [:]           // chat key → relay-only messages kept on device
        var openedViewOnce: Set<String> = []
        var scheduled: [ScheduledMessage] = []
        var notes: [NoteToSelf] = []
    }

    struct ScheduledMessage: Codable, Identifiable, Equatable {
        var id = UUID().uuidString
        var chatKey: String
        var handle: String?
        var groupID: String?
        var body: String
        var sendAt: Double
        var silent: Bool
    }

    struct NoteToSelf: Codable, Identifiable, Equatable {
        var id = UUID().uuidString
        var body: String
        var createdAt: Double
        var transcript: String?
    }

    private(set) var snapshot = Snapshot()
    private var saveTask: Task<Void, Never>?
    private let fileURL: URL

    init(fileName: String = "e2ee-cache.bin") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(fileName)
        load()
    }

    private var key: SymmetricKey {
        if let d = Keychain.get("cache-key.v1"), d.count == 32 { return SymmetricKey(data: d) }
        let d = E2EECrypto.random(32)
        Keychain.set(d, account: "cache-key.v1")
        return SymmetricKey(data: d)
    }

    private func load() {
        guard let blob = try? Data(contentsOf: fileURL), let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: plain) else { return }
        snapshot = s
        purgeExpired()
    }

    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let plain = try? JSONEncoder().encode(snapshot), let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        try? sealed.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func mutate(_ change: (inout Snapshot) -> Void) {
        change(&snapshot)
        saveSoon()
    }

    func payload(_ msgID: String) -> E2EEPayload? { snapshot.payloads[msgID] }

    func store(_ payload: E2EEPayload, msgID: String, sender: String?, expiresIn: Int?) {
        mutate {
            $0.payloads[msgID] = payload
            if let sender { $0.senders[msgID] = sender }
            if let e = expiresIn, e > 0 { $0.expiresAt[msgID] = Date().timeIntervalSince1970 + Double(e) }
        }
    }

    func isDeleted(_ id: String) -> Bool { snapshot.deleted.contains(id) }

    /// Removes everything for a message (unsend / disappearing).
    func forget(_ msgID: String) {
        mutate {
            $0.payloads[msgID] = nil; $0.senders[msgID] = nil; $0.expiresAt[msgID] = nil; $0.votes[msgID] = nil
            $0.deleted.insert(msgID)
            for (k, list) in $0.relay { $0.relay[k] = list.filter { $0.msgID != msgID && $0.id != msgID } }
        }
    }

    func purgeExpired(now: Double = Date().timeIntervalSince1970) {
        let gone = snapshot.expiresAt.filter { $0.value <= now }.map(\.key)
        guard !gone.isEmpty else { return }
        for id in gone { forget(id) }
    }

    func clearChat(_ chatKey: String) {
        mutate { $0.relay[chatKey] = nil; $0.pinned[chatKey] = nil }
    }

    func wipeAll() {
        snapshot = Snapshot()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

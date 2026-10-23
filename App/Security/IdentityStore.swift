import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Zero-setup identity (SPEC §24): generated silently on first launch, synced through iCloud Keychain
/// (kSecAttrSynchronizable) so a new iPhone signed into the same Apple Account restores it automatically (§21).
/// The device ID and prekeys are per device and never synced.
final class IdentityStore {
    static let shared = IdentityStore()

    private struct SyncedIdentity: Codable { var sign: String; var dh: String; var backupKey: String; var createdAt: Double }
    struct PrekeyState: Codable {
        var spkID: Int
        var spk: String
        var spkCreatedAt: Double
        var previousSPK: [Int: String]
        var opks: [Int: String]
        var nextOPK: Int
        var uploaded: Bool
    }

    private let identityAccount = "identity.v1"
    private let deviceAccount = "device.v1"
    private let prekeyAccount = "prekeys.v1"
    private let lock = NSLock()

    /// True when the identity came from iCloud Keychain rather than being created on this device.
    private(set) var restoredFromICloud = false

    func handleKey(_ handle: String) -> String { handle.lowercased() }

    func identity(handle: String, createIfMissing: Bool = true) -> E2EELocalIdentity? {
        lock.lock(); defer { lock.unlock() }
        let synced: SyncedIdentity
        if let existing = Keychain.getCodable(SyncedIdentity.self, identityAccount) {
            synced = existing
            if Keychain.get(deviceAccount) == nil { restoredFromICloud = true }
        } else if !createIfMissing {
            return nil
        } else {
            synced = SyncedIdentity(sign: E2EECrypto.b64u(P256.Signing.PrivateKey().rawRepresentation),
                                    dh: E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation),
                                    backupKey: E2EECrypto.b64u(E2EECrypto.random(32)), createdAt: Date().timeIntervalSince1970)
            Keychain.setCodable(synced, identityAccount, synced: true)
        }
        let deviceID: String
        if let d = Keychain.get(deviceAccount), let s = String(data: d, encoding: .utf8) { deviceID = s } else {
            guard createIfMissing else { return nil }
            deviceID = "d_ios_" + E2EECrypto.b64u(E2EECrypto.random(12))
            Keychain.set(Data(deviceID.utf8), account: deviceAccount)
        }
        guard let signRaw = try? E2EECrypto.unb64u(synced.sign), let dhRaw = try? E2EECrypto.unb64u(synced.dh),
              let sign = try? P256.Signing.PrivateKey(rawRepresentation: signRaw),
              let dh = try? P256.KeyAgreement.PrivateKey(rawRepresentation: dhRaw) else { return nil }
        return E2EELocalIdentity(deviceID: deviceID, handle: handle.lowercased(), sign: sign, dh: dh)
    }

    var deviceID: String? { Keychain.get(deviceAccount).flatMap { String(data: $0, encoding: .utf8) } }

    var backupKey: Data? {
        Keychain.getCodable(SyncedIdentity.self, identityAccount).flatMap { try? E2EECrypto.unb64u($0.backupKey) }
    }

    // MARK: Prekeys (per device)

    func prekeys(createIfMissing: Bool = true) -> PrekeyState? {
        if let s = Keychain.getCodable(PrekeyState.self, prekeyAccount) { return s }
        guard createIfMissing else { return nil }
        var opks: [Int: String] = [:]
        for i in 1...100 { opks[i] = E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation) }
        let s = PrekeyState(spkID: Int.random(in: 1...1_000_000), spk: E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation),
                            spkCreatedAt: Date().timeIntervalSince1970, previousSPK: [:], opks: opks, nextOPK: 101, uploaded: false)
        Keychain.setCodable(s, prekeyAccount)
        return s
    }

    func savePrekeys(_ s: PrekeyState) { Keychain.setCodable(s, prekeyAccount) }

    /// Rotates the signed prekey every 7 days, keeping the previous one for 30 days for in-flight messages.
    func rotateSignedPrekeyIfNeeded() -> PrekeyState? {
        guard var s = prekeys(), Date().timeIntervalSince1970 - s.spkCreatedAt > 7 * 86400 else { return nil }
        s.previousSPK[s.spkID] = s.spk
        if s.previousSPK.count > 4, let oldest = s.previousSPK.keys.min() { s.previousSPK[oldest] = nil }
        s.spkID = Int.random(in: 1...1_000_000)
        s.spk = E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation)
        s.spkCreatedAt = Date().timeIntervalSince1970
        savePrekeys(s)
        return s
    }

    /// Raw synced identity blob for the passcode backup (never leaves the device unencrypted).
    func exportIdentity() -> Data? { Keychain.get(identityAccount) }

    /// Restores an identity from a decrypted passcode backup; per-device prekeys are regenerated and re-registered.
    @discardableResult
    func importIdentity(_ d: Data) -> Bool {
        guard let s = try? JSONDecoder().decode(SyncedIdentity.self, from: d),
              (try? P256.Signing.PrivateKey(rawRepresentation: E2EECrypto.unb64u(s.sign))) != nil else { return false }
        lock.lock(); defer { lock.unlock() }
        Keychain.setCodable(s, identityAccount, synced: true)
        Keychain.delete(prekeyAccount)
        KeychainSessionStorage.shared.wipe()
        return true
    }

    /// "Forgot passcode": brand-new identity. Contacts will see "security number changed".
    func resetIdentity() {
        Keychain.delete(identityAccount)
        resetDevice()
    }

    /// Wipes this device's keys (used by "Delete my data" and remote sign-out).
    func resetDevice() {
        Keychain.delete(deviceAccount); Keychain.delete(prekeyAccount)
        KeychainSessionStorage.shared.wipe()
    }
}

/// Session state in the shared keychain so the NSE sees the same chains as the app.
final class KeychainSessionStorage: E2EESessionStorage {
    static let shared = KeychainSessionStorage()
    private struct Blob: Codable { var outbound: [String: E2EEOutboundSession] = [:]; var inbound: [String: E2EEInboundSession] = [:] }
    private let account = "sessions.v1"
    private let lock = NSLock()
    private var cache: Blob?

    private func load() -> Blob {
        if let cache { return cache }
        let b = Keychain.getCodable(Blob.self, account) ?? Blob()
        cache = b
        return b
    }
    private func save(_ b: Blob) { cache = b; Keychain.setCodable(b, account) }

    func reload() { lock.lock(); cache = nil; lock.unlock() }
    func wipe() { lock.lock(); cache = Blob(); Keychain.delete(account); lock.unlock() }

    func outbound(peer deviceID: String) -> E2EEOutboundSession? { lock.lock(); defer { lock.unlock() }; return load().outbound[deviceID] }
    func setOutbound(_ session: E2EEOutboundSession?, peer deviceID: String) {
        lock.lock(); var b = load(); b.outbound[deviceID] = session; save(b); lock.unlock()
    }
    func inbound(sender deviceID: String, ek: String) -> E2EEInboundSession? {
        lock.lock(); defer { lock.unlock() }; return load().inbound[deviceID + "|" + ek]
    }
    func setInbound(_ session: E2EEInboundSession, sender deviceID: String, ek: String) {
        lock.lock(); var b = load()
        b.inbound[deviceID + "|" + ek] = session
        // Keep at most 4 inbound chains per sender device (older ones are replaced by re-keys).
        let mine = b.inbound.filter { $0.value.senderDeviceID == deviceID }.sorted { $0.value.createdAt > $1.value.createdAt }
        for old in mine.dropFirst(4) { b.inbound[old.key] = nil }
        save(b); lock.unlock()
    }
    func resetOutbound(peer: String) { setOutbound(nil, peer: peer) }
    func signedPrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey? {
        guard let s = IdentityStore.shared.prekeys(createIfMissing: false) else { return nil }
        let raw = id == s.spkID ? s.spk : s.previousSPK[id]
        return raw.flatMap { try? E2EECrypto.unb64u($0) }.flatMap { try? P256.KeyAgreement.PrivateKey(rawRepresentation: $0) }
    }
    func oneTimePrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey? {
        IdentityStore.shared.prekeys(createIfMissing: false)?.opks[id]
            .flatMap { try? E2EECrypto.unb64u($0) }.flatMap { try? P256.KeyAgreement.PrivateKey(rawRepresentation: $0) }
    }
    func consumeOneTimePrekey(id: Int) {
        guard var s = IdentityStore.shared.prekeys(createIfMissing: false) else { return }
        s.opks[id] = nil
        IdentityStore.shared.savePrekeys(s)
    }
}


/// One-time copy of E2EE keys into the shared keychain group so the Notification Service Extension can read them.
enum SharedKeychainMigration {
    static func run() {
        guard Keychain.sharedGroup != nil, !UserDefaults.standard.bool(forKey: "keychain.sharedMigrated.v1") else { return }
        for (account, synced) in [("identity.v1", true), ("device.v1", false), ("prekeys.v1", false), ("sessions.v1", false)] {
            if let d = Keychain.get(account) { Keychain.set(d, account: account, synced: synced) }
        }
        KeychainSessionStorage.shared.reload()
        UserDefaults.standard.set(true, forKey: "keychain.sharedMigrated.v1")
    }
}

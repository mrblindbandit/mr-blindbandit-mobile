import Foundation
import OSLog
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Wire format the production key directory actually accepts (worker/platform/e2ee.ts, strict zod schemas):
/// - identity_key      = b64u(identity_sign_pub(65) ‖ identity_dh_pub(65))
/// - signed_prekey     = b64u(UInt32BE id ‖ pub(65)),  signed_prekey_sig = b64u(ECDSA sig over pub)
/// - prekeys[]         = b64u(UInt32BE id ‖ pub(65))
/// Root cause of "devices never register keys" (2.0.5 and earlier): the app posted object-shaped fields
/// (identity_sign_pub, signed_prekey:{id,pub,sig}, prekeys:[{id,pub}], platform, suite, name); the strict
/// schema rejected every request with HTTP 400 and E2EEService.bootstrap swallowed the error with no retry.
enum KeyWire {
    static let pubLen = 65

    static func identityKey(signPub: Data, dhPub: Data) -> String { E2EECrypto.b64u(signPub + dhPub) }

    static func packed(id: Int, pub: Data) -> String {
        var be = UInt32(truncatingIfNeeded: id).bigEndian
        return E2EECrypto.b64u(Data(bytes: &be, count: 4) + pub)
    }

    static func unpack(_ s: String) -> (id: Int, pub: Data)? {
        guard let d = try? E2EECrypto.unb64u(s), d.count == 4 + pubLen else { return nil }
        let id = d.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        return (id, Data(d.dropFirst(4)))
    }

    static func splitIdentity(_ s: String) -> (sign: Data, dh: Data)? {
        guard let d = try? E2EECrypto.unb64u(s), d.count == 2 * pubLen else { return nil }
        return (Data(d.prefix(pubLen)), Data(d.suffix(pubLen)))
    }

    static func spkPub(_ s: IdentityStore.PrekeyState) throws -> Data {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: try E2EECrypto.unb64u(s.spk)).publicKey.x963Representation
    }

    static func signedPrekeyBody(spk s: IdentityStore.PrekeyState, spkSign: (Data) throws -> Data) throws -> [String: Any] {
        let pub = try spkPub(s)
        return ["signed_prekey": packed(id: s.spkID, pub: pub), "signed_prekey_sig": E2EECrypto.b64u(try spkSign(pub))]
    }

    static func prekeys(_ items: [(Int, String)]) -> [String] {
        items.compactMap { idx, raw in
            guard let d = try? E2EECrypto.unb64u(raw), let k = try? P256.KeyAgreement.PrivateKey(rawRepresentation: d) else { return nil }
            return packed(id: idx, pub: k.publicKey.x963Representation)
        }
    }

    static func registerBody(id: E2EELocalIdentity, spk: IdentityStore.PrekeyState, spkSign: (Data) throws -> Data,
                             opks: [(Int, String)], label: String) throws -> (body: [String: Any], prekeys: [String]) {
        var body = try signedPrekeyBody(spk: spk, spkSign: spkSign)
        body["device_id"] = id.deviceID
        body["device_label"] = String(label.prefix(100))
        body["identity_key"] = identityKey(signPub: id.signPub, dhPub: id.dhPub)
        return (body, prekeys(opks))
    }

    /// Server returns either a bare number or {count:n} (wrapped in {data:…}).
    static func count(_ d: Data) -> Int? {
        guard let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) else { return nil }
        if let n = o as? Int { return n }
        if let m = o as? [String: Any] {
            if let n = m["data"] as? Int { return n }
            if let n = m["count"] as? Int { return n }
            if let inner = m["data"] as? [String: Any], let n = inner["count"] as? Int { return n }
        }
        return nil
    }

    /// Maps a server bundle ({device_id, identity_key, signed_prekey, signed_prekey_sig, one_time_prekey}) to the app model.
    /// Also accepts the legacy object shape so either server version works.
    static func bundle(_ o: [String: Any]) -> E2EEDeviceBundle? {
        if let j = try? JSONSerialization.data(withJSONObject: o), let b = try? JSONDecoder().decode(E2EEDeviceBundle.self, from: j) { return b }
        guard let dev = o["device_id"] as? String, let ik = o["identity_key"] as? String, let keys = splitIdentity(ik),
              let spkS = o["signed_prekey"] as? String, let spk = unpack(spkS), let sig = o["signed_prekey_sig"] as? String else { return nil }
        let opk = (o["one_time_prekey"] as? String).flatMap(unpack).map { E2EEOneTimePrekey(id: $0.id, pub: E2EECrypto.b64u($0.pub)) }
        return E2EEDeviceBundle(device_id: dev, platform: nil, suite: E2EECrypto.suite,
                                identity_sign_pub: E2EECrypto.b64u(keys.sign), identity_dh_pub: E2EECrypto.b64u(keys.dh), device_cert: nil,
                                signed_prekey: E2EESignedPrekey(id: spk.id, pub: E2EECrypto.b64u(spk.pub), sig: sig), prekey: opk, handle: nil)
    }
}

/// Key-setup status shown in Settings ▸ debug log so failures are never silent again.
enum KeySetupLog {
    static let logger = Logger(subsystem: "net.mrblindbandit.app", category: "e2ee")
    static func record(_ s: String) {
        logger.log("\(s, privacy: .public)")
        UserDefaults.standard.set("\(Date().formatted(date: .abbreviated, time: .shortened)): \(s)", forKey: "e2ee.lastKeySetup")
    }
    static var last: String { UserDefaults.standard.string(forKey: "e2ee.lastKeySetup") ?? "No key setup attempt yet." }
}

/// Per-call LiveKit frame keys, delivered inside p256-v1 E2EE messages (payload t = "call_key").
/// The server only ever relays the per-device ciphertext envelope; it never sees the key.
struct CallKeyMessage: Codable, Equatable {
    var call_id: String
    var key: String   // b64u, 32 random bytes
    var index: Int
}

@MainActor
final class CallKeyStore {
    static let shared = CallKeyStore()
    private(set) var keys: [String: CallKeyMessage] = [:]
    var onKey: ((CallKeyMessage) -> Void)?

    static func newKey() -> Data {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
        return Data(b)
    }

    static func encode(_ m: CallKeyMessage) -> String { String(data: (try? JSONEncoder().encode(m)) ?? Data(), encoding: .utf8) ?? "" }

    func receive(_ body: String) {
        guard let d = body.data(using: .utf8), let m = try? JSONDecoder().decode(CallKeyMessage.self, from: d) else { return }
        if let cur = keys[m.call_id], cur.index >= m.index { return }
        keys[m.call_id] = m
        onKey?(m)
    }

    func set(_ m: CallKeyMessage) { keys[m.call_id] = m }
    func clear(_ callID: String) { keys[callID] = nil }
}

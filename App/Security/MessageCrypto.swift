import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Key directory models (site prompt §2)

struct E2EESignedPrekey: Codable, Equatable { var id: Int; var pub: String; var sig: String }
struct E2EEOneTimePrekey: Codable, Equatable { var id: Int; var pub: String }

struct E2EEDeviceBundle: Codable, Equatable {
    var device_id: String
    var platform: String?
    var suite: String?
    var identity_sign_pub: String
    var identity_dh_pub: String
    var device_cert: String?
    var signed_prekey: E2EESignedPrekey?
    var prekey: E2EEOneTimePrekey?
    /// Filled by the client from the bundle's top-level handle.
    var handle: String?
}

/// This device's long-term identity. Signing + agreement keys are software P-256 keys so iCloud Keychain can sync them (§12).
struct E2EELocalIdentity {
    var deviceID: String
    var handle: String
    var sign: P256.Signing.PrivateKey
    var dh: P256.KeyAgreement.PrivateKey
    var signPub: Data { sign.publicKey.x963Representation }
    var dhPub: Data { dh.publicKey.x963Representation }
}

// MARK: - Sessions (§1.2, §1.3)

struct E2EEOutboundSession: Codable, Equatable {
    var peerDeviceID: String
    var header: E2EEPrekeyHeader
    var chainKey: String
    var n: Int
    var createdAt: Double
}

struct E2EEInboundSession: Codable, Equatable {
    var senderDeviceID: String
    var ek: String
    var chainKey: String
    /// Next unused chain index.
    var n: Int
    /// Skipped message keys by index (≤ 200, 7 days).
    var skipped: [Int: String]
    var skippedAt: [Int: Double]
    var createdAt: Double
}

protocol E2EESessionStorage: AnyObject {
    func outbound(peer deviceID: String) -> E2EEOutboundSession?
    func setOutbound(_ session: E2EEOutboundSession?, peer deviceID: String)
    func inbound(sender deviceID: String, ek: String) -> E2EEInboundSession?
    func setInbound(_ session: E2EEInboundSession, sender deviceID: String, ek: String)
    func signedPrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey?
    func oneTimePrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey?
    /// Called when a session was established from a one-time prekey: the private half must be deleted.
    func consumeOneTimePrekey(id: Int)
}

/// Injected so tests can reproduce `vectors/p256-v1.json` byte for byte.
protocol E2EERandomness {
    func ephemeralKey() -> P256.KeyAgreement.PrivateKey
    func contentKey() -> Data
    func nonce() -> Data
}

struct SystemE2EERandomness: E2EERandomness {
    func ephemeralKey() -> P256.KeyAgreement.PrivateKey { P256.KeyAgreement.PrivateKey() }
    func contentKey() -> Data { E2EECrypto.random(32) }
    func nonce() -> Data { E2EECrypto.random(12) }
}

enum X3DH {
    static func info(sender: String, recipient: String) -> Data { Data("BB-X3DH-v1".utf8) + Data(sender.utf8) + Data(recipient.utf8) }

    static func verifyBundle(_ bundle: E2EEDeviceBundle) throws -> E2EESignedPrekey {
        guard let spk = bundle.signed_prekey else { throw E2EECrypto.CryptoError.badKey }
        let ok = E2EECrypto.verify(try E2EECrypto.unb64u(spk.sig), try E2EECrypto.unb64u(spk.pub), publicKey: try E2EECrypto.unb64u(bundle.identity_sign_pub))
        guard ok else { throw E2EECrypto.CryptoError.badSignature }
        return spk
    }

    /// Sender side. Returns the shared key and the header the recipient needs.
    static func initiate(local: E2EELocalIdentity, bundle: E2EEDeviceBundle, ephemeral: P256.KeyAgreement.PrivateKey) throws -> (sk: Data, header: E2EEPrekeyHeader) {
        let spk = try verifyBundle(bundle)
        let spkPub = try E2EECrypto.unb64u(spk.pub)
        var ikm = try E2EECrypto.dh(local.dh, spkPub)
        ikm += try E2EECrypto.dh(ephemeral, try E2EECrypto.unb64u(bundle.identity_dh_pub))
        ikm += try E2EECrypto.dh(ephemeral, spkPub)
        if let opk = bundle.prekey { ikm += try E2EECrypto.dh(ephemeral, try E2EECrypto.unb64u(opk.pub)) }
        let sk = E2EECrypto.hkdf(ikm, salt: Data(count: 32), info: info(sender: local.deviceID, recipient: bundle.device_id))
        let header = E2EEPrekeyHeader(ek: E2EECrypto.b64u(ephemeral.publicKey.x963Representation), spk_id: spk.id,
                                      opk_id: bundle.prekey?.id, ik: E2EECrypto.b64u(local.dhPub), isk: E2EECrypto.b64u(local.signPub))
        return (sk, header)
    }

    /// Recipient side.
    static func respond(local: E2EELocalIdentity, senderDeviceID: String, header: E2EEPrekeyHeader,
                        spk: P256.KeyAgreement.PrivateKey, opk: P256.KeyAgreement.PrivateKey?) throws -> Data {
        let ek = try E2EECrypto.unb64u(header.ek)
        var ikm = try E2EECrypto.dh(spk, try E2EECrypto.unb64u(header.ik))
        ikm += try E2EECrypto.dh(local.dh, ek)
        ikm += try E2EECrypto.dh(spk, ek)
        if let opk { ikm += try E2EECrypto.dh(opk, ek) }
        return E2EECrypto.hkdf(ikm, salt: Data(count: 32), info: info(sender: senderDeviceID, recipient: local.deviceID))
    }
}

/// Symmetric sending-chain ratchet (§1.3). Honest scope: forward secrecy per message, no post-compromise healing.
enum ChainRatchet {
    static let maxSkipped = 200
    static let skippedLifetime: Double = 7 * 86400
    static let rekeyAfterMessages = 100
    static let rekeyAfterSeconds: Double = 7 * 86400

    static func step(_ ck: Data) -> (mk: Data, next: Data) {
        (E2EECrypto.hmac(ck, Data([0x01])), E2EECrypto.hmac(ck, Data([0x02])))
    }

    /// Returns the message key for index `n`, advancing the chain and keeping skipped keys. A key is deleted after use.
    static func messageKey(_ session: inout E2EEInboundSession, index n: Int, now: Double) throws -> Data {
        session.skippedAt = session.skippedAt.filter { now - $0.value < skippedLifetime }
        session.skipped = session.skipped.filter { session.skippedAt[$0.key] != nil }
        if n < session.n {
            guard let mk = session.skipped.removeValue(forKey: n) else { throw E2EECrypto.CryptoError.replayedOrStale }
            session.skippedAt[n] = nil
            return try E2EECrypto.unb64u(mk)
        }
        guard n - session.n <= maxSkipped else { throw E2EECrypto.CryptoError.replayedOrStale }
        var ck = try E2EECrypto.unb64u(session.chainKey)
        while session.n < n {
            let s = step(ck)
            session.skipped[session.n] = E2EECrypto.b64u(s.mk)
            session.skippedAt[session.n] = now
            ck = s.next
            session.n += 1
        }
        let s = step(ck)
        session.chainKey = E2EECrypto.b64u(s.next)
        session.n += 1
        while session.skipped.count > maxSkipped, let oldest = session.skipped.keys.min() {
            session.skipped[oldest] = nil; session.skippedAt[oldest] = nil
        }
        return s.mk
    }
}

struct E2EEDecrypted {
    var payload: E2EEPayload
    var senderDeviceID: String
    var senderSignPub: String?
    var senderDHPub: String?
}

/// Multi-device fan-out (§1.4): content encrypted once under a random CEK, CEK wrapped per device.
enum MessageCrypto {
    static func contentAD(msgID: String, senderDevice: String) -> Data { Data("bb1:\(msgID):\(senderDevice)".utf8) }
    static func wrapAD(senderSign: Data, recipientSign: Data) -> Data { Data("bb1".utf8) + senderSign + recipientSign }

    static func encrypt(_ payload: E2EEPayload, msgID: String = UUID().uuidString.lowercased(), local: E2EELocalIdentity,
                        recipients: [E2EEDeviceBundle], storage: E2EESessionStorage,
                        randomness: E2EERandomness = SystemE2EERandomness(), now: Double = Date().timeIntervalSince1970,
                        payloadJSON: Data? = nil) throws -> E2EEEnvelope {
        let cek = randomness.contentKey()
        let nonce = randomness.nonce()
        let plain = try payloadJSON ?? payload.canonicalJSON()
        let ct = try E2EECrypto.seal(E2EECrypto.pad(plain), key: cek, nonce: nonce, ad: contentAD(msgID: msgID, senderDevice: local.deviceID))
        var entries: [E2EEKeyEntry] = []
        for device in recipients where device.device_id != local.deviceID {
            var session = storage.outbound(peer: device.device_id)
            if let s = session, s.n >= ChainRatchet.rekeyAfterMessages || now - s.createdAt > ChainRatchet.rekeyAfterSeconds { session = nil }
            if session == nil {
                let x = try X3DH.initiate(local: local, bundle: device, ephemeral: randomness.ephemeralKey())
                session = E2EEOutboundSession(peerDeviceID: device.device_id, header: x.header, chainKey: E2EECrypto.b64u(x.sk), n: 0, createdAt: now)
            }
            guard var s = session else { continue }
            let step = ChainRatchet.step(try E2EECrypto.unb64u(s.chainKey))
            let wrapNonce = randomness.nonce()
            let wrapped = try E2EECrypto.seal(cek, key: step.mk, nonce: wrapNonce,
                                              ad: wrapAD(senderSign: local.signPub, recipientSign: try E2EECrypto.unb64u(device.identity_sign_pub)))
            entries.append(E2EEKeyEntry(device_id: device.device_id, handle: device.handle, prekey: s.header, n: s.n, pn: 0,
                                        wrapped: E2EECrypto.b64u(wrapped), nonce: E2EECrypto.b64u(wrapNonce)))
            s.chainKey = E2EECrypto.b64u(step.next)
            s.n += 1
            storage.setOutbound(s, peer: device.device_id)
        }
        return E2EEEnvelope(sender_device_id: local.deviceID, msg_id: msgID, nonce: E2EECrypto.b64u(nonce),
                            ciphertext: E2EECrypto.b64u(ct), keys: entries, sig: nil)
    }

    static func decrypt(_ envelope: E2EEEnvelope, local: E2EELocalIdentity, storage: E2EESessionStorage,
                        now: Double = Date().timeIntervalSince1970) throws -> E2EEDecrypted {
        guard envelope.suite == E2EECrypto.suite else { throw E2EECrypto.CryptoError.badKey }
        guard let entry = envelope.keys.first(where: { $0.device_id == local.deviceID }) else { throw E2EECrypto.CryptoError.missingKeyEntry }
        guard let header = entry.prekey else { throw E2EECrypto.CryptoError.unknownSession }
        var session: E2EEInboundSession
        if let existing = storage.inbound(sender: envelope.sender_device_id, ek: header.ek) {
            session = existing
        } else {
            guard let spk = storage.signedPrekeyPrivate(id: header.spk_id) else { throw E2EECrypto.CryptoError.unknownSession }
            var opk: P256.KeyAgreement.PrivateKey?
            if let id = header.opk_id {
                guard let k = storage.oneTimePrekeyPrivate(id: id) else { throw E2EECrypto.CryptoError.unknownSession }
                opk = k
            }
            let sk = try X3DH.respond(local: local, senderDeviceID: envelope.sender_device_id, header: header, spk: spk, opk: opk)
            session = E2EEInboundSession(senderDeviceID: envelope.sender_device_id, ek: header.ek, chainKey: E2EECrypto.b64u(sk),
                                         n: 0, skipped: [:], skippedAt: [:], createdAt: now)
            if let id = header.opk_id { storage.consumeOneTimePrekey(id: id) }
        }
        let mk = try ChainRatchet.messageKey(&session, index: entry.n, now: now)
        let senderSign = try E2EECrypto.unb64u(header.isk ?? "")
        let cek = try E2EECrypto.open(try E2EECrypto.unb64u(entry.wrapped), key: mk, nonce: try E2EECrypto.unb64u(entry.nonce),
                                      ad: wrapAD(senderSign: senderSign, recipientSign: local.signPub))
        let padded = try E2EECrypto.open(try E2EECrypto.unb64u(envelope.ciphertext), key: cek, nonce: try E2EECrypto.unb64u(envelope.nonce),
                                         ad: contentAD(msgID: envelope.msg_id, senderDevice: envelope.sender_device_id))
        storage.setInbound(session, sender: envelope.sender_device_id, ek: header.ek)
        let payload = try JSONDecoder().decode(E2EEPayload.self, from: try E2EECrypto.unpad(padded))
        return E2EEDecrypted(payload: payload, senderDeviceID: envelope.sender_device_id, senderSignPub: header.isk, senderDHPub: header.ik)
    }

    /// Signed delete control (§23).
    static func deletePayload(target: String, local: E2EELocalIdentity) throws -> E2EEPayload {
        let sig = try E2EECrypto.sign(E2EEPayload.deleteSigningMessage(target), with: local.sign)
        return E2EEPayload(t: "delete", target_msg_id: target, sig: E2EECrypto.b64u(sig))
    }

    static func verifyDelete(_ payload: E2EEPayload, senderSignPubs: [String]) -> Bool {
        guard payload.t == "delete", let target = payload.target_msg_id, let s = payload.sig, let sig = try? E2EECrypto.unb64u(s) else { return false }
        return senderSignPubs.contains { pub in
            guard let key = try? E2EECrypto.unb64u(pub) else { return false }
            return E2EECrypto.verify(sig, E2EEPayload.deleteSigningMessage(target), publicKey: key)
        }
    }
}

/// In-memory storage (tests, and the NSE's scratch copy).
final class InMemoryE2EEStorage: E2EESessionStorage {
    var outboundSessions: [String: E2EEOutboundSession] = [:]
    var inboundSessions: [String: E2EEInboundSession] = [:]
    var spks: [Int: P256.KeyAgreement.PrivateKey] = [:]
    var opks: [Int: P256.KeyAgreement.PrivateKey] = [:]
    init() {}
    func outbound(peer deviceID: String) -> E2EEOutboundSession? { outboundSessions[deviceID] }
    func setOutbound(_ session: E2EEOutboundSession?, peer deviceID: String) { outboundSessions[deviceID] = session }
    func inbound(sender deviceID: String, ek: String) -> E2EEInboundSession? { inboundSessions[deviceID + "|" + ek] }
    func setInbound(_ session: E2EEInboundSession, sender deviceID: String, ek: String) { inboundSessions[deviceID + "|" + ek] = session }
    func signedPrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey? { spks[id] }
    func oneTimePrekeyPrivate(id: Int) -> P256.KeyAgreement.PrivateKey? { opks[id] }
    func consumeOneTimePrekey(id: Int) { opks[id] = nil }
}

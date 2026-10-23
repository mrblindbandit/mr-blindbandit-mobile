import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Suite `p256-v1` primitives (SPEC.md §1). Platform crypto only: CryptoKit P-256, HKDF-SHA256,
/// HMAC-SHA256, AES-256-GCM. No custom ciphers. Byte layouts are pinned by `vectors/p256-v1.json`.
enum E2EECrypto {
    static let suite = "p256-v1"

    enum CryptoError: Error, Equatable {
        case badBase64, badKey, badSignature, badPadding, decryptFailed, missingKeyEntry, unknownSession, replayedOrStale
    }

    // MARK: base64url (no padding)
    static func b64u(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func unb64u(_ string: String) throws -> Data {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s) else { throw CryptoError.badBase64 }
        return d
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func unhex(_ s: String) -> Data {
        var out = Data(); var idx = s.startIndex
        while idx < s.endIndex, let next = s.index(idx, offsetBy: 2, limitedBy: s.endIndex) {
            if let b = UInt8(s[idx..<next], radix: 16) { out.append(b) }
            idx = next
        }
        return out
    }

    // MARK: padding (§17, ISO/IEC 7816-4)
    static let buckets = [256, 512, 1024, 2048, 4096]

    static func paddedLength(_ n: Int) -> Int {
        for b in buckets where n + 1 <= b { return b }
        return ((n + 1 + 4095) / 4096) * 4096
    }

    static func pad(_ data: Data) -> Data {
        var out = data
        out.append(0x80)
        out.append(Data(count: paddedLength(data.count) - data.count - 1))
        return out
    }

    static func unpad(_ data: Data) throws -> Data {
        guard let idx = data.lastIndex(where: { $0 != 0 }), data[idx] == 0x80 else { throw CryptoError.badPadding }
        return data.prefix(upTo: idx)
    }

    /// Padmé (PURBs): leaks at most O(log log n) bits of the attachment size.
    static func padme(_ n: Int) -> Int {
        guard n > 1 else { return n }
        let e = Int(floor(log2(Double(n))))
        let s = Int(floor(log2(Double(e)))) + 1
        let z = e - s
        let mask = (1 << z) - 1
        return (n + mask) & ~mask
    }

    // MARK: KDF / MAC
    static func hkdf(_ ikm: Data, salt: Data, info: Data, count: Int = 32) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: info, outputByteCount: count)
        return key.withUnsafeBytes { Data($0) }
    }

    static func hmac(_ key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    static func sha512(_ data: Data) -> Data { Data(SHA512.hash(data: data)) }

    static func random(_ count: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    // MARK: AES-256-GCM (ciphertext||tag; nonce carried separately)
    static func seal(_ plaintext: Data, key: Data, nonce: Data, ad: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce), authenticating: ad)
        return box.ciphertext + box.tag
    }

    static func open(_ sealed: Data, key: Data, nonce: Data, ad: Data) throws -> Data {
        guard sealed.count >= 16 else { throw CryptoError.decryptFailed }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: ad)
        } catch { throw CryptoError.decryptFailed }
    }

    // MARK: P-256
    static func dh(_ priv: P256.KeyAgreement.PrivateKey, _ pubRaw: Data) throws -> Data {
        guard let pub = try? P256.KeyAgreement.PublicKey(x963Representation: pubRaw) else { throw CryptoError.badKey }
        let secret = try priv.sharedSecretFromKeyAgreement(with: pub)
        return secret.withUnsafeBytes { Data($0) }
    }

    static func sign(_ message: Data, with key: P256.Signing.PrivateKey) throws -> Data {
        try key.signature(for: message).rawRepresentation
    }

    static func verify(_ signature: Data, _ message: Data, publicKey: Data) -> Bool {
        guard let pub = try? P256.Signing.PublicKey(x963Representation: publicKey),
              let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
        return pub.isValidSignature(sig, for: message)
    }

    static func agreementKey(hex: String) throws -> P256.KeyAgreement.PrivateKey {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: unhex(hex))
    }

    static func signingKey(hex: String) throws -> P256.Signing.PrivateKey {
        try P256.Signing.PrivateKey(rawRepresentation: unhex(hex))
    }
}

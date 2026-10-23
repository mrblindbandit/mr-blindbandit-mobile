import Foundation

/// Encrypted attachments (§16): per-file key, 64 KiB AES-GCM segments, Padmé size padding, SHA-256 over the blob.
enum AttachmentCrypto {
    static let segmentSize = 65536

    struct Sealed { let blob: Data; let key: Data; let baseNonce: Data; let sha256: Data; let plainSize: Int }

    static func segmentNonce(base: Data, index: Int) -> Data {
        let tail = base.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } ^ UInt64(index)
        return base.prefix(4) + Data((0..<8).reversed().map { UInt8((tail >> (UInt64($0) * 8)) & 0xff) })
    }

    static func segmentAD(_ index: Int) -> Data {
        Data("bb-att-v1".utf8) + Data([UInt8((index >> 24) & 0xff), UInt8((index >> 16) & 0xff), UInt8((index >> 8) & 0xff), UInt8(index & 0xff)])
    }

    static func seal(_ plain: Data, key: Data = E2EECrypto.random(32), baseNonce: Data = E2EECrypto.random(12)) throws -> Sealed {
        var padded = plain
        padded.append(Data(count: E2EECrypto.padme(plain.count) - plain.count))
        var out = Data()
        var index = 0
        var offset = 0
        while offset < padded.count {
            let end = min(offset + segmentSize, padded.count)
            out += try E2EECrypto.seal(padded.subdata(in: offset..<end), key: key, nonce: segmentNonce(base: baseNonce, index: index), ad: segmentAD(index))
            offset = end; index += 1
        }
        return Sealed(blob: out, key: key, baseNonce: baseNonce, sha256: E2EECrypto.sha256(out), plainSize: plain.count)
    }

    static func open(_ blob: Data, key: Data, baseNonce: Data, plainSize: Int, sha256: Data?) throws -> Data {
        if let sha256, E2EECrypto.sha256(blob) != sha256 { throw E2EECrypto.CryptoError.decryptFailed }
        var out = Data(); var index = 0; var offset = 0
        let sealedSegment = segmentSize + 16
        while offset < blob.count {
            let end = min(offset + sealedSegment, blob.count)
            out += try E2EECrypto.open(blob.subdata(in: offset..<end), key: key, nonce: segmentNonce(base: baseNonce, index: index), ad: segmentAD(index))
            offset = end; index += 1
        }
        return out.prefix(plainSize)
    }
}

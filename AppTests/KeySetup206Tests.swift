import XCTest
import CryptoKit
@testable import Blindbandit

@MainActor
final class KeySetup206Tests: XCTestCase {
    private let b64url = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{16,}$")
    private func isB64url(_ s: String) -> Bool { b64url.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    private func makeIdentity() -> E2EELocalIdentity {
        E2EELocalIdentity(deviceID: "d_ios_test", handle: "kheck", sign: P256.Signing.PrivateKey(), dh: P256.KeyAgreement.PrivateKey())
    }
    private func makeSPK() -> IdentityStore.PrekeyState {
        IdentityStore.PrekeyState(spkID: 4242, spk: E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation), spkCreatedAt: 0,
                                  previousSPK: [:], opks: [7: E2EECrypto.b64u(P256.KeyAgreement.PrivateKey().rawRepresentation)], nextOPK: 8, uploaded: false)
    }

    /// Root cause regression: the body must only use keys the strict server schema accepts, all base64url strings.
    func testRegisterBodyMatchesServerSchema() throws {
        let id = makeIdentity(), s = makeSPK()
        let r = try KeyWire.registerBody(id: id, spk: s, spkSign: { try E2EECrypto.sign($0, with: id.sign) },
                                         opks: s.opks.map { ($0.key, $0.value) }, label: "iPhone")
        let allowed: Set<String> = ["device_id", "device_label", "identity_key", "signed_prekey", "signed_prekey_sig", "registration_lock_token"]
        XCTAssertTrue(Set(r.body.keys).isSubset(of: allowed), "unexpected keys: \(Set(r.body.keys).subtracting(allowed))")
        for k in ["identity_key", "signed_prekey", "signed_prekey_sig"] {
            let v = try XCTUnwrap(r.body[k] as? String, k)
            XCTAssertTrue(isB64url(v), k)
        }
        XCTAssertEqual(r.prekeys.count, 1)
        XCTAssertTrue(r.prekeys.allSatisfy(isB64url))
    }

    func testServerBundleRoundTripsAndVerifies() throws {
        let id = makeIdentity(), s = makeSPK()
        let r = try KeyWire.registerBody(id: id, spk: s, spkSign: { try E2EECrypto.sign($0, with: id.sign) },
                                         opks: s.opks.map { ($0.key, $0.value) }, label: "iPhone")
        let server: [String: Any] = ["device_id": "d_ios_test", "identity_key": r.body["identity_key"]!, "signed_prekey": r.body["signed_prekey"]!,
                                     "signed_prekey_sig": r.body["signed_prekey_sig"]!, "one_time_prekey": r.prekeys[0]]
        let b = try XCTUnwrap(KeyWire.bundle(server))
        XCTAssertEqual(b.identity_sign_pub, E2EECrypto.b64u(id.signPub))
        XCTAssertEqual(b.identity_dh_pub, E2EECrypto.b64u(id.dhPub))
        XCTAssertEqual(b.signed_prekey?.id, 4242)
        XCTAssertEqual(b.prekey?.id, 7)
        XCTAssertNoThrow(try X3DH.verifyBundle(b))
    }

    func testPrekeyCountParsing() {
        XCTAssertEqual(KeyWire.count(Data("{\"data\":12}".utf8)), 12)
        XCTAssertEqual(KeyWire.count(Data("{\"count\":3}".utf8)), 3)
        XCTAssertEqual(KeyWire.count(Data("5".utf8)), 5)
    }

    func testPasscodeBackupRoundTrip() throws {
        let secret = Data("identity-blob".utf8)
        let b = try EncryptionPasscode.seal(secret, pass: "123456")
        XCTAssertTrue(isB64url(b["ciphertext"] as! String))
        var stored = b
        stored["kdf"] = String(data: try JSONSerialization.data(withJSONObject: b["kdf"]!), encoding: .utf8)
        XCTAssertEqual(EncryptionPasscode.open(stored, pass: "123456"), secret)
        XCTAssertNil(EncryptionPasscode.open(stored, pass: "654321"))
        XCTAssertFalse(EncryptionPasscode.isValid("12345"))
        XCTAssertTrue(EncryptionPasscode.isValid("abc123"))
    }

    func testCallKeyStoreKeepsNewestIndex() {
        let store = CallKeyStore.shared
        store.clear("c1")
        store.receive(CallKeyStore.encode(CallKeyMessage(call_id: "c1", key: "k1", index: 1)))
        store.receive(CallKeyStore.encode(CallKeyMessage(call_id: "c1", key: "k0", index: 0)))
        XCTAssertEqual(store.keys["c1"]?.key, "k1")
        XCTAssertEqual(CallKeyStore.newKey().count, 32)
        XCTAssertTrue(E2EEService.isControl(E2EEPayload(t: "call_key")))
        store.clear("c1")
    }
}

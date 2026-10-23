import XCTest
import CryptoKit
@testable import Blindbandit

@MainActor
final class Release202Tests: XCTestCase {
    func testBackupEnvelopeReadsBothShapes() {
        let c = Data([1, 2, 3]).base64EncodedString()
        for json in [#"{"ciphertext":"\#(c)","metadata":{"v":1},"updated_at":1}"#, #"{"v":1,"blob":"\#(c)"}"#, #"{"data":{"ciphertext":"\#(c)"}}"#] {
            XCTAssertEqual(BackupEnvelope.ciphertext(Data(json.utf8)), Data([1, 2, 3]), json)
        }
        let body = BackupEnvelope.body(Data([9]), kind: "ai-chat")
        XCTAssertNotNil(body["ciphertext"]); XCTAssertNotNil(body["metadata"]); XCTAssertNotNil(body["blob"])
    }

    func testAIChatBackupRoundTripsViaServerShape() throws {
        let k = SymmetricKey(size: .bits256)
        let p = AIChatBackup.Payload(lines: [.init(fromAI: false, text: "hi")], memory: .init(facts: ["likes coffee"]))
        let sealed = try XCTUnwrap(AIChatBackup.seal(p, key: k))
        let server = try JSONSerialization.data(withJSONObject: ["ciphertext": sealed.base64EncodedString(), "metadata": [:], "updated_at": 1])
        let back = try XCTUnwrap(AIChatBackup.open(server, key: k))
        XCTAssertEqual(back.lines.first?.text, "hi"); XCTAssertEqual(back.memory.facts, ["likes coffee"])
    }

    func testSettingsDecodeFlatServerFields() throws {
        let json = #"{"no_store":1,"allow_ai":false,"screenshot_alerts":false,"allow_view_once":0,"admins_only_post":true,"require_approval":"true","my":{"mute_sound":true}}"#
        let s = try JSONDecoder().decode(ChatSecuritySettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.no_store); XCTAssertFalse(s.allow_ai)
        XCTAssertFalse(s.security.screenshot_alerts); XCTAssertFalse(s.security.allow_view_once)
        XCTAssertEqual(s.group?.admins_only_post, true); XCTAssertEqual(s.group?.require_approval, true)
        XCTAssertTrue(s.my.mute_sound)
        XCTAssertTrue(try JSONDecoder().decode(ChatSecuritySettings.self, from: Data("{}".utf8)).allow_ai)
    }

    func testKeysBackupPayloadForPUTRoundTrips() throws {
        let id = Data((0..<64).map { UInt8($0) })
        let blob = try RecoveryPassphrase.wrap(identity: id, pass: "correct horse")
        XCTAssertNotNil(blob["ciphertext"]); XCTAssertNotNil(blob["blob"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: blob))
        XCTAssertEqual(RecoveryPassphrase.unwrap(blob, pass: "correct horse"), id)
        XCTAssertNil(RecoveryPassphrase.unwrap(blob, pass: "wrong"))
        // Server echo in {ciphertext, metadata} shape only.
        let echo: [String: Any] = ["data": ["ciphertext": blob["ciphertext"]!, "metadata": blob["metadata"]!]]
        XCTAssertEqual(RecoveryPassphrase.unwrap(echo, pass: "correct horse"), id)
    }
}

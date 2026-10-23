import XCTest
@testable import Blindbandit

@MainActor
final class Release201Tests: XCTestCase {
    func testSocialProfileDecodesVerifiedAsIntOrBool() throws {
        let a = try JSONDecoder().decode(BlindbanditSocialProfile.self, from: Data(#"{"id":"1","handle":"kheck","display_name":"Kaeleb","verified":1}"#.utf8))
        XCTAssertEqual(a.verified, true)
        let b = try JSONDecoder().decode(BlindbanditSocialProfile.self, from: Data(#"{"id":"1","handle":"x","display_name":"X","verified":false}"#.utf8))
        XCTAssertEqual(b.verified, false)
        let c = try JSONDecoder().decode(BlindbanditSocialProfile.self, from: Data(#"{"id":"1","handle":"x"}"#.utf8))
        XCTAssertNil(c.verified)
    }

    func testHiddenFolderAlwaysExists() {
        XCTAssertTrue(ChatFolders.shared.folders.contains { $0.hidden })
    }

    func testDuressPinOpensDecoy() {
        AppPIN.set(real: "1234"); AppPIN.set(duress: "9999")
        XCTAssertEqual(AppPIN.check("0000"), .wrong)
        XCTAssertEqual(AppPIN.check("9999"), .duress); XCTAssertTrue(AppPIN.decoyActive)
        XCTAssertEqual(AppPIN.check("1234"), .real); XCTAssertFalse(AppPIN.decoyActive)
        AppPIN.clear()
    }

    func testNotesToSelfAddAndDelete() {
        NotesToSelf.add("buy strings")
        let n = NotesToSelf.notes.last
        XCTAssertEqual(n?.body, "buy strings")
        if let id = n?.id { NotesToSelf.delete(id) }
        XCTAssertFalse(NotesToSelf.notes.contains { $0.id == n?.id })
    }

    func testPollPayloadRoundTrips() throws {
        let p = E2EEPayload(t: "poll", body: "Gig?", poll: .init(question: "Gig?", options: ["Fri", "Sat"], multiple: false))
        let d = try p.canonicalJSON()
        let back = try JSONDecoder().decode(E2EEPayload.self, from: d)
        XCTAssertEqual(back.poll?.options, ["Fri", "Sat"])
    }
}

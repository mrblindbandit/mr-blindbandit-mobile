import XCTest
@testable import Blindbandit

@MainActor
final class BlindbanditTests: XCTestCase {
    func testFirstPartyHostsAreAccepted() throws {
        let urls = [
            "https://mrblindbandit.net/",
            "https://www.mrblindbandit.net/media-tools/",
            "https://portal.mrblindbandit.net/portal/",
            "https://api.mrblindbandit.net/v1/status",
            "https://accounts.mrblindbandit.net/"
        ]
        for raw in urls {
            XCTAssertTrue(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: raw))), raw)
        }
    }

    func testExternalAndInsecureHostsAreRejected() throws {
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "https://example.com/"))))
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "http://mrblindbandit.net/"))))
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "https://mrblindbandit.net.example.com/"))))
    }

    func testAppVersionIsConfigured() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertNotNil(version)
    }

    func testDefaultAccessibilityPreferences() {
        UserDefaults.standard.removeObject(forKey: "announcePageLoads")
        UserDefaults.standard.removeObject(forKey: "reduceAppMotion")
        let preferences = AppPreferences()
        XCTAssertTrue(preferences.announcePageLoads)
        XCTAssertFalse(preferences.reduceAppMotion)
    }

    func testPhoneNormalizationForTesterRouting() {
        XCTAssertEqual(TestIdentity.normalizePhone(" +63 917-123-4567 "), "+639171234567")
        XCTAssertEqual(TestIdentity.routingKey(for: "+63 (917) 123-4567"), "639171234567")
        XCTAssertEqual(TestIdentity.normalizePhone("415 555 0199"), "4155550199")
    }

    func testInboxRoomNameIsStableAcrossPhoneFormatting() {
        let formatted = TestIdentity.inboxRoom(for: "+63 917 123 4567")
        let compact = TestIdentity.inboxRoom(for: "+639171234567")
        let other = TestIdentity.inboxRoom(for: "+639171234568")

        XCTAssertEqual(formatted, compact)
        XCTAssertNotEqual(compact, other)
        XCTAssertTrue(compact.hasPrefix("bb-inbox-"))
    }
}

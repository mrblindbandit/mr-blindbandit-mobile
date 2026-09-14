import XCTest
@testable import Blindbandit

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

    @MainActor
    func testDefaultAccessibilityPreferences() {
        UserDefaults.standard.removeObject(forKey: "announcePageLoads")
        UserDefaults.standard.removeObject(forKey: "reduceAppMotion")
        let preferences = AppPreferences()
        XCTAssertTrue(preferences.announcePageLoads)
        XCTAssertFalse(preferences.reduceAppMotion)
    }
}

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
            "https://accounts.mrblindbandit.net/",
            "https://clerk.mrblindbandit.net/"
        ]
        for raw in urls {
            XCTAssertTrue(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: raw))), raw)
        }
    }

    func testExternalAndInsecureHostsAreRejected() throws {
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "https://example.com/"))))
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "http://mrblindbandit.net/"))))
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "https://mrblindbandit.net.example.com/"))))
        XCTAssertFalse(Browser.isFirstPartyURL(try XCTUnwrap(URL(string: "javascript:alert(1)"))))
    }

    func testAPIURLBuilderPreservesPathAndQuery() throws {
        let url = try BlindbanditAPI.url("/v1/social/messages?limit=100")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.mrblindbandit.net")
        XCTAssertEqual(url.path, "/v1/social/messages")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "100")
    }

    func testAPIURLBuilderNormalizesLeadingSlash() throws {
        XCTAssertEqual(
            try BlindbanditAPI.url("v1/social/me").absoluteString,
            "https://api.mrblindbandit.net/v1/social/me"
        )
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

    func testAppConfigMarketingVersion() {
        XCTAssertEqual(AppConfig.marketingVersion, "1.6")
    }

    func testLiveKitDefaultRoom() {
        XCTAssertEqual(AppConfig.defaultLiveKitRoom, "mrblindbandit")
    }

    func testClerkPublishableKeyFormatWhenPresent() {
        let key = AppConfig.clerkPublishableKey
        if !key.isEmpty {
            XCTAssertTrue(key.hasPrefix("pk_"), "Publishable keys must start with pk_")
            XCTAssertFalse(key.hasPrefix("sk_"), "Secret keys must never appear in the client")
        }
    }
}

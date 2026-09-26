import XCTest
import SwiftUI
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
        XCTAssertEqual(AppConfig.marketingVersion, "1.7")
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

    func testEnvelopeUnwrapsProfile() throws {
        let json = #"{"success":true,"data":{"id":"profile_1","handle":"mrblindbandit","display_name":"Mr. Blindbandit"},"meta":{"request_id":"r1"}}"#
        let profile = try BlindbanditAPI.decode(BlindbanditSocialProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.handle, "mrblindbandit")
        XCTAssertEqual(profile.display_name, "Mr. Blindbandit")
    }

    func testEnvelopeUnwrapsCallWithLiveKitGrant() throws {
        let json = #"{"success":true,"data":{"id":"c1","room":"call_abc","kind":"video","status":"ringing","livekit":{"token":"t","identity":"p1","room":"call_abc","expires_at":1,"url":""}}}"#
        let call = try BlindbanditAPI.decode(BlindbanditCallResponse.self, from: Data(json.utf8))
        XCTAssertEqual(call.kind, "video")
        XCTAssertEqual(call.livekit.token, "t")
    }

    func testHandleNormalization() {
        XCTAssertEqual(BlindbanditHandle.normalize("  @MrBlindbandit "), "mrblindbandit")
    }

    func testLegalAndDeletionURLsAreFirstParty() {
        for url in [AppConfig.privacyURL, AppConfig.termsURL, AppConfig.supportURL, AppConfig.accountDeletionURL] {
            XCTAssertTrue(Browser.isFirstPartyURL(url), url.absoluteString)
        }
    }

    func testAppearanceOptions() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}

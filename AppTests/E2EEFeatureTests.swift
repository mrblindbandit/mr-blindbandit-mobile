import XCTest
@testable import Blindbandit

final class E2EEFeatureTests: XCTestCase {
    func testSettingsDecodeLenient() throws {
        let json = #"{"e2ee":"true","disappearing_seconds":300,"no_store":0,"security":{"screenshot_alerts":false},"my":{"read_receipts":"false"}}"#
        let s = try JSONDecoder().decode(ChatSecuritySettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.e2ee)
        XCTAssertEqual(s.disappearing_seconds, 300)
        XCTAssertFalse(s.no_store)
        XCTAssertFalse(s.security.screenshot_alerts)
        XCTAssertFalse(s.my.read_receipts)
        XCTAssertEqual(ChatSecuritySettings.timerLabel(604800), "7 days")
    }

    func testServerFeaturesTTL() {
        let d = UserDefaults(suiteName: "bbtest-\(UUID().uuidString)")!
        let f = ServerFeatures(defaults: d, ttl: 60)
        XCTAssertTrue(f.isAvailable(.unsend))
        let now = Date()
        f.markMissing(.unsend, now: now)
        XCTAssertFalse(f.isAvailable(.unsend, now: now.addingTimeInterval(30)))
        XCTAssertTrue(f.isAvailable(.unsend, now: now.addingTimeInterval(61)))
    }

    @MainActor func testAIParse() {
        XCTAssertEqual(AIAssistant.parse("@AI what time is it")?.isPrivate, false)
        XCTAssertEqual(AIAssistant.parse("@ai private summarize")?.isPrivate, true)
        XCTAssertEqual(AIAssistant.parse("/ai hello")?.isPrivate, true)
        XCTAssertNil(AIAssistant.parse("hello @AIden"))
    }

    func testScamQuickCheck() {
        XCTAssertTrue(ScamDetector.quickCheck("URGENT: verify your account now, send the gift card code and your OTP").suspicious)
        XCTAssertFalse(ScamDetector.quickCheck("See you at lunch tomorrow").suspicious)
    }

    func testCebuanoHeuristic() {
        XCTAssertEqual(CebuanoHeuristic.guess("Maayong buntag! Unsa imong ginabuhat karon?"), "ceb")
        XCTAssertEqual(CebuanoHeuristic.guess("Magandang umaga! Ano ang ginagawa mo ngayon?"), "tl")
    }

    func testActionDetectorTracking() {
        XCTAssertTrue(ActionDetector.detect("Your parcel 1Z999AA10123456784 ships today").contains { if case .tracking = $0.kind { return true }; return false })
    }
}

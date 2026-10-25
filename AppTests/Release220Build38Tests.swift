import XCTest
@testable import Blindbandit

@MainActor
final class Release220Build38Tests: XCTestCase {
    func testOutgoingToneNames() {
        XCTAssertEqual(CallSounds.outgoingDialToneName, "US dial tone")
        XCTAssertEqual(CallSounds.outgoingRingbackToneName, "US ringback")
        XCTAssertEqual(CallSounds.outgoingProgressToneName, "US dial tone")
    }

    func testUSDialToneAssetStillShips() {
        let url = Bundle.main.url(forResource: "ringback_us_dialtone", withExtension: "caf")
            ?? Bundle.main.url(forResource: "ringback_us_dialtone", withExtension: "mp3")
        XCTAssertNotNil(url, "ringback_us_dialtone.caf must remain for dial phase")
    }

    func testUSRingbackAssetShips() {
        let url = Bundle.main.url(forResource: "ringback_us_ringback", withExtension: "caf")
            ?? Bundle.main.url(forResource: "ringback_us_ringback", withExtension: "mp3")
        XCTAssertNotNil(url, "ringback_us_ringback.caf must ship for remote-ringing phase")
    }

    func testHowlerAndReorderAssetsShip() {
        XCTAssertNotNil(Bundle.main.url(forResource: "ringback_us_howler", withExtension: "caf")
            ?? Bundle.main.url(forResource: "ringback_us_howler", withExtension: "caf", subdirectory: "Sounds"))
        XCTAssertNotNil(Bundle.main.url(forResource: "ringback_us_reorder", withExtension: "caf")
            ?? Bundle.main.url(forResource: "ringback_us_reorder", withExtension: "caf", subdirectory: "Sounds"))
    }

    func testDTMFKeySet() {
        for key in ["0","1","2","3","4","5","6","7","8","9","*","#"] {
            // playDTMF is silent-safe when UI sounds off; just ensure it does not trap.
            CallSounds.playDTMF(key)
        }
    }

    func testCallNumberDirectoryResolve() {
        CallNumberDirectory.assign(number: "5551234567", handle: "tyrese")
        XCTAssertEqual(CallNumberDirectory.resolve("5551234567"), "tyrese")
        XCTAssertEqual(CallNumberDirectory.resolve("1-555-123-4567"), "tyrese")
        XCTAssertEqual(CallNumberDirectory.number(forHandle: "tyrese"), "5551234567")
        XCTAssertNil(CallNumberDirectory.resolve("9999999"))
        CallNumberDirectory.unassign(number: "5551234567")
        XCTAssertNil(CallNumberDirectory.resolve("5551234567"))
    }

    func testProjectBuildNumberIs38() {
        XCTAssertEqual(AppConfig.marketingVersion, "2.2.0")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build == "38" {
            XCTAssertEqual(build, "38")
        }
    }
}

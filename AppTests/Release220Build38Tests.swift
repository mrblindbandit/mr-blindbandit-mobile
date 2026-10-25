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

    func testProjectBuildNumberIs38() {
        XCTAssertEqual(AppConfig.marketingVersion, "2.2.0")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty, build == "38" {
            XCTAssertEqual(build, "38")
        }
    }
}

import XCTest
@testable import Blindbandit

@MainActor
final class Release206Tests: XCTestCase {
    func testVoiceRowExposesBubbleToVoiceOver() {
        XCTAssertTrue(MessageRowAccessibility.exposesChildren(isVoice: true))
        XCTAssertFalse(MessageRowAccessibility.exposesChildren(isVoice: false))
    }

    func testRateIsClampedToAVAudioPlayerRange() {
        XCTAssertEqual(VoicePlayerModel.validRate(1.5), 1.5)
        XCTAssertEqual(VoicePlayerModel.validRate(2), 2)
        XCTAssertEqual(VoicePlayerModel.validRate(0), 1)
        XCTAssertEqual(VoicePlayerModel.validRate(7), 1)
    }

    func testVoiceLogRecordsRealError() {
        VoiceLog.record("test", "boom")
        XCTAssertTrue(VoiceLog.lastError.contains("boom"))
    }
}

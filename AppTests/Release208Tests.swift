import XCTest
@testable import Blindbandit

@MainActor
final class Release208Tests: XCTestCase {
    /// Voice message rows expose Play (or Pause) as the first VoiceOver Actions rotor name.
    func testVoiceRowExposesPlayAccessibilityActionName() {
        XCTAssertEqual(MessageRowAccessibility.voicePlayActionName(isPlayingCurrent: false), "Play")
        XCTAssertEqual(MessageRowAccessibility.voicePlayActionName(isPlayingCurrent: true), "Pause")
        XCTAssertTrue(MessageRowAccessibility.exposesChildren(isVoice: true))
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: "audio/mp4", kind: "voice", decryptedType: "voice"))
        XCTAssertFalse(VoiceRowPlayAction.isVoice(mime: "text/plain", kind: "text", decryptedType: "text"))
    }
}

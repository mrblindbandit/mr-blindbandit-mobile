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

    func testHeatRingtoneInPicker() {
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.rawValue, "ringtone_mrblindbandit_heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.title, "Mr. BlindBandit Heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.rawValue, "ringtone_mrblindbandit")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditClassic.rawValue, "ringtone_mrblindbandit_classic")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditAlt.rawValue, "ringtone_mrblindbandit_alt")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditNight.rawValue, "ringtone_mrblindbandit_night")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditPulse.rawValue, "ringtone_mrblindbandit_pulse")
    }
}

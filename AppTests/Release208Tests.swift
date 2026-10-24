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

    func testCleanRingtonePickerTitles() {
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.title, "Mr. BlindBandit")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditClassic.title, "Classic")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditAlt.title, "Alt")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditNight.title, "Night")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditPulse.title, "Pulse")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.title, "Heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditRise.title, "Rise")
        XCTAssertEqual(CallSounds.Ringtone.pulse.title, "Pulse Tone")
        XCTAssertEqual(CallSounds.Ringtone.ambientAurora.title, "Aurora")
        XCTAssertEqual(CallSounds.Ringtone.ambientNight.title, "Night Ambient")
        // Picker labels must never be raw filenames.
        for tone in CallSounds.Ringtone.allCases {
            XCTAssertFalse(tone.title.contains(".caf"), tone.rawValue)
            XCTAssertFalse(tone.title.hasPrefix("ringtone_"), tone.rawValue)
            XCTAssertNotEqual(tone.title, tone.rawValue)
        }
    }

    func testHeatAndRiseRingtonesInPicker() {
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.rawValue, "ringtone_mrblindbandit_heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.title, "Heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.rawValue, "ringtone_mrblindbandit")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditClassic.rawValue, "ringtone_mrblindbandit_classic")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditAlt.rawValue, "ringtone_mrblindbandit_alt")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditNight.rawValue, "ringtone_mrblindbandit_night")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditPulse.rawValue, "ringtone_mrblindbandit_pulse")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditRise.rawValue, "ringtone_mrblindbandit_rise")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditRise.title, "Rise")
    }
}

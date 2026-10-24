import XCTest
@testable import Blindbandit

@MainActor
final class Release207Tests: XCTestCase {
    func testGroupVoiceRowExposesBubbleToVoiceOver() {
        XCTAssertTrue(MessageRowAccessibility.exposesChildren(isVoice: true))
        XCTAssertFalse(MessageRowAccessibility.exposesChildren(isVoice: false))
    }

    func testPreviewPrivacyCandidateKeysIncludeDmAndGroup() {
        let suite = UserDefaults(suiteName: PreviewPrivacy.appGroup)!
        let chatKey = "dm:abc"
        suite.removeObject(forKey: "hidePreviews." + chatKey)
        suite.removeObject(forKey: "hidePreviews.abc")
        var s = ChatSecuritySettings()
        s.my.hide_previews = true
        s.my.mute_sound = true
        ChatSettingsCache.set(s, chatKey)
        XCTAssertTrue(suite.bool(forKey: "hidePreviews.dm:abc"))
        XCTAssertTrue(suite.bool(forKey: "hidePreviews.abc"))
        XCTAssertTrue(suite.bool(forKey: "muteSound.dm:abc"))
        suite.removeObject(forKey: "hidePreviews.dm:abc")
        suite.removeObject(forKey: "hidePreviews.abc")
        suite.removeObject(forKey: "muteSound.dm:abc")
        suite.removeObject(forKey: "muteSound.abc")
    }

    func testGroupOptimisticLocalMessage() {
        let m = BlindbanditGroupMessage.local(id: "local-1", handle: "kheck", name: "You", body: "hi")
        XCTAssertTrue(m.id.hasPrefix("local-"))
        XCTAssertEqual(m.body, "hi")
        XCTAssertEqual(m.sender_handle, "kheck")
    }

    func testAltRingtoneInPicker() {
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditAlt.rawValue, "ringtone_mrblindbandit_alt")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditAlt.title, "Mr. BlindBandit Alt")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditNight.rawValue, "ringtone_mrblindbandit_night")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditNight.title, "Mr. BlindBandit Night")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditPulse.rawValue, "ringtone_mrblindbandit_pulse")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditPulse.title, "Mr. BlindBandit Pulse")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.rawValue, "ringtone_mrblindbandit_heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditHeat.title, "Mr. BlindBandit Heat")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditRise.rawValue, "ringtone_mrblindbandit_rise")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBanditRise.title, "Mr. BlindBandit Rise")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.rawValue, "ringtone_mrblindbandit")
    }

    func testAIPersonaOwnerGate() {
        let prev = AIPersona.serverHandle
        AIPersona.serverHandle = "kheck"
        XCTAssertTrue(AIPersona.isOwner)
        AIPersona.serverHandle = "someoneelse"
        XCTAssertFalse(AIPersona.isOwner)
        XCTAssertEqual(AIPersona.forPrivate, .professional)
        AIPersona.serverHandle = prev
    }

    func testVoiceRowPlayActionName() {
        XCTAssertEqual(MessageRowAccessibility.voicePlayActionName(isPlayingCurrent: false), "Play")
        XCTAssertEqual(MessageRowAccessibility.voicePlayActionName(isPlayingCurrent: true), "Pause")
        XCTAssertEqual(VoiceRowPlayAction.actionName(isPlayingCurrent: false), "Play")
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: "audio/m4a"))
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: nil, kind: "voice"))
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: nil, decryptedType: "voice"))
        XCTAssertFalse(VoiceRowPlayAction.isVoice(mime: "image/jpeg"))
    }
}

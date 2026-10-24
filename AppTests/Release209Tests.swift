import XCTest
@testable import Blindbandit

@MainActor
final class Release209Tests: XCTestCase {
    func testVoicePlayableMediaAndRowContainment() {
        let audio = E2EEPayload.Media(
            url: nil, attachment_id: "a1", key: "YQ==", nonce: "YQ==",
            sha256: "YQ==", mime: "audio/mp4", size: 1, filename: "voice.m4a",
            caption: nil, view_once: nil, duration: 1, transcript: nil, alt: nil
        )
        XCTAssertTrue(VoiceRowPlayAction.hasPlayableVoiceMedia(audio))
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: "audio/mp4"))
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: nil, kind: "voice"))
        XCTAssertTrue(VoiceRowPlayAction.isVoice(mime: "text/plain", decryptedType: "voice"))
        XCTAssertFalse(VoiceRowPlayAction.isVoice(mime: "image/jpeg", kind: "image", decryptedType: "image"))
        XCTAssertTrue(MessageRowAccessibility.exposesChildren(isVoice: true))
        XCTAssertFalse(MessageRowAccessibility.exposesChildren(isVoice: false))
        XCTAssertEqual(MessageRowAccessibility.voicePlayActionName(isPlayingCurrent: false), "Play")
        XCTAssertEqual(MessageRowAccessibility.voicePlayActionName(isPlayingCurrent: true), "Pause")
    }

    func testVoiceRateClampStillHolds() {
        XCTAssertEqual(VoicePlayerModel.validRate(1.5), 1.5)
        XCTAssertEqual(VoicePlayerModel.validRate(9), 1)
    }

    func testAnsweredElsewhereEchoDetector() {
        XCTAssertTrue(CallKitManager.isAnsweredElsewhereEcho(["reason": "Call answered on another device"]))
        XCTAssertTrue(CallKitManager.isAnsweredElsewhereEcho(["message": "Answered elsewhere"]))
        XCTAssertTrue(CallKitManager.isAnsweredElsewhereEcho([
            "aps": ["alert": ["body": "Call answered on another device"]] as [String: Any]
        ] as [AnyHashable: Any]))
        XCTAssertFalse(CallKitManager.isAnsweredElsewhereEcho(["reason": "remote hangup"]))
        XCTAssertFalse(CallKitManager.isAnsweredElsewhereEcho([:]))
    }

    func testEndedCallsStaleUsesCreatedAt() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        XCTAssertFalse(EndedCalls.isStale(createdAtMs: nowMs))
        XCTAssertTrue(EndedCalls.isStale(createdAtMs: nowMs - 60_000))
        XCTAssertFalse(EndedCalls.isStale(createdAtMs: 0))
    }

    func testEncryptionPasscodeValidation() {
        XCTAssertTrue(EncryptionPasscode.isValid("123456"))
        XCTAssertTrue(EncryptionPasscode.isValid("secret1"))
        XCTAssertFalse(EncryptionPasscode.isValid("12345"))
        XCTAssertFalse(EncryptionPasscode.isValid("abc"))
    }

    func testInstallationIDStable() {
        let a = BlindbanditAPI.installationID
        let b = BlindbanditAPI.installationID
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, b)
    }

    func testDefaultRingtoneUntouched() {
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.rawValue, "ringtone_mrblindbandit")
        XCTAssertEqual(CallSounds.Ringtone.mrBlindBandit.title, "Mr. BlindBandit")
    }
}

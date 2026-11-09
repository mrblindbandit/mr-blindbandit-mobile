import XCTest
@testable import Blindbandit

@MainActor
final class VoiceAttachmentIdentityTests: XCTestCase {
    func testTranscriptOnlyMessageDoesNotCreateDeadPlayControl() {
        let id = "voice-missing-" + UUID().uuidString
        let media = VoiceRowPlayAction.resolveVoiceMedia(
            messageID: id,
            clientMsgID: id,
            decrypted: nil,
            kind: "voice",
            body: "🎤 Voice message (4 s, transcribed on my iPhone): hello"
        )
        XCTAssertNil(media)
    }

    func testEncryptedVoiceMediaKeepsAttachmentIdentityThroughJSON() throws {
        let media = E2EEPayload.Media(
            url: nil,
            attachment_id: "att-voice-123",
            key: "a2V5",
            nonce: "bm9uY2U=",
            sha256: "",
            mime: "audio/mp4",
            size: 16,
            filename: "voice.m4a",
            caption: nil,
            view_once: nil,
            duration: 4,
            transcript: "hello",
            alt: nil
        )
        let payload = E2EEPayload(t: "voice", media: media)
        let decoded = try JSONDecoder().decode(E2EEPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded.media?.attachment_id, "att-voice-123")
    }
}

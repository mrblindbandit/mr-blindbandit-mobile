import XCTest
@testable import Blindbandit

final class MusicIntentTests: XCTestCase {
    func testPlaySong() {
        XCTAssertEqual(MusicIntent.parse("Play Blinding Lights on Apple Music"), MusicIntent(action: "play", query: "blinding lights", kind: "any"))
    }
    func testPlayBy() {
        XCTAssertEqual(MusicIntent.parse("play Blinding Lights by The Weeknd"), MusicIntent(action: "play", query: "blinding lights the weeknd", kind: "song"))
    }
    func testAlbumAndPlaylist() {
        XCTAssertEqual(MusicIntent.parse("play the album After Hours")?.kind, "album")
        XCTAssertEqual(MusicIntent.parse("play my chill playlist")?.kind, "playlist")
    }
    func testControls() {
        XCTAssertEqual(MusicIntent.parse("pause")?.action, "pause")
        XCTAssertEqual(MusicIntent.parse("Skip.")?.action, "next")
        XCTAssertEqual(MusicIntent.parse("previous song")?.action, "previous")
        XCTAssertEqual(MusicIntent.parse("resume")?.action, "resume")
        XCTAssertEqual(MusicIntent.parse("can you play Drake please")?.query, "drake")
    }
    func testLibrary() {
        XCTAssertEqual(MusicIntent.parse("shuffle my library"), MusicIntent(action: "library", kind: "shuffle"))
    }
    func testNonMusic() {
        XCTAssertNil(MusicIntent.parse("what's the weather"))
        XCTAssertNil(MusicIntent.parse("play a game with me"))
        XCTAssertNil(MusicIntent.parse("tell me about the play Hamilton"))
    }
}

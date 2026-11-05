import Foundation
import XCTest
@testable import Blindbandit

final class CallSpatialLayoutTests: XCTestCase {
    func testAudioPolicyMatchesHighQualityStereoContract() {
        XCTAssertEqual(CallAudioPolicy.musicHighQualityStereo, 5)
        XCTAssertEqual(CallAudioPolicy.gameStreamingScenario, 3)
        XCTAssertEqual(CallAudioPolicy.stereoProcessingChannels, 2)
        XCTAssertTrue(CallAudioPolicy.echoCancellation)
        XCTAssertFalse(CallAudioPolicy.noiseSuppression)
        XCTAssertFalse(CallAudioPolicy.aiNoiseSuppression)
        XCTAssertTrue(CallAudioPolicy.automaticGainControl)
        XCTAssertEqual(CallAudioPolicy.unityVolume, 100)
    }

    func testOneToOneSeatIsInFront() {
        let seats = CallSpatialLayout.seats(count: 1)
        XCTAssertEqual(seats.count, 1)
        XCTAssertEqual(seats[0].spokenDirection, "in front of you")
        XCTAssertGreaterThan(seats[0].front, 0)
        XCTAssertEqual(seats[0].right, 0, accuracy: 0.001)
        XCTAssertEqual(seats[0].top, 0, accuracy: 0.001)
        assertFacesListener(seats[0])
    }

    func testTwoPeopleSitLeftAndRight() {
        let seats = CallSpatialLayout.seats(count: 2)
        XCTAssertEqual(seats[0].spokenDirection, "on your left")
        XCTAssertEqual(seats[1].spokenDirection, "on your right")
        XCTAssertLessThan(seats[0].right, 0)
        XCTAssertGreaterThan(seats[1].right, 0)
        XCTAssertEqual(CallSpatialLayout.joinedAnnouncement(name: "Emma", direction: seats[0].spokenDirection), "Emma joined, on your left.")
    }

    func testThreePeopleKeepSomeoneInFront() {
        let seats = CallSpatialLayout.seats(count: 3)
        XCTAssertEqual(seats.map(\.spokenDirection), ["on your left", "in front of you", "on your right"])
    }

    func testEmptyAndLargeCirclesStayInsideHearingRange() {
        XCTAssertTrue(CallSpatialLayout.seats(count: 0).isEmpty)
        let seats = CallSpatialLayout.seats(count: 8)
        XCTAssertEqual(seats.count, 8)
        XCTAssertEqual(seats[0].spokenDirection, "in front of you")
        for seat in seats {
            let distance = sqrt(seat.front * seat.front + seat.right * seat.right + seat.top * seat.top)
            XCTAssertLessThan(distance, CallSpatialLayout.receiveRange)
            assertFacesListener(seat)
        }
    }

    func testRoutesKeepHeadphonesAndLeaveSpeakerWithoutEQ() {
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 3).kind, .speaker)
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 3).headphoneEQ, .off)
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 1).label, "earpiece")
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 0).kind, .wired)
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 0).headphoneEQ, .overEar)
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 5).kind, .bluetooth)
        XCTAssertEqual(CallAudioRoute.from(agoraRoute: 10).headphoneEQ, .inEar)
        XCTAssertTrue(CallAudioRoute.from(agoraRoute: 5).isExternal)
        XCTAssertFalse(CallAudioRoute.from(agoraRoute: 4).isExternal)
    }

    func testGroupStaysOpenAfterTheLastPersonLeaves() {
        XCTAssertTrue(CallSpatialLayout.shouldEndImmediately(isGroup: false, remotesRemaining: 0, hadRemote: true))
        XCTAssertFalse(CallSpatialLayout.shouldEndImmediately(isGroup: true, remotesRemaining: 0, hadRemote: true))
        XCTAssertFalse(CallSpatialLayout.shouldEndImmediately(isGroup: false, remotesRemaining: 0, hadRemote: false))
        XCTAssertEqual(CallSpatialLayout.groupAloneSeconds, 120)
        XCTAssertEqual(CallSpatialLayout.movedAnnouncement(name: "Emma", direction: "on your left"), "Emma moved. Now on your left.")
    }

    private func assertFacesListener(_ seat: CallSpatialSeat) {
        let dot = seat.front * seat.forwardFront + seat.right * seat.forwardRight + seat.top * seat.forwardTop
        XCTAssertLessThan(dot, 0.01)
    }
}

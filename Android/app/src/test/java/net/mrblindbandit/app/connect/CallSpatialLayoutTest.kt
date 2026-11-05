package net.mrblindbandit.app.connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.sqrt

class CallSpatialLayoutTest {
    @Test fun audioPolicyMatchesHighQualityStereoContract() {
        assertEquals(5, CallAudioPolicy.musicHighQualityStereo)
        assertEquals(3, CallAudioPolicy.gameStreamingScenario)
        assertEquals(2, CallAudioPolicy.stereoProcessingChannels)
        assertTrue(CallAudioPolicy.echoCancellation)
        assertFalse(CallAudioPolicy.noiseSuppression)
        assertFalse(CallAudioPolicy.aiNoiseSuppression)
        assertTrue(CallAudioPolicy.automaticGainControl)
        assertEquals(100, CallAudioPolicy.unityVolume)
    }

    @Test fun oneToOneSeatIsInFront() {
        val seats = CallSpatialLayout.seats(1)
        assertEquals(1, seats.size)
        assertEquals("in front of you", seats[0].spokenDirection)
        assertTrue(seats[0].front > 0f)
        assertEquals(0f, seats[0].right, 0.001f)
        assertFacesListener(seats[0])
    }

    @Test fun twoPeopleSitLeftAndRight() {
        val seats = CallSpatialLayout.seats(2)
        assertEquals("on your left", seats[0].spokenDirection)
        assertEquals("on your right", seats[1].spokenDirection)
        assertTrue(seats[0].right < 0f)
        assertTrue(seats[1].right > 0f)
        assertEquals("Emma joined, on your left.", CallSpatialLayout.joinedAnnouncement("Emma", seats[0].spokenDirection))
    }

    @Test fun threePeopleKeepSomeoneInFront() {
        val directions = CallSpatialLayout.seats(3).map { it.spokenDirection }
        assertEquals(listOf("on your left", "in front of you", "on your right"), directions)
    }

    @Test fun emptyAndLargeCirclesStayInsideHearingRange() {
        assertTrue(CallSpatialLayout.seats(0).isEmpty())
        val seats = CallSpatialLayout.seats(8)
        assertEquals(8, seats.size)
        assertEquals("in front of you", seats[0].spokenDirection)
        seats.forEach { seat ->
            val distance = sqrt(seat.front * seat.front + seat.right * seat.right + seat.top * seat.top)
            assertTrue(distance < CallSpatialLayout.RECEIVE_RANGE)
            assertFacesListener(seat)
        }
    }

    @Test fun routesKeepHeadphonesAndLeaveSpeakerWithoutEQ() {
        assertEquals(CallAudioRoute.Kind.SPEAKER, CallAudioRoute.from(3).kind)
        assertEquals(CallAudioRoute.HeadphoneEQ.OFF, CallAudioRoute.from(3).headphoneEQ)
        assertEquals("earpiece", CallAudioRoute.from(1).label)
        assertEquals(CallAudioRoute.Kind.WIRED, CallAudioRoute.from(0).kind)
        assertEquals(CallAudioRoute.HeadphoneEQ.OVER_EAR, CallAudioRoute.from(0).headphoneEQ)
        assertEquals(CallAudioRoute.Kind.BLUETOOTH, CallAudioRoute.from(5).kind)
        assertEquals(CallAudioRoute.HeadphoneEQ.IN_EAR, CallAudioRoute.from(10).headphoneEQ)
        assertTrue(CallAudioRoute.from(5).isExternal)
        assertFalse(CallAudioRoute.from(4).isExternal)
    }

    @Test fun groupStaysOpenAfterTheLastPersonLeaves() {
        assertTrue(CallSpatialLayout.shouldEndImmediately(isGroup = false, remotesRemaining = 0, hadRemote = true))
        assertFalse(CallSpatialLayout.shouldEndImmediately(isGroup = true, remotesRemaining = 0, hadRemote = true))
        assertFalse(CallSpatialLayout.shouldEndImmediately(isGroup = false, remotesRemaining = 0, hadRemote = false))
        assertEquals(120_000L, CallSpatialLayout.GROUP_ALONE_MS)
        assertEquals("Emma moved. Now on your left.", CallSpatialLayout.movedAnnouncement("Emma", "on your left"))
    }

    private fun assertFacesListener(seat: CallSpatialSeat) {
        val dot = seat.front * seat.forwardFront + seat.right * seat.forwardRight + seat.top * seat.forwardTop
        assertTrue(dot < 0.01f)
    }
}

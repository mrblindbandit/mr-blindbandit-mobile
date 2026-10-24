
package net.mrblindbandit.app.connect

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class VoicePlaybackTest {
    @Test
    fun clockFormatsMinutesAndSeconds() {
        assertEquals("0:00", VoicePlayback.clock(0.0))
        assertEquals("0:05", VoicePlayback.clock(5.0))
        assertEquals("1:01", VoicePlayback.clock(61.0))
    }

    @Test
    fun validRateClamps() {
        assertEquals(1f, VoicePlayback.validRate(0f), 0.001f)
        assertEquals(1.5f, VoicePlayback.validRate(1.5f), 0.001f)
        assertEquals(1f, VoicePlayback.validRate(9f), 0.001f)
    }

    @Test
    fun rateLabel() {
        assertEquals("1x", VoicePlayback.rateLabel(1f))
        assertEquals("1.5x", VoicePlayback.rateLabel(1.5f))
        assertEquals("2x", VoicePlayback.rateLabel(2f))
    }

    @Test
    fun isVoiceMediaDetectsMimeAndFilename() {
        assertTrue(VoicePlayback.isVoiceMedia(JSONObject().put("mime", "audio/mp4")))
        assertTrue(VoicePlayback.isVoiceMedia(JSONObject().put("filename", "voice.m4a")))
        assertFalse(VoicePlayback.isVoiceMedia(JSONObject().put("mime", "image/jpeg")))
        assertFalse(VoicePlayback.isVoiceMedia(null))
    }
}

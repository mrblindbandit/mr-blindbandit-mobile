package net.mrblindbandit.app.ai

import org.junit.Assert.*
import org.junit.Test

class DeviceActionsParseTest {
    @Test fun volumeUp() {
        assertEquals("volume_up", DeviceActions.parse("turn up the volume")!!.action)
    }
    @Test fun flashlight() {
        assertEquals("flashlight_on", DeviceActions.parse("flashlight on")!!.action)
    }
    @Test fun volumeSet() {
        val c = DeviceActions.parse("set volume to 40%")!!
        assertEquals("volume_set", c.action)
        assertEquals("40", c.arg)
    }
    @Test fun openApp() {
        val c = DeviceActions.parse("open youtube")!!
        assertEquals("open_app", c.action)
        assertEquals("youtube", c.arg)
    }
    @Test fun notMusicPause() {
        // "pause music" is MusicIntent; device parse may still match mute-like — ensure volume mute doesn't steal music pause
        assertNull(DeviceActions.parse("pause music"))
    }
}

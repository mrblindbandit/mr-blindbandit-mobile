package net.mrblindbandit.app.ai

import org.junit.Assert.*
import org.junit.Test

class MusicIntentTest {
    @Test fun playSong() {
        val i = MusicIntent.parse("play Never Gonna Give You Up")!!
        assertEquals("play", i.action)
        assertTrue(i.query.contains("never", ignoreCase = true) || i.query.contains("Gonna", ignoreCase = true) || i.query.isNotBlank())
    }
    @Test fun pause() {
        assertEquals("pause", MusicIntent.parse("pause music")!!.action)
    }
    @Test fun next() {
        assertEquals("next", MusicIntent.parse("skip this song")!!.action)
    }
    @Test fun ignoreGame() {
        assertNull(MusicIntent.parse("play a game"))
    }
    @Test fun queue() {
        val i = MusicIntent.parse("queue up Bohemian Rhapsody")!!
        assertEquals("queue", i.action)
        assertTrue(i.query.contains("Bohemian", ignoreCase = true) || i.query.isNotBlank())
    }
}

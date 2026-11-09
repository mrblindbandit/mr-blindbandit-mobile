package net.mrblindbandit.app.connect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushPreviewSanitizerTest {
    @Test fun callFrameKeyNeverBecomesVisibleText() {
        val raw = """{"index":0,"call_id":"29904bbb-9578-4143-8dc3-7b4d1f1839d7","key":"UhXO7RcJV0","nonce":"secret"}"""
        assertTrue(PushPreviewSanitizer.isCallControl(raw))
        assertTrue(PushPreviewSanitizer.containsSensitiveJson(raw))
        assertEquals("New message", PushPreviewSanitizer.visibleBody(raw, false, false, "Caller"))
    }

    @Test fun normalMessagesRemainVisibleWhenPreviewsAreEnabled() {
        assertFalse(PushPreviewSanitizer.containsSensitiveJson("See you after the show"))
        assertEquals("See you after the show", PushPreviewSanitizer.visibleBody("See you after the show", false, false, "Caller"))
    }

    @Test fun callsUseHumanReadableText() {
        assertEquals("Alex is calling", PushPreviewSanitizer.visibleBody("{}", true, false, "Alex"))
    }
}

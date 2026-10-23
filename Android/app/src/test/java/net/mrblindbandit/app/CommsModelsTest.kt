package net.mrblindbandit.app

import net.mrblindbandit.app.connect.CommsDestination
import net.mrblindbandit.app.connect.Lenient
import net.mrblindbandit.app.connect.Receipt
import net.mrblindbandit.app.connect.ServerConversation
import net.mrblindbandit.app.connect.ServerMessage
import net.mrblindbandit.app.connect.items
import net.mrblindbandit.app.connect.lBool
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CommsModelsTest {
    @Test fun lenientBooleans() {
        listOf(true, 1, "1", "true", "yes").forEach { assertEquals(true, Lenient.bool(it)) }
        listOf(false, 0, "0", "false", "no").forEach { assertEquals(false, Lenient.bool(it)) }
        assertTrue(JSONObject("""{"other_typing":"1"}""").lBool("other_typing"))
        assertFalse(JSONObject("{}").lBool("other_typing"))
    }

    @Test fun timestampsSecondsMillisIso() {
        assertEquals(1_700_000_000_000L, Lenient.timestamp(1_700_000_000L))
        assertEquals(1_700_000_000_000L, Lenient.timestamp(1_700_000_000_000L))
        assertEquals(0L, Lenient.timestamp("1970-01-01T00:00:00Z"))
        assertNull(Lenient.timestamp(null))
    }

    @Test fun conversationAndReceipts() {
        val json = JSONObject("""{"items":[{"id":"c1","unread_count":"2","other":{"handle":"amy","display_name":"Amy","verified":1},
            "last_message":{"body":"hi","sender_id":"p2","created_at":"2026-10-23T01:00:00Z"}}]}""")
        val c = ServerConversation.parse(json.items().first())!!
        assertEquals(2, c.unreadCount); assertTrue(c.verified); assertEquals("Amy", c.peerName)
        val m = ServerMessage.parse(JSONObject("""{"id":"m","sender_id":"me","body":"x","created_at":1,"delivered_at":2,"read_at":null}"""))!!
        assertEquals(Receipt.DELIVERED, m.receipt)
        assertEquals(Receipt.READ, m.copy(readAt = 3).receipt)
        assertEquals(Receipt.SENDING, m.copy(pending = true).receipt)
    }

    @Test fun destinations() {
        assertEquals(CommsDestination.Thread("abc"), CommsDestination.parse("https://mrblindbandit.net/messages/abc"))
        assertEquals(CommsDestination.Call("k9"), CommsDestination.parse("/mobile/calls/k9"))
        assertEquals(CommsDestination.Calls, CommsDestination.parse("/mobile/calls"))
        assertEquals(CommsDestination.Thread("x"), CommsDestination.parse(null, conversationId = "x"))
        assertNull(CommsDestination.parse("/music/"))
    }
}

package net.mrblindbandit.app

import net.mrblindbandit.app.connect.CallRtcGrant
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
        // Optimistic local bubbles show Sent immediately (Android 2.0.12 / iOS TF 39).
        assertEquals(Receipt.SENT, m.copy(id = "local-abc", pending = false, clientMsgId = "local-abc").receipt)
        assertEquals(Receipt.SENT, m.copy(id = "local-abc", pending = true).receipt)
        val withClient = ServerMessage.parse(JSONObject("""{"id":"srv1","sender_id":"me","body":"x","created_at":1,"client_msg_id":"local-abc"}"""))!!
        assertEquals("local-abc", withClient.clientMsgId)
    }

    @Test fun pushTerminalEventsAreNotIncomingCalls() {
        val ended = net.mrblindbandit.app.connect.PushPayload.parse(mapOf("type" to "call_end", "call_id" to "k9"))
        assertTrue(ended.endsCall)
        assertEquals("call:k9", ended.key)
        val invite = net.mrblindbandit.app.connect.PushPayload.parse(mapOf("type" to "call_invite", "call_id" to "k9"))
        assertFalse(invite.endsCall)
        assertEquals(ended.key, invite.key)
        assertFalse(net.mrblindbandit.app.connect.PushPayload.parse(mapOf("type" to "message")).isCall)
    }
    @Test fun callRtcGrantParsesNestedAgora() {
        val json = JSONObject("""{"id":"c2","room":"call_xyz","kind":"voice","status":"ringing","provider":"agora","livekit":null,"agora":{"token":"atok","app_id":"app123","channel":"call_xyz","uid":"42"},"token":"atok","app_id":"app123","channel":"call_xyz","uid":"42"}""")
        val g = CallRtcGrant.parse(json)
        assertEquals("agora", g.provider)
        assertTrue(g.usesAgora)
        assertEquals("app123", g.agoraAppId)
        assertEquals("atok", g.agoraToken)
        assertEquals("call_xyz", g.agoraChannel)
        assertEquals(42, g.agoraUid)
        assertNull(g.livekitToken)
    }

    @Test fun callRtcGrantParsesFlatAgoraAndLegacyLiveKit() {
        val agora = CallRtcGrant.parse(JSONObject("""{"call_id":"c3","room":"room1","provider":"agora","token":"flatTok","app_id":"flatApp","channel":"room1","uid":99}"""))
        assertTrue(agora.usesAgora)
        assertEquals(99, agora.agoraUid)
        val lk = CallRtcGrant.parse(JSONObject("""{"call_id":"c4","room":"r","token":"lk","livekit_url":"wss://example.livekit.cloud"}"""))
        assertEquals("livekit", lk.provider)
        assertFalse(lk.usesAgora)
        assertEquals("lk", lk.livekitToken)
        assertEquals("wss://example.livekit.cloud", lk.livekitUrl)
    }

    @Test fun destinations() {
        assertEquals(CommsDestination.Thread("abc"), CommsDestination.parse("https://mrblindbandit.net/messages/abc"))
        assertEquals(CommsDestination.Call("k9"), CommsDestination.parse("/mobile/calls/k9"))
        assertEquals(CommsDestination.Calls, CommsDestination.parse("/mobile/calls"))
        assertEquals(CommsDestination.Thread("x"), CommsDestination.parse(null, conversationId = "x"))
        assertNull(CommsDestination.parse("/music/"))
        assertEquals(CommsDestination.Thread("abc"), CommsDestination.parse("/mobile/messages/?c=abc"))
        assertEquals(CommsDestination.Thread("a:b"), CommsDestination.parse("/mobile/messages/?id=a%3Ab"))
        assertEquals(CommsDestination.Thread("abc"), CommsDestination.parse("/mobile/messages/?conversation_id=abc"))
        assertEquals(CommsDestination.Call("k9"), CommsDestination.parse("/mobile/calls/?call_id=k9"))
        assertEquals(CommsDestination.Group("g1"), CommsDestination.parse("/mobile/groups/?id=g1"))
        assertEquals(CommsDestination.Thread("abc"), CommsDestination.parse("mrblindbandit://messages/abc"))
        assertNull(CommsDestination.parse("https://evilmrblindbandit.net/messages/abc"))
        assertNull(CommsDestination.parse("https://example.com/messages/abc"))
        assertNull(CommsDestination.parse("//example.com/messages/abc"))
        assertEquals(CommsDestination.Call("k9"), CommsDestination.parse(null, conversationId = "abc", callId = "k9"))
    }
}

package net.mrblindbandit.app.security

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CallFrameKeysTest {
    @Test fun iosWireRoundTripIsBoundToAuthenticatedCallerAndCall() {
        val store = CallFrameKeys()
        val key = CallFrameKeys.newKey("call-a")
        store.receive(key.wire(), "alice", 100)
        assertEquals(key.secret, store.get("call-a", "alice", 101)?.secret)
        assertNull(store.get("call-b", "alice", 101))
        assertNull(store.get("call-a", "mallory", 101))
        assertFalse(key.toString().contains(key.secret))
        store.clear("call-a")
        assertNull(store.get("call-a", "alice", 101))
    }
    @Test fun rejectsInvalidKeysAndExpiredEntries() {
        val store = CallFrameKeys()
        val key = CallFrameKeys.newKey("call-a")
        for (wire in listOf("invalid", JSONObject(key.wire()).put("index", -1).toString(),
            JSONObject(key.wire()).put("key", "short").toString(), JSONObject(key.wire()).put("call_id", "").toString())) {
            store.receive(wire, "alice", 100)
            assertNull(store.get("call-a", "alice", 101))
        }
        store.receive(key.wire(), "", 100)
        assertNull(store.get("call-a", "", 101))
        store.receive(key.wire(), "alice", 100)
        assertNull(store.get("call-a", "alice", 3_600_101))
    }
    @Test fun rotationIsMonotonicAndSenderCannotOverwriteAnotherCaller() {
        val store = CallFrameKeys()
        val first = CallFrameKeys.newKey("call-a")
        val next = CallFrameKeys.Key(first.callId, CallFrameKeys.newKey("call-a").secret, 1)
        store.receive(first.wire(), "alice", 100)
        store.receive(next.wire(), "alice", 101)
        store.receive(first.wire(), "alice", 102)
        store.receive(first.wire(), "mallory", 103)
        assertEquals(next.secret, store.get("call-a", "alice", 104)?.secret)
        assertEquals(1, store.get("call-a", "alice", 104)?.index)
    }
}

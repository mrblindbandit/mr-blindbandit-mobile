package net.mrblindbandit.app.security

import org.json.JSONObject

/** Memory-only call keys. Accept only already-decrypted control payloads and bind to the caller. */
internal class CallFrameKeys {
    class Key(val callId: String, val secret: String, val index: Int) {
        fun wire(): String = JSONObject().put("call_id", callId).put("key", secret).put("index", index).toString()
        override fun toString() = "CallFrameKey(index=$index)"
    }
    private data class Entry(val key: Key, val receivedAt: Long)
    private val keys = mutableMapOf<Pair<String, String>, Entry>()
    fun receive(body: String, senderId: String, now: Long = System.currentTimeMillis()) {
        if (senderId.isBlank()) return
        val key = runCatching {
            val o = JSONObject(body)
            val id = o.getString("call_id")
            val secret = o.getString("key")
            val index = o.getInt("index")
            require(id.isNotBlank() && id.length <= 200 && index >= 0 && P256Crypto.unb64(secret).size == 32)
            Key(id, secret, index)
        }.getOrNull() ?: return
        prune(now)
        val identity = key.callId to senderId
        if ((keys[identity]?.key?.index ?: -1) >= key.index) return
        // Bound controls from long histories; never write call frame keys to logs or preferences.
        if (keys.size >= 64) keys.remove(keys.minBy { it.value.receivedAt }.key)
        keys[identity] = Entry(key, now)
    }
    fun get(callId: String, senderId: String, now: Long = System.currentTimeMillis()): Key? {
        prune(now)
        return keys[callId to senderId]?.key
    }
    fun clear(callId: String) { keys.keys.removeAll { it.first == callId } }
    private fun prune(now: Long) { keys.entries.removeAll { now - it.value.receivedAt > 60 * 60_000L } }
    companion object {
        fun newKey(callId: String) = Key(callId, P256Crypto.b64(P256Crypto.random(32)), 0)
    }
}

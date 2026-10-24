package net.mrblindbandit.app.connect

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class PendingMessage(val id: String, val handle: String, val body: String, val conversationId: String, val created: Long)

/** Preferences that exist only on this device: pins, mutes, favourites, drafts, offline queue. */
class LocalComms(val context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("blindbandit_comms", Context.MODE_PRIVATE)

    private var secure = net.mrblindbandit.app.security.SecureLocalStore(context, "comms")
    private var boundAccount: String? = null

    fun bindAccount(accountId: String) {
        require(accountId.isNotBlank())
        if (boundAccount == accountId) return
        check(boundAccount == null) { "Use a new communications session when switching accounts" }
        val hash = net.mrblindbandit.app.security.P256Crypto.b64(net.mrblindbandit.app.security.P256Crypto.sha256(accountId.toByteArray()))
        val destination = net.mrblindbandit.app.security.SecureLocalStore(context, "comms.$hash")
        val owner = prefs.getString("legacyPrivateOwner", null)
        if (owner == null || owner == accountId) {
            // Claim legacy records only once. No other account can inherit the previous user's queue.
            check(prefs.edit().putString("legacyPrivateOwner", accountId).commit())
            val keys = (secure.names() + prefs.all.keys).filter { it == "pending" || it.startsWith("draft.") }
            for (key in keys) {
                val value = secure.get(key) ?: prefs.getString(key, null) ?: continue
                if (destination.get(key) == null) destination.put(key, value)
                secure.put(key, null)
                check(prefs.edit().remove(key).commit())
            }
        }
        secure = destination
        boundAccount = accountId
    }

    // Read legacy data once, then remove it only after durable encrypted storage succeeds.
    private fun readPrivate(key: String, fallback: String): String {
        if (boundAccount == null) return fallback
        return secure.get(key) ?: fallback
    }

    private fun set(key: String) = prefs.getStringSet(key, emptySet())!!.toSet()
    private fun toggle(key: String, value: String): Boolean {
        val now = set(key).toMutableSet()
        val on = if (value in now) { now.remove(value); false } else { now.add(value); true }
        prefs.edit().putStringSet(key, now).apply()
        return on
    }

    val pinned get() = set("pinned")
    val muted get() = set("muted")
    val markedUnread get() = set("markedUnread")
    fun togglePinned(id: String) = toggle("pinned", id)
    fun toggleMuted(id: String) = toggle("muted", id)
    fun setMarkedUnread(id: String, unread: Boolean) {
        val now = markedUnread.toMutableSet()
        if (unread) now.add(id) else now.remove(id)
        prefs.edit().putStringSet("markedUnread", now).apply()
    }

    val favorites: List<String>
        get() = prefs.getString("favorites", null)?.split('\n')?.filter { it.isNotBlank() } ?: emptyList()
    fun toggleFavorite(handle: String): Boolean {
        val h = normalizeHandle(handle)
        val list = favorites.toMutableList()
        val on = if (h in list) { list.remove(h); false } else { list.add(h); true }
        prefs.edit().putString("favorites", list.joinToString("\n")).apply()
        return on
    }

    fun draft(conversationId: String): String = readPrivate("draft.$conversationId", "")
    fun setDraft(conversationId: String, text: String) {
        check(boundAccount != null) { "Account is still loading" }
        secure.put("draft.$conversationId", text.takeIf { it.isNotEmpty() })
        prefs.edit().remove("draft.$conversationId").apply()
    }

    var lastSeenMessageIds: Map<String, String>
        get() = runCatching {
            val o = JSONObject(prefs.getString("lastSeen", "{}")!!)
            o.keys().asSequence().associateWith { o.optString(it) }
        }.getOrDefault(emptyMap())
        set(value) { prefs.edit().putString("lastSeen", JSONObject(value).toString()).apply() }

    var pending: List<PendingMessage>
        get() {
            val a = JSONArray(readPrivate("pending", "[]"))
            return (0 until a.length()).mapNotNull { i ->
                a.optJSONObject(i)?.let { PendingMessage(it.optString("id"), it.optString("handle"), it.optString("body"), it.optString("conversation_id"), it.optLong("created")) }
            }
        }
        set(value) {
            check(boundAccount != null) { "Account is still loading" }
            val a = JSONArray()
            value.forEach { a.put(JSONObject().put("id", it.id).put("handle", it.handle).put("body", it.body).put("conversation_id", it.conversationId).put("created", it.created)) }
            secure.put("pending", a.toString())
            prefs.edit().remove("pending").apply()
        }

    var appLockEnabled: Boolean
        get() = prefs.getBoolean("appLock", false)
        set(value) { prefs.edit().putBoolean("appLock", value).apply() }

    var readAloudRate: Float
        get() = prefs.getFloat("readAloudRate", 1.0f).coerceIn(0.5f, 2.0f)
        set(value) { prefs.edit().putFloat("readAloudRate", value.coerceIn(0.5f, 2.0f)).apply() }

    fun clearAll() { secure.clear(); prefs.edit().clear().apply() }
}

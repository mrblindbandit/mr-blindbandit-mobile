package net.mrblindbandit.app.security

import android.content.Context
import net.mrblindbandit.app.connect.BlindbanditApiException
import net.mrblindbandit.app.connect.ServerMessage
import net.mrblindbandit.app.connect.lBool
import net.mrblindbandit.app.connect.lString
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

/** Coordinates the existing authenticated key directory with p256-v1; never mints server credentials. */
class EncryptedMessaging internal constructor(internal val engine: E2EEEngine, private val myHandle: String,
    private val request: suspend (String, String, JSONObject?) -> JSONObject) {
    constructor(context: Context, accountId: String, myHandle: String,
        request: suspend (String, String, JSONObject?) -> JSONObject) : this(E2EEEngine(context, accountId), myHandle, request)
    internal val callKeys = CallFrameKeys()
    var ready = false; private set
    private var routesMissing = false
    private var setupError: Exception? = null
    suspend fun bootstrap() {
        try {
            if (!engine.registered) {
                request("/v1/social/keys/devices", "POST", engine.registration())
                request("/v1/social/keys/devices/${engine.deviceId}/prekeys", "POST", JSONObject().put("prekeys", engine.pendingPrekeys()))
                engine.markPrekeysUploaded(); engine.markRegistered()
            } else {
                val count = request("/v1/social/keys/devices/${engine.deviceId}/prekeys/count", "GET", null)
                if (count.optInt("count", count.optInt("value", 100)) < 20) {
                    request("/v1/social/keys/devices/${engine.deviceId}/prekeys", "POST", JSONObject().put("prekeys", engine.pendingPrekeys()))
                    engine.markPrekeysUploaded()
                }
            }
            ready = true; setupError = null; routesMissing = false
        } catch (e: kotlinx.coroutines.CancellationException) { throw e
        } catch (e: Exception) {
            ready = false; setupError = e; routesMissing = e is BlindbanditApiException && e.status == 404
        }
    }
    private suspend fun devices(handle: String): List<E2EEEngine.Bundle> {
        val h = URLEncoder.encode(handle, "UTF-8")
        val rows = request("/v1/social/keys/bundles/$h", "GET", null).optJSONArray("devices") ?: JSONArray()
        return (0 until rows.length()).map { engine.bundle(rows.getJSONObject(it), handle) }
    }
    /** Null means a legacy peer, never an encryption error. Previously encrypted chats cannot downgrade. */
    suspend fun fields(handles: List<String>, payload: JSONObject): JSONObject? {
        val peers = handles.map { it.trim().removePrefix("@").lowercase() }.distinct().filter { !it.equals(myHandle, true) }
        if (!ready) bootstrap()
        if (!ready) {
            check(routesMissing && peers.none(engine::hasEncrypted)) { "Encryption setup is unavailable. Your message has not been sent. Retry when connected." }
            return null
        }
        val recipients = mutableListOf<E2EEEngine.Bundle>()
        var legacyRecipient = false
        for (handle in peers) {
            val peer = devices(handle)
            if (peer.isEmpty()) {
                legacyRecipient = true
            }
            recipients += peer
        }
        if (legacyRecipient) {
            check(peers.none(engine::hasEncrypted)) { "An encrypted recipient cannot be downgraded because another group member has no keys. Message not sent." }
            return null
        }
        recipients += devices("me").filter { it.device != engine.deviceId }
        check(recipients.size <= 64) { "This chat has more than 64 devices. Message not sent." }
        val env = engine.encrypt(payload, recipients)
        peers.forEach(engine::markEncrypted)
        return JSONObject().put("e2ee", true).put("envelope", env).put("client_msg_id", env.getString("msg_id"))
    }
    suspend fun safetyNumber(handle: String): String {
        val mine = (devices("me").map { it.sign } + listOf(engine.signPublic)).distinctBy(P256Crypto::b64)
        val theirs = devices(handle).map { it.sign }
        require(theirs.isNotEmpty()) { "This person has no encryption keys yet." }
        return SafetyNumber.display(myHandle, mine, handle, theirs)
    }
    fun resolve(row: JSONObject): ServerMessage? {
        val message = ServerMessage.parse(row) ?: return null
        // View-once: decrypt and surface media; consumption is tracked locally after the user opens it.
        val expiresAt = net.mrblindbandit.app.connect.Lenient.timestamp(row.opt("expires_at"))
        if (expiresAt != null && expiresAt <= System.currentTimeMillis()) return null
        if (!row.lBool("e2ee")) return message
        val env = when (val value = row.opt("envelope") ?: row.opt("envelope_json")) {
            is JSONObject -> value
            is String -> runCatching { JSONObject(value) }.getOrNull()
            else -> null
        }
        return try {
            val p = engine.decrypt(env ?: error("Missing envelope"), message.senderId)
            if (p.optString("t") == "call_key") {
                callKeys.receive(p.optString("body"), message.senderId)
                return null
            }
            if (p.optString("t") in setOf("delete", "vote", "reaction", "receipt", "ai_policy", "call_key")) return null
            val sent = p.optLong("sent_at")
            val expires = p.optLong("expires_in")
            if (sent > 0 && expires > 0 && sent + expires * 1000 <= System.currentTimeMillis()) return null
            val media = p.optJSONObject("media")
            val body = if (media != null) {
                val mime = media.lString("mime")
                val name = media.lString("filename").lowercase()
                val voice = p.optString("t") == "voice" || mime.startsWith("audio/") || name.endsWith(".m4a") || name == "voice.m4a"
                val once = media.optBoolean("listen_once") || media.optBoolean("view_once")
                val head = when {
                    voice && once -> "Listen-once voice message"
                    voice -> "Voice message"
                    once -> "View-once attachment"
                    else -> "Encrypted attachment"
                }
                val dur = media.optDouble("duration", 0.0)
                val clock = if (voice && dur > 0) " (${"%d:%02d".format(dur.toInt() / 60, dur.toInt() % 60)})" else ""
                listOf(head + clock, media.lString("caption"), media.lString("alt"), media.lString("transcript")).filter { it.isNotBlank() }.joinToString("\n")
            } else p.lString("body")
            message.copy(body = body, encrypted = true, media = media)
        } catch (e: Exception) { message.copy(body = "Couldn't decrypt this message on this device.", encrypted = true, decryptFailed = true) }
    }

    fun markViewOnceOpened(context: Context, messageId: String) {
        val prefs = context.getSharedPreferences("bb_view_once", Context.MODE_PRIVATE)
        prefs.edit().putBoolean(messageId, true).apply()
    }
    fun wasViewOnceOpened(context: Context, messageId: String): Boolean =
        context.getSharedPreferences("bb_view_once", Context.MODE_PRIVATE).getBoolean(messageId, false)
}

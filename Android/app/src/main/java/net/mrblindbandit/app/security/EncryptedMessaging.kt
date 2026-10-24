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
class EncryptedMessaging(context: Context, accountId: String, private val myHandle: String,
    private val request: suspend (String, String, JSONObject?) -> JSONObject) {
    private val engine = E2EEEngine(context, accountId)
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
        if (!ready) bootstrap()
        if (!ready) {
            check(routesMissing && handles.none(engine::hasEncrypted)) { "Encryption setup is unavailable. Your message has not been sent. Retry when connected." }
            return null
        }
        val recipients = mutableListOf<E2EEEngine.Bundle>()
        for (handle in handles.distinct().filter { it != myHandle }) {
            val peer = devices(handle)
            if (peer.isEmpty()) {
                check(!engine.hasEncrypted(handle)) { "Previously encrypted recipient has no device keys. Message not sent." }
                return null
            }
            recipients += peer
        }
        recipients += devices("me").filter { it.device != engine.deviceId }
        check(recipients.size <= 64) { "This chat has more than 64 devices. Message not sent." }
        val env = engine.encrypt(payload, recipients)
        handles.forEach(engine::markEncrypted)
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
        if (row.lBool("view_once")) return message.copy(body = "View-once message. Opening on Android is not available yet.", encrypted = row.lBool("e2ee"))
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
            if (p.optString("t") in setOf("delete", "vote", "reaction", "receipt", "ai_policy", "call_key")) return null
            val sent = p.optLong("sent_at")
            val expires = p.optLong("expires_in")
            if (sent > 0 && expires > 0 && sent + expires * 1000 <= System.currentTimeMillis()) return null
            val media = p.optJSONObject("media")
            val body = if (media != null) listOf("Encrypted attachment", media.lString("caption"), media.lString("alt"), media.lString("transcript")).filter { it.isNotBlank() }.joinToString("\n") else p.lString("body")
            message.copy(body = body, encrypted = true, media = media)
        } catch (e: Exception) { message.copy(body = "Couldn't decrypt this message on this device.", encrypted = true, decryptFailed = true) }
    }
}

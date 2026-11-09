package net.mrblindbandit.app.connect

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.security.AttachmentCrypto
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64

internal fun decodeAttachmentKeyMaterial(value: String?): ByteArray? {
    val text = value?.trim().orEmpty()
    if (text.isEmpty()) return null
    runCatching { Base64.getDecoder().decode(text) }.getOrNull()?.takeIf { it.isNotEmpty() }?.let { return it }
    val padded = text.replace('-', '+').replace('_', '/').let { it + "=".repeat((4 - it.length % 4) % 4) }
    return runCatching { Base64.getDecoder().decode(padded) }.getOrNull()?.takeIf { it.isNotEmpty() }
}

internal fun looksLikeM4A(bytes: ByteArray): Boolean =
    bytes.size >= 8 && bytes.copyOfRange(4, 8).contentEquals("ftyp".toByteArray())

/** Signed object URLs do not receive the Clerk JWT. No redirects or cleartext transfers. */
private suspend fun objectTransfer(url: String, upload: ByteArray? = null): ByteArray = withContext(Dispatchers.IO) {
    val target = URL(url)
    require(target.protocol == "https" && target.userInfo == null) { "Invalid attachment URL" }
    val conn = (target.openConnection() as HttpURLConnection).apply {
        connectTimeout = 15_000; readTimeout = 30_000; instanceFollowRedirects = false
        if (upload != null) { requestMethod = "PUT"; doOutput = true; setFixedLengthStreamingMode(upload.size); setRequestProperty("Content-Type", "application/octet-stream") }
    }
    try {
        upload?.let { bytes -> conn.outputStream.use { it.write(bytes) } }
        check(conn.responseCode in 200..299) { "Attachment transfer failed (${conn.responseCode})" }
        if (upload != null) byteArrayOf() else conn.inputStream.use { readLimited(it, AttachmentCrypto.MAX_SIZE + 1024 * 1024) }
    } finally { conn.disconnect() }
}
internal fun readLimited(input: java.io.InputStream, limit: Int): ByteArray {
    val output = ByteArrayOutputStream(); val buffer = ByteArray(8192)
    while (true) { val n = input.read(buffer); if (n < 0) break; require(output.size() + n <= limit) { "Attachment exceeds the size limit" }; output.write(buffer, 0, n) }
    return output.toByteArray()
}

suspend fun ProductionCommunicationsService.sendAttachment(chatId: String, handles: List<String>, group: Boolean,
    bytes: ByteArray, mime: String, filename: String, duration: Double? = null, listenOnce: Boolean = false) {
    val engine = encryption ?: error("Wait for your account to load")
    check(bytes.isNotEmpty() && bytes.size <= AttachmentCrypto.MAX_SIZE) { "Choose a file between 1 byte and 20 MB" }
    val sealed = withContext(Dispatchers.Default) { AttachmentCrypto.seal(bytes) }
    val slot = request("/v1/social/attachments", "POST", JSONObject().put("size", sealed.blob.size).put("chat_type", if (group) "group" else "dm").put("chat_id", chatId))
    val media = JSONObject().put("attachment_id", slot.getString("attachment_id"))
        .put("key", Base64.getEncoder().encodeToString(sealed.key)).put("nonce", Base64.getEncoder().encodeToString(sealed.nonce))
        .put("sha256", Base64.getEncoder().encodeToString(sealed.digest)).put("size", sealed.size).put("mime", mime.take(100)).put("filename", filename.take(120))
    duration?.let { media.put("duration", it) }
    if (listenOnce) media.put("listen_once", true)
    val payload = JSONObject().put("t", if (duration != null) "voice" else "file").put("media", media).put("sent_at", System.currentTimeMillis())
    val recipients = if (group) {
        val members = groupDetail(chatId).optJSONArray("members") ?: error("Group membership unavailable. File not sent.")
        (0 until members.length()).map { members.getJSONObject(it).lString("handle") }.filter { it.isNotBlank() }
    } else handles
    check(recipients.isNotEmpty()) { "Recipients unavailable. File not sent." }
    val fields = engine.fields(recipients, payload) ?: error("Encrypted attachments require recipient device keys. File not sent.")
    fields.put("attachment_ids", org.json.JSONArray().put(slot.getString("attachment_id")))
    fields.put("kind", if (duration != null) "voice" else "file")
    objectTransfer(slot.getJSONObject("upload").getString("url"), sealed.blob)
    val path = if (group) "/v1/social/groups/${enc(chatId)}/messages" else "/v1/social/messages"
    if (!group) fields.put("handle", handles.first())
    request(path, "POST", fields)
    if (!group && openConversationId == chatId) reloadThread(chatId)
}
suspend fun ProductionCommunicationsService.downloadAttachment(media: JSONObject): ByteArray {
    val id = media.getString("attachment_id")
    val response = request("/v1/social/attachments/${enc(id)}")
    val blob = objectTransfer(response.lString("url", "download_url"))
    if (looksLikeM4A(blob)) return blob
    val key = sequenceOf("key", "attachment_key", "encryption_key", "wrapped_key")
        .mapNotNull { decodeAttachmentKeyMaterial(media.optString(it, null)) }.firstOrNull()
        ?: error("Attachment key missing")
    val nonce = sequenceOf("nonce", "base_nonce", "iv")
        .mapNotNull { decodeAttachmentKeyMaterial(media.optString(it, null)) }.firstOrNull()
        ?: error("Attachment nonce missing")
    val digest = decodeAttachmentKeyMaterial(media.optString("sha256", null))
        ?: error("Attachment digest missing")
    return withContext(Dispatchers.Default) {
        AttachmentCrypto.open(blob, key, nonce, media.getInt("size"), digest)
    }
}

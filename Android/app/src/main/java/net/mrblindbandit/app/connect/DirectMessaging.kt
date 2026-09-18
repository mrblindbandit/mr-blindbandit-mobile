package net.mrblindbandit.app.connect

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

enum class MessageReceipt { SENDING, SENT, DELIVERED, READ }
enum class DMKind { TEXT, ATTACHMENT, VOICE_NOTE, SYSTEM }

data class DMMessage(
    val id: String = UUID.randomUUID().toString(),
    val threadId: String,
    val senderId: String,
    val senderName: String,
    val body: String,
    val sentAt: Long = System.currentTimeMillis(),
    val isLocal: Boolean,
    val kind: DMKind = DMKind.TEXT,
    var receipt: MessageReceipt = MessageReceipt.SENT,
    val localFilePath: String? = null,
    val attachmentMime: String? = null,
    val attachmentName: String? = null
)

data class DMThread(
    val id: String,
    val peerId: String,
    val peerName: String,
    var updatedAt: Long = System.currentTimeMillis(),
    val messages: MutableList<DMMessage> = mutableListOf()
) {
    val preview: String
        get() {
            val last = messages.lastOrNull { it.kind != DMKind.SYSTEM } ?: return "No messages yet"
            return when (last.kind) {
                DMKind.VOICE_NOTE -> "🎙 Voice note"
                DMKind.ATTACHMENT -> "📎 ${last.attachmentName ?: "Attachment"}"
                else -> last.body
            }
        }
}

class DMThreadStore(context: Context) {
    private val prefs = context.getSharedPreferences("connect_dm_threads_v1", Context.MODE_PRIVATE)
    private val attachmentsDir = File(context.filesDir, "dm-attachments").also { it.mkdirs() }
    var threads: MutableList<DMThread> = mutableListOf()
        private set

    init {
        load()
        if (threads.isEmpty()) seedDemo()
    }

    fun attachmentsDirectory(): File = attachmentsDir

    fun load() {
        val raw = prefs.getString("threads_json", null) ?: run {
            threads = mutableListOf()
            return
        }
        try {
            val arr = JSONArray(raw)
            val list = mutableListOf<DMThread>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val msgs = mutableListOf<DMMessage>()
                val mArr = o.optJSONArray("messages") ?: JSONArray()
                for (j in 0 until mArr.length()) {
                    val m = mArr.getJSONObject(j)
                    msgs.add(
                        DMMessage(
                            id = m.getString("id"),
                            threadId = m.getString("threadId"),
                            senderId = m.getString("senderId"),
                            senderName = m.getString("senderName"),
                            body = m.getString("body"),
                            sentAt = m.optLong("sentAt", System.currentTimeMillis()),
                            isLocal = m.optBoolean("isLocal", false),
                            kind = runCatching { DMKind.valueOf(m.optString("kind", "TEXT")) }.getOrDefault(DMKind.TEXT),
                            receipt = runCatching { MessageReceipt.valueOf(m.optString("receipt", "SENT")) }.getOrDefault(MessageReceipt.SENT),
                            localFilePath = m.optString("localFilePath", null),
                            attachmentMime = m.optString("attachmentMime", null),
                            attachmentName = m.optString("attachmentName", null)
                        )
                    )
                }
                list.add(
                    DMThread(
                        id = o.getString("id"),
                        peerId = o.getString("peerId"),
                        peerName = o.getString("peerName"),
                        updatedAt = o.optLong("updatedAt", System.currentTimeMillis()),
                        messages = msgs
                    )
                )
            }
            threads = list.sortedByDescending { it.updatedAt }.toMutableList()
        } catch (_: Exception) {
            threads = mutableListOf()
        }
    }

    fun persist() {
        threads.sortByDescending { it.updatedAt }
        val arr = JSONArray()
        threads.forEach { th ->
            val o = JSONObject()
            o.put("id", th.id)
            o.put("peerId", th.peerId)
            o.put("peerName", th.peerName)
            o.put("updatedAt", th.updatedAt)
            val mArr = JSONArray()
            th.messages.forEach { m ->
                mArr.put(
                    JSONObject()
                        .put("id", m.id)
                        .put("threadId", m.threadId)
                        .put("senderId", m.senderId)
                        .put("senderName", m.senderName)
                        .put("body", m.body)
                        .put("sentAt", m.sentAt)
                        .put("isLocal", m.isLocal)
                        .put("kind", m.kind.name)
                        .put("receipt", m.receipt.name)
                        .put("localFilePath", m.localFilePath)
                        .put("attachmentMime", m.attachmentMime)
                        .put("attachmentName", m.attachmentName)
                )
            }
            o.put("messages", mArr)
            arr.put(o)
        }
        prefs.edit().putString("threads_json", arr.toString()).apply()
    }

    fun thread(id: String): DMThread? = threads.find { it.id == id }

    fun ensureThread(peerId: String, peerName: String): DMThread {
        threads.find { it.peerId == peerId || it.id == threadId(peerId) }?.let { return it }
        val t = DMThread(id = threadId(peerId), peerId = peerId, peerName = peerName)
        threads.add(0, t)
        persist()
        return t
    }

    fun appendMessage(message: DMMessage, peerId: String, peerName: String) {
        val t = ensureThread(peerId, peerName)
        if (t.messages.any { it.id == message.id }) return
        t.messages.add(message)
        t.updatedAt = message.sentAt
        if (!message.isLocal && peerName != t.peerName) {
            // peerName is val — recreate not needed for demo; keep as-is
        }
        persist()
    }

    fun updateReceipt(threadId: String, messageId: String, receipt: MessageReceipt) {
        val t = thread(threadId) ?: return
        val idx = t.messages.indexOfFirst { it.id == messageId }
        if (idx < 0) return
        val order = listOf(MessageReceipt.SENDING, MessageReceipt.SENT, MessageReceipt.DELIVERED, MessageReceipt.READ)
        val cur = t.messages[idx].receipt
        if (order.indexOf(receipt) < order.indexOf(cur)) return
        t.messages[idx] = t.messages[idx].copy(receipt = receipt)
        persist()
    }

    private fun seedDemo() {
        val id = threadId("studio")
        threads = mutableListOf(
            DMThread(
                id = id,
                peerId = "studio",
                peerName = "Studio",
                messages = mutableListOf(
                    DMMessage(
                        threadId = id,
                        senderId = "studio",
                        senderName = "Studio",
                        body = "TEST SCAFFOLD — DMs use LiveKit data packets. Tokens are temporary.",
                        isLocal = false,
                        receipt = MessageReceipt.READ
                    )
                )
            )
        )
        persist()
    }

    companion object {
        fun threadId(peerId: String): String {
            val pair = listOf("local", peerId).sorted().joinToString(":")
            return "dm-$pair"
        }
    }
}

package net.mrblindbandit.app.connect

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Local-first inbox/thread cache for faster cold start and chat open (Android win vs network-first).
 * Ciphertext/envelopes only — never stores decrypted plaintext.
 */
class ConversationCache(context: Context) {
    private val dir = File(context.applicationContext.filesDir, "chat-cache").also { it.mkdirs() }

    fun saveInbox(json: JSONObject) {
        atomicWrite(File(dir, "inbox.json"), json.toString())
    }

    fun loadInbox(): JSONObject? = readJson(File(dir, "inbox.json"))

    fun saveThread(conversationId: String, json: JSONObject) {
        val safe = conversationId.replace(Regex("[^A-Za-z0-9._-]"), "_").take(120)
        atomicWrite(File(dir, "thread-$safe.json"), json.toString())
    }

    fun loadThread(conversationId: String): JSONObject? {
        val safe = conversationId.replace(Regex("[^A-Za-z0-9._-]"), "_").take(120)
        return readJson(File(dir, "thread-$safe.json"))
    }

    fun clear() {
        dir.listFiles()?.forEach { it.delete() }
    }

    private fun atomicWrite(file: File, text: String) {
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) {
            file.writeText(text)
            tmp.delete()
        }
    }

    private fun readJson(file: File): JSONObject? = runCatching {
        if (!file.exists()) return null
        JSONObject(file.readText())
    }.getOrNull()
}

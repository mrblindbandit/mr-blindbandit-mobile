package net.mrblindbandit.app.social

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * Local-first cache for BanditBites feed, newsfeed, and profiles.
 * Speeds cold open and offline read of last-known public social data.
 */
class SocialCache(context: Context) {
    private val dir = File(context.applicationContext.filesDir, "social-cache").also { it.mkdirs() }

    fun saveBites(json: JSONObject) = atomicWrite(File(dir, "bites.json"), json.toString())
    fun loadBites(): JSONObject? = readJson(File(dir, "bites.json"))

    fun saveNewsfeed(json: JSONObject) = atomicWrite(File(dir, "newsfeed.json"), json.toString())
    fun loadNewsfeed(): JSONObject? = readJson(File(dir, "newsfeed.json"))

    fun saveProfile(handle: String, json: JSONObject) {
        atomicWrite(File(dir, "profile-${safe(handle)}.json"), json.toString())
    }
    fun loadProfile(handle: String): JSONObject? = readJson(File(dir, "profile-${safe(handle)}.json"))

    fun saveFollowers(handle: String, json: JSONObject) {
        atomicWrite(File(dir, "followers-${safe(handle)}.json"), json.toString())
    }
    fun loadFollowers(handle: String): JSONObject? = readJson(File(dir, "followers-${safe(handle)}.json"))

    fun saveFollowing(handle: String, json: JSONObject) {
        atomicWrite(File(dir, "following-${safe(handle)}.json"), json.toString())
    }
    fun loadFollowing(handle: String): JSONObject? = readJson(File(dir, "following-${safe(handle)}.json"))

    fun clear() { dir.listFiles()?.forEach { it.delete() } }

    private fun safe(handle: String) = handle.lowercase().replace(Regex("[^a-z0-9._-]"), "_").take(80)

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

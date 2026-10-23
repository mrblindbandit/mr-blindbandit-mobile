package net.mrblindbandit.app.connect

import org.json.JSONArray
import org.json.JSONObject

/**
 * Lenient JSON reading for the Blindbandit social API. The server sometimes sends booleans as
 * 0/1, "0"/"1", "true"/"false", "yes"/"no", numbers as strings, and timestamps in seconds or
 * milliseconds. One bad field must never make a whole list fail to load.
 */
object Lenient {
    fun bool(value: Any?): Boolean? = when (value) {
        null, JSONObject.NULL -> null
        is Boolean -> value
        is Number -> value.toDouble() != 0.0
        is String -> when (value.trim().lowercase()) {
            "1", "true", "yes", "y", "on", "t" -> true
            "0", "false", "no", "n", "off", "f", "" -> false
            else -> value.trim().toDoubleOrNull()?.let { it != 0.0 }
        }
        else -> null
    }

    fun long(value: Any?): Long? = when (value) {
        null, JSONObject.NULL -> null
        is Number -> value.toLong()
        is String -> value.trim().toLongOrNull() ?: value.trim().toDoubleOrNull()?.toLong()
            ?: runCatching { java.time.Instant.parse(value.trim()).toEpochMilli() }.getOrNull()
        is Boolean -> if (value) 1 else 0
        else -> null
    }

    /** Milliseconds since the epoch; values that look like seconds are scaled up. */
    fun timestamp(value: Any?): Long? = long(value)?.let { if (it in 1..99_999_999_999L) it * 1000 else it }

    fun string(value: Any?): String? = when (value) {
        null, JSONObject.NULL -> null
        is String -> value
        is Number, is Boolean -> value.toString()
        else -> null
    }
}

fun JSONObject.lBool(vararg keys: String, default: Boolean = false): Boolean =
    keys.firstNotNullOfOrNull { Lenient.bool(opt(it)) } ?: default

fun JSONObject.lLong(vararg keys: String): Long? = keys.firstNotNullOfOrNull { Lenient.long(opt(it)) }

fun JSONObject.lTime(vararg keys: String): Long? = keys.firstNotNullOfOrNull { Lenient.timestamp(opt(it)) }

fun JSONObject.lString(vararg keys: String): String =
    keys.firstNotNullOfOrNull { Lenient.string(opt(it))?.takeIf { s -> s.isNotBlank() } }.orEmpty()

fun JSONObject.items(): List<JSONObject> {
    val array = optJSONArray("items") ?: optJSONArray("conversations") ?: optJSONArray("messages")
        ?: optJSONArray("calls") ?: optJSONArray("notifications") ?: optJSONArray("blocks") ?: JSONArray()
    return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
}

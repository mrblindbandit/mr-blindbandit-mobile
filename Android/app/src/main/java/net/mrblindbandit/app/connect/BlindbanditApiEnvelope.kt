package net.mrblindbandit.app.connect

import org.json.JSONArray
import org.json.JSONObject

/**
 * The Blindbandit Platform API wraps every response as
 * `{ "success": true, "data": ..., "meta": {...} }` and errors as
 * `{ "success": false, "error": { "code", "message" } }`.
 */
object BlindbanditApiEnvelope {
    fun unwrap(status: Int, body: String): JSONObject {
        val json = if (body.isBlank()) JSONObject() else runCatching { JSONObject(body) }.getOrElse { JSONObject() }
        if (status !in 200..299 || json.optBoolean("success", true) == false) {
            val message = json.optJSONObject("error")?.optString("message").orEmpty()
                .ifBlank { "The Blindbandit service returned HTTP $status." }
            throw BlindbanditApiException(status, json.optJSONObject("error")?.optString("code").orEmpty(), message)
        }
        return when (val data = json.opt("data")) {
            is JSONObject -> data
            is JSONArray -> JSONObject().put("items", data)
            null, JSONObject.NULL -> json
            else -> JSONObject().put("value", data)
        }
    }
}

class BlindbanditApiException(val status: Int, val code: String, message: String) : Exception(message)

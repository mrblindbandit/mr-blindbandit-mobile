package net.mrblindbandit.app.connect

/** FCM data-only contract; never log payload values or decrypted contents. */
data class PushPayload(val type: String, val callId: String?, val conversationId: String?, val groupId: String?, val link: String?) {
    val endsCall get() = type in setOf("call_end", "call_ended", "call_cancelled", "call_canceled", "call_declined", "call_answered_elsewhere")
    val isCall get() = type.startsWith("call") || callId != null || CommsDestination.parse(link) is CommsDestination.Call
    val key get() = if (isCall) "call:${callId ?: link.orEmpty()}" else groupId?.let { "group:$it" } ?: "dm:${conversationId ?: link.orEmpty()}"
    companion object {
        fun parse(data: Map<String, String>) = PushPayload(
            (data["type"] ?: data["category"] ?: data["kind"]).orEmpty().lowercase(),
            (data["call_id"] ?: data["callId"])?.takeIf { it.isNotBlank() },
            (data["conversation_id"] ?: data["conversationId"])?.takeIf { it.isNotBlank() },
            (data["group_id"] ?: data["groupId"])?.takeIf { it.isNotBlank() },
            data["deep_link"] ?: data["url"] ?: data["link"],
        )
    }
}


/** Prevents encrypted envelopes and call-frame keys from leaking into OS notification previews. */
internal object PushPreviewSanitizer {
    private fun looksLikeJsonObject(text: String) = text.trimStart().startsWith("{")
    private fun hasField(text: String, field: String) =
        Regex("\\\"${Regex.escape(field)}\\\"\\s*:", RegexOption.IGNORE_CASE).containsMatchIn(text)

    fun isCallControl(text: String): Boolean =
        looksLikeJsonObject(text) && hasField(text, "call_id") && hasField(text, "index") &&
            (hasField(text, "key") || hasField(text, "nonce"))

    fun containsSensitiveJson(text: String): Boolean {
        if (!looksLikeJsonObject(text)) return false
        return listOf("key", "nonce", "ciphertext", "wrapped", "wrapped_key", "keys",
            "attachment_key", "encryption_key", "base_nonce", "iv").any { hasField(text, it) }
    }

    fun visibleBody(raw: String, isCall: Boolean, hidePreview: Boolean, caller: String): String = when {
        isCall -> "$caller is calling"
        hidePreview || containsSensitiveJson(raw) -> "New message"
        else -> raw
    }
}

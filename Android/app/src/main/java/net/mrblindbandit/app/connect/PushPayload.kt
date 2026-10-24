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

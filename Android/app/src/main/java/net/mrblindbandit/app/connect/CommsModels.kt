package net.mrblindbandit.app.connect

import org.json.JSONObject

data class ServerConversation(
    val id: String,
    val peerHandle: String,
    val peerName: String,
    val lastBody: String,
    val lastSenderId: String = "",
    val lastCreatedAt: Long,
    val verified: Boolean,
    val unreadCount: Int = 0,
) {
    companion object {
        fun parse(row: JSONObject): ServerConversation? {
            val id = row.lString("id", "conversation_id").ifBlank { return null }
            val other = row.optJSONObject("other") ?: row.optJSONObject("peer") ?: JSONObject()
            val last = row.optJSONObject("last_message") ?: JSONObject()
            val handle = other.lString("handle", "username")
            return ServerConversation(
                id = id,
                peerHandle = handle,
                peerName = other.lString("display_name", "name").ifBlank { handle.ifBlank { "Blindbandit user" } },
                lastBody = last.lString("body", "text"),
                lastSenderId = last.lString("sender_id"),
                lastCreatedAt = last.lTime("created_at") ?: row.lTime("updated_at") ?: 0L,
                verified = other.lBool("verified", "is_verified"),
                unreadCount = (row.lLong("unread_count", "unread") ?: 0L).toInt().coerceAtLeast(0),
            )
        }
    }
}

enum class Receipt(val label: String) { SENDING("Sending"), SENT("Sent"), DELIVERED("Delivered"), READ("Read") }

data class ServerMessage(
    val id: String,
    val senderId: String,
    val body: String,
    val createdAt: Long,
    val deliveredAt: Long? = null,
    val readAt: Long? = null,
    val replyToBody: String = "",
    val pending: Boolean = false,
) {
    val receipt: Receipt
        get() = when {
            pending -> Receipt.SENDING
            readAt != null -> Receipt.READ
            deliveredAt != null -> Receipt.DELIVERED
            else -> Receipt.SENT
        }

    companion object {
        fun parse(row: JSONObject): ServerMessage? {
            val id = row.lString("id").ifBlank { return null }
            return ServerMessage(
                id = id,
                senderId = row.lString("sender_id"),
                body = row.lString("body", "text"),
                createdAt = row.lTime("created_at") ?: 0L,
                deliveredAt = row.lTime("delivered_at"),
                readAt = row.lTime("read_at"),
            )
        }
    }
}

data class CallRecord(
    val id: String,
    val kind: String,
    val status: String,
    val createdAt: Long,
    val endedAt: Long?,
    val direction: String,
    val peerHandle: String,
    val peerName: String,
) {
    val isVideo get() = kind == "video"
    val isIncoming get() = direction == "incoming"
    val durationSeconds: Int? get() = endedAt?.takeIf { it > createdAt }?.let { ((it - createdAt) / 1000).toInt() }

    /** Same rules as iOS: a call still "ringing" a minute later was never answered. */
    fun stateLabel(now: Long = System.currentTimeMillis()): String {
        val stale = now - createdAt > 60_000
        return when (status) {
            "ringing" -> if (stale) (if (isIncoming) "Missed" else "Not answered") else (if (isIncoming) "Ringing" else "Calling")
            "active" -> "In progress"
            "missed" -> if (isIncoming) "Missed" else "Not answered"
            "declined" -> "Declined"
            "cancelled", "canceled" -> "Cancelled"
            "ended" -> if ((durationSeconds ?: 0) > 0) (if (isIncoming) "Incoming" else "Outgoing") else (if (isIncoming) "Missed" else "Not answered")
            else -> status.replaceFirstChar { it.uppercase() }
        }
    }

    val isMissed get() = isIncoming && stateLabel() == "Missed"

    companion object {
        fun parse(row: JSONObject): CallRecord? {
            val id = row.lString("id").ifBlank { return null }
            val other = row.optJSONObject("other") ?: JSONObject()
            val handle = other.lString("handle")
            return CallRecord(
                id = id,
                kind = row.lString("kind").ifBlank { "voice" },
                status = row.lString("status").lowercase(),
                createdAt = row.lTime("created_at") ?: 0L,
                endedAt = row.lTime("ended_at"),
                direction = row.lString("direction").lowercase(),
                peerHandle = handle,
                peerName = other.lString("display_name").ifBlank { handle.ifBlank { "Blindbandit user" } },
            )
        }
    }
}

data class BlockedProfile(val handle: String, val displayName: String) {
    companion object {
        fun parse(row: JSONObject): BlockedProfile? {
            val handle = row.lString("handle", "blocked_handle").ifBlank { row.optJSONObject("profile")?.lString("handle").orEmpty() }
            if (handle.isBlank()) return null
            return BlockedProfile(handle, row.lString("display_name").ifBlank { handle })
        }
    }
}

data class SocialNotification(
    val id: String,
    val title: String,
    val detail: String,
    val createdAt: Long,
    val isRead: Boolean,
    val link: String,
) {
    companion object {
        fun parse(row: JSONObject): SocialNotification {
            val type = row.lString("type")
            return SocialNotification(
                id = row.lString("id").ifBlank { java.util.UUID.randomUUID().toString() },
                title = row.lString("title").ifBlank { if (type.isBlank()) "Notification" else type.replace('_', ' ').replaceFirstChar { it.uppercase() } },
                detail = row.lString("body", "message"),
                createdAt = row.lTime("created_at") ?: 0L,
                isRead = row.lTime("read_at") != null || row.lBool("read", "is_read"),
                link = row.lString("deep_link", "url", "link"),
            )
        }
    }
}

/** Where a notification or push should take the user inside the app. */
sealed interface CommsDestination {
    data class Thread(val conversationId: String) : CommsDestination
    data class Call(val callId: String) : CommsDestination
    data object Calls : CommsDestination
    data object Messages : CommsDestination

    companion object {
        private val thread = Regex("/(?:messages|conversations|inbox)/([A-Za-z0-9_\\-:.]+)")
        private val call = Regex("/calls/([A-Za-z0-9_\\-:.]+)")

        fun parse(link: String?, conversationId: String? = null, callId: String? = null): CommsDestination? {
            if (!conversationId.isNullOrBlank()) return Thread(conversationId)
            if (!callId.isNullOrBlank()) return Call(callId)
            val path = link?.substringBefore('?')?.substringBefore('#') ?: return null
            call.find(path)?.let { m -> m.groupValues[1].takeIf { it != "history" }?.let { return Call(it) } }
            thread.find(path)?.let { m -> m.groupValues[1].takeIf { it != "unread-count" }?.let { return Thread(it) } }
            return when {
                path.contains("/calls") -> Calls
                path.contains("/messages") || path.contains("/inbox") -> Messages
                else -> null
            }
        }
    }
}

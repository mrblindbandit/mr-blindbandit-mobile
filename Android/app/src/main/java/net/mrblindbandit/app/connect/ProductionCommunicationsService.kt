package net.mrblindbandit.app.connect

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.livekit.android.RoomOptions
import io.livekit.android.e2ee.BaseKeyProvider
import io.livekit.android.e2ee.E2EEOptions
import net.mrblindbandit.app.security.CallFrameKeys
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.config.AppConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID

/** Load state for any list screen. Every load ends in Loaded or Failed, never an endless spinner. */
sealed interface LoadState {
    data object Idle : LoadState
    data object Loading : LoadState
    data object Loaded : LoadState
    data class Failed(val message: String) : LoadState
}

/**
 * Production communications client. Clerk session JWTs authenticate every request to the
 * Blindbandit `/v1/social` API. LiveKit room tokens are minted server-side per call.
 */
class ProductionCommunicationsService(
    private val context: Context,
    private val auth: ClerkAuthService,
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    internal var encryption: net.mrblindbandit.app.security.EncryptedMessaging? = null
    var encryptionStatus by mutableStateOf("Encryption not initialized"); private set
    val local = LocalComms(appContext)
    private val conversationCache = ConversationCache(appContext)
    private val callSounds = CallSounds(appContext)
    /** Exposed for Dialer keypad tones. */
    val callSoundsPublic: CallSounds get() = callSounds
    val callNumbers = CallNumberDirectory(appContext)

    var openGroupId by mutableStateOf<String?>(null)
    val conversations = mutableStateListOf<ServerConversation>()
    val messages = mutableStateListOf<ServerMessage>()
    val pendingMessages = mutableStateListOf<PendingMessage>().apply { addAll(local.pending) }
    val callHistory = mutableStateListOf<CallRecord>()
    val blocked = mutableStateListOf<BlockedProfile>()
    val notifications = mutableStateListOf<SocialNotification>()

    var myProfileId by mutableStateOf(""); private set
    var myHandle by mutableStateOf(""); private set
    var statusMessage by mutableStateOf("")
    var conversationsState by mutableStateOf<LoadState>(LoadState.Idle); private set
    var threadState by mutableStateOf<LoadState>(LoadState.Idle); private set
    var historyState by mutableStateOf<LoadState>(LoadState.Idle); private set
    var blockedState by mutableStateOf<LoadState>(LoadState.Idle); private set
    var notificationsState by mutableStateOf<LoadState>(LoadState.Idle); private set
    var serverUnreadCount by mutableIntStateOf(0); private set
    var otherTyping by mutableStateOf(false); private set
    var openConversationId by mutableStateOf<String?>(null); private set
    var shareReadReceipts by mutableStateOf(true); private set
    var settingsLoaded by mutableStateOf(false); private set
    var markedUnread by mutableStateOf(local.markedUnread); private set
    var pinned by mutableStateOf(local.pinned); private set
    var muted by mutableStateOf(local.muted); private set
    var favorites by mutableStateOf(local.favorites); private set

    // Calls
    var isInCall by mutableStateOf(false); private set
    var isRinging by mutableStateOf(false); private set
    var isVideoCall by mutableStateOf(false); private set
    var micEnabled by mutableStateOf(true); private set
    var cameraEnabled by mutableStateOf(false); private set
    var speakerOn by mutableStateOf(false); private set
    var callSeconds by mutableIntStateOf(0); private set
    var activeCallId by mutableStateOf<String?>(null); private set
    var callPeerName by mutableStateOf(""); private set
    var callPeerHandle by mutableStateOf(""); private set
    var incomingCallId by mutableStateOf<String?>(null)
    /** Call IDs this device just answered/joined — ignore late "answered elsewhere" echo for ~8s (iOS 2.0.9 parity). */
    private val joinedAt = java.util.concurrent.ConcurrentHashMap<String, Long>()
    @Volatile private var joiningCallId: String? = null
    var myAvatarUrl by mutableStateOf(""); private set
    var myDisplayName by mutableStateOf(""); private set
    var callEncryptionLabel by mutableStateOf("Media encrypted in transit"); private set
    private var callKeyProvider: BaseKeyProvider? = null

    var room by mutableStateOf<Room?>(null); private set
    private var agoraSession: AgoraCallSession? = null
    var activeRtcProvider by mutableStateOf("livekit"); private set
    private var lastTypingSent = 0L

    /** Mirrors the "Start video calls with camera off" setting. */
    var startWithCameraOff: Boolean = false
    var speakerByDefault: Boolean = false
    var preferBluetoothHeadset: Boolean = true

    val callTimeLabel: String get() = "%02d:%02d".format(callSeconds / 60, callSeconds % 60)

    /** Unread conversations: the server's unread_count, plus threads the user marked unread here. */
    fun isUnread(c: ServerConversation) = c.id in markedUnread || (c.unreadCount > 0 && c.id != openConversationId)

    val unreadBadge: Int
        get() {
            val listed = conversations.count { isUnread(it) && it.id !in muted }
            return if (conversations.isEmpty()) maxOf(serverUnreadCount, markedUnread.size) else listed
        }

    suspend fun bootstrap() {
        try {
            val me = request("/v1/social/me")
            myProfileId = me.lString("id")
            myHandle = me.lString("handle")
            myDisplayName = me.lString("display_name")
            myAvatarUrl = me.lString("avatar_url")
            if (myProfileId.isNotBlank()) {
                local.bindAccount(myProfileId)
                pendingMessages.clear(); pendingMessages.addAll(local.pending)
                encryption = net.mrblindbandit.app.security.EncryptedMessaging(appContext, myProfileId, myHandle) { p, m, b -> request(p, m, b) }
                encryption?.bootstrap()
                encryptionStatus = if (encryption?.ready == true) "Encryption keys ready" else "Encryption setup unavailable"
            }
        } catch (e: Exception) {
            statusMessage = friendly(e, "Could not connect to Blindbandit communications.")
        }
        refreshConversations()
        loadSettings()
        flushPendingMessages()
        warmCallPath()
    }

    suspend fun refreshUnreadCount() {
        try {
            val r = request("/v1/social/messages/unread-count")
            serverUnreadCount = (r.lLong("unread_count", "count", "unread", "value") ?: 0L).toInt().coerceAtLeast(0)
        } catch (_: Exception) { }
    }

    suspend fun refreshConversations(): Boolean {
        if (conversations.isEmpty()) {
            conversationsState = LoadState.Loading
            // Local-first: paint cached inbox immediately for faster cold start.
            conversationCache.loadInbox()?.let { cached ->
                val fromCache = cached.items().mapNotNull { runCatching { ServerConversation.parse(it) }.getOrNull() }
                if (fromCache.isNotEmpty() && conversations.isEmpty()) {
                    conversations.addAll(fromCache)
                    conversationsState = LoadState.Loaded
                }
            }
        }
        return try {
            // Prefer slim inbox (Sites native-speed). Fall back to classic list on 404.
            val raw = try {
                request("/v1/social/inbox?limit=100", connectMs = 8_000, readMs = 12_000)
            } catch (e: BlindbanditApiException) {
                if (e.status == 404) request("/v1/social/messages?limit=100", connectMs = 10_000, readMs = 20_000)
                else throw e
            }
            conversationCache.saveInbox(raw)
            val parsed = raw.items().mapNotNull { runCatching { ServerConversation.parse(it) }.getOrNull() }
            announceNewIncoming(parsed)
            conversations.clear()
            conversations.addAll(parsed)
            conversationsState = LoadState.Loaded
            refreshUnreadCount()
            prefetchThreads()
            true
        } catch (e: Exception) {
            if (conversations.isEmpty()) conversationsState = LoadState.Failed(friendly(e, "Could not load your conversations."))
            else statusMessage = friendly(e, "Could not refresh conversations.")
            false
        }
    }

    private var prefetched = false
    /** Prefetch top chats via native-speed hydrate (one round-trip) with classic fallback. */
    private fun prefetchThreads() {
        if (prefetched) return
        prefetched = true
        val ids = conversations.take(8).map { it.id }
        scope.launch {
            hydrateThreads(ids, limitPer = 40)
            for (id in ids) {
                if (conversationCache.loadThread(id) == null) {
                    runCatching {
                        val result = request("/v1/social/messages/${enc(id)}?limit=40", connectMs = 8_000, readMs = 15_000)
                        conversationCache.saveThread(id, result)
                    }
                }
            }
        }
    }

    /** Prefetch many threads in one round-trip (native-speed). */
    suspend fun hydrateThreads(ids: List<String>, limitPer: Int = 30) {
        val slice = ids.take(20)
        if (slice.isEmpty()) return
        val body = JSONObject()
            .put("conversation_ids", JSONArray(slice))
            .put("limit_per", limitPer)
        val raw = runCatching {
            request("/v1/social/inbox/hydrate", method = "POST", body = body, connectMs = 8_000, readMs = 15_000)
        }.getOrNull() ?: return
        val threads = raw.optJSONArray("threads") ?: return
        for (i in 0 until threads.length()) {
            val thr = threads.optJSONObject(i) ?: continue
            val id = thr.lString("id")
            if (id.isBlank()) continue
            val items = thr.optJSONArray("items") ?: continue
            val wrapped = JSONObject().put("items", items)
            conversationCache.saveThread(id, wrapped)
        }
    }

    private fun announceNewIncoming(fresh: List<ServerConversation>) {
        val seen = local.lastSeenMessageIds.toMutableMap()
        val first = seen.isEmpty()
        fresh.forEach { c ->
            val key = "${c.lastCreatedAt}:${c.lastBody.hashCode()}"
            val before = seen[c.id]
            seen[c.id] = key
            if (!first && before != key && c.lastSenderId.isNotBlank() && c.lastSenderId != myProfileId && c.id != openConversationId && c.id !in muted) {
                Announcer.announce(appContext, "New message from ${c.peerName}")
            }
        }
        local.lastSeenMessageIds = seen
    }

    suspend fun openConversation(conversationId: String) {
        openConversationId = conversationId
        messages.clear()
        otherTyping = false
        threadState = LoadState.Loading
        reloadThread(conversationId)
        markRead(conversationId)
    }

    fun closeConversation() {
        openConversationId = null
        otherTyping = false
    }

    /** Reloads the open thread. Returns incoming messages that were not there before. */
    private fun parseThreadItems(result: org.json.JSONObject): List<ServerMessage> =
        result.items().mapNotNull { runCatching { encryption?.resolve(it) ?: if (!it.lBool("e2ee")) ServerMessage.parse(it) else ServerMessage.parse(it)?.copy(body = "Encrypted message unavailable on this device", encrypted = true, decryptFailed = true) }.getOrNull() }.sortedBy { it.createdAt }

    suspend fun reloadThread(conversationId: String): List<ServerMessage> = try {
        if (messages.isEmpty()) {
            conversationCache.loadThread(conversationId)?.let { cached ->
                val fromCache = parseThreadItems(cached)
                if (fromCache.isNotEmpty() && openConversationId == conversationId && messages.isEmpty()) {
                    messages.addAll(fromCache)
                    threadState = LoadState.Loaded
                }
            }
        }
        val result = request("/v1/social/messages/${enc(conversationId)}?limit=100")
        conversationCache.saveThread(conversationId, result)
        val parsed = parseThreadItems(result)
        if (openConversationId != conversationId) emptyList() else {
            val known = messages.map { it.id }.toSet()
            val hadMessages = messages.isNotEmpty()
            val incoming = parsed.filter { it.id !in known && it.senderId != myProfileId }
            val pendingLocal = messages.filter { local ->
                local.id.startsWith("local-") && parsed.none { s ->
                    (local.clientMsgId.isNotBlank() && (s.clientMsgId == local.clientMsgId || s.id == local.clientMsgId || s.id == local.id))
                        || (s.senderId == myProfileId && s.body == local.body)
                }
            }
            // Prefer client_msg_id so optimistic local- rows and the server echo share one identity.
            val merged = parsed.map { server ->
                val match = messages.firstOrNull { local ->
                    local.id.startsWith("local-") && (
                        (local.clientMsgId.isNotBlank() && (server.clientMsgId == local.clientMsgId || server.id == local.clientMsgId))
                            || (server.senderId == myProfileId && server.body == local.body)
                    )
                }
                if (match != null && server.clientMsgId.isBlank()) server.copy(clientMsgId = match.clientMsgId.ifBlank { match.id })
                else server
            }
            messages.clear()
            messages.addAll(merged + pendingLocal)
            otherTyping = result.lBool("other_typing", "typing")
            threadState = LoadState.Loaded
            if (hadMessages && incoming.isNotEmpty()) markRead(conversationId)
            if (hadMessages) incoming else emptyList()
        }
    } catch (e: Exception) {
        if (messages.isEmpty()) threadState = LoadState.Failed(friendly(e, "Could not load messages."))
        emptyList()
    }

    suspend fun markRead(conversationId: String) {
        setMarkedUnreadLocal(conversationId, false)
        try {
            request("/v1/social/messages/${enc(conversationId)}/read", method = "POST", body = JSONObject())
            val i = conversations.indexOfFirst { it.id == conversationId }
            if (i >= 0) conversations[i] = conversations[i].copy(unreadCount = 0)
            refreshUnreadCount()
        } catch (_: Exception) { }
    }

    /** Mark unread is kept on this device (the API has no unread route); the badge includes it. */
    fun markUnread(conversationId: String) {
        setMarkedUnreadLocal(conversationId, true)
        statusMessage = "Marked as unread."
    }

    private fun setMarkedUnreadLocal(id: String, unread: Boolean) {
        local.setMarkedUnread(id, unread)
        markedUnread = local.markedUnread
    }

    fun togglePinned(id: String): Boolean = local.togglePinned(id).also { pinned = local.pinned }
    fun toggleMuted(id: String): Boolean = local.toggleMuted(id).also { muted = local.muted }
    fun toggleFavorite(handle: String): Boolean = local.toggleFavorite(handle).also { favorites = local.favorites }

    /** Tells the other person we're typing. Throttled to one request every 3 seconds. */
    fun sendTyping(conversationId: String) {
        val now = System.currentTimeMillis()
        if (now - lastTypingSent < 3_000) return
        lastTypingSent = now
        scope.launch {
            try { request("/v1/social/messages/${enc(conversationId)}/typing", method = "POST", body = JSONObject().put("typing", true)) } catch (_: Exception) { }
        }
    }

    suspend fun loadSettings() {
        try {
            val s = request("/v1/social/me/settings")
            val inner = s.optJSONObject("settings") ?: s
            shareReadReceipts = inner.lBool("share_read_receipts", default = true)
            settingsLoaded = true
        } catch (_: Exception) { }
    }

    suspend fun setShareReadReceipts(on: Boolean): Boolean {
        val before = shareReadReceipts
        shareReadReceipts = on
        return try {
            val s = request("/v1/social/me/settings", method = "PATCH", body = JSONObject().put("share_read_receipts", on))
            val inner = s.optJSONObject("settings") ?: s
            if (inner.has("share_read_receipts")) shareReadReceipts = inner.lBool("share_read_receipts", default = on)
            settingsLoaded = true
            statusMessage = if (shareReadReceipts) "Read receipts on." else "Read receipts off."
            true
        } catch (e: Exception) {
            shareReadReceipts = before
            statusMessage = friendly(e, "Could not change read receipts.")
            false
        }
    }

    /** Checks that a username exists before messaging or calling it. */
    suspend fun checkHandle(raw: String): Boolean {
        val handle = normalizeHandle(raw)
        if (handle.isBlank()) return false
        return try {
            request("/v1/social/profiles/${enc(handle)}")
            true
        } catch (e: BlindbanditApiException) {
            statusMessage = if (e.status == 404) "No Blindbandit account has the username @$handle." else friendly(e, "Could not check that username.")
            false
        } catch (e: Exception) {
            // Offline: let the caller queue it.
            e !is IOException
        }
    }

    /** Sends a message. Optimistic Sent caption immediately; network runs in background (iOS TF 39). */
    suspend fun sendMessage(recipient: String, body: String, conversationId: String = ""): String? {
        val target = normalizeHandle(recipient)
        val text = body.trim().take(4000)
        if (target.isBlank() || text.isBlank()) {
            statusMessage = "Enter the person's Blindbandit username and a message."
            return null
        }
        val localId = "local-" + UUID.randomUUID().toString()
        val openId = openConversationId
        if (!openId.isNullOrBlank() && (conversationId.isBlank() || conversationId == openId)) {
            messages.add(
                ServerMessage(
                    id = localId,
                    senderId = myProfileId,
                    body = text,
                    createdAt = System.currentTimeMillis(),
                    pending = false,
                    clientMsgId = localId,
                )
            )
        }
        callSounds.messageSent()
        Announcer.announce(appContext, "Sent")
        statusMessage = "Message sent to @$target."
        val seedConv = conversationId.ifBlank { openId.orEmpty() }
        // Network off the UI path — draft already cleared by the caller.
        scope.launch {
            try {
                // Race E2EE ≤350ms so missing bundles never feel like multi-second lag.
                val e2ee = withTimeoutOrNull(350L) {
                    runCatching { messageFields(listOf(target), text) }.getOrNull()
                }
                val fields = (e2ee ?: JSONObject().put("body", text))
                    .put("handle", target)
                    .put("client_msg_id", localId)
                val response = request("/v1/social/messages", method = "POST", body = fields, connectMs = 6_000, readMs = 8_000)
                val who = response.optJSONObject("recipient")?.lString("display_name").orEmpty().ifBlank { "@$target" }
                statusMessage = if (fields.optBoolean("e2ee")) "Encrypted message sent to $who." else "Message sent to $who."
                val id = response.lString("conversation_id").ifBlank { seedConv }
                val serverMsgId = response.lString("id", "message_id")
                // Flip optimistic bubble to real server id when present.
                val idx = messages.indexOfFirst { it.id == localId }
                if (idx >= 0 && serverMsgId.isNotBlank()) {
                    if (messages.any { it.id == serverMsgId }) {
                        messages.removeAll { it.id == localId }
                    } else {
                        val cur = messages[idx]
                        messages[idx] = cur.copy(
                            id = serverMsgId,
                            createdAt = response.lTime("created_at") ?: cur.createdAt,
                            clientMsgId = localId,
                            pending = false,
                        )
                    }
                }
                if (id.isNotBlank()) {
                    runCatching { sendAck(id, localId) }
                }
                refreshConversations()
                if (id.isNotBlank() && openConversationId == id) reloadThread(id)
            } catch (e: IOException) {
                val item = PendingMessage(UUID.randomUUID().toString(), target, text, seedConv, System.currentTimeMillis())
                pendingMessages.add(item)
                local.pending = pendingMessages.toList()
                statusMessage = "You're offline. The message to @$target will send when you're back online."
                Announcer.announce(appContext, statusMessage)
            } catch (e: Exception) {
                messages.removeAll { it.id == localId }
                statusMessage = friendly(e, "Message could not be sent.")
                Announcer.announce(appContext, statusMessage)
            }
        }
        return seedConv.ifBlank { null }
    }

    /** Fast send ack by client_msg_id (native-speed) — no thread refetch required. */
    suspend fun sendAck(conversationId: String, clientMsgId: String): Boolean {
        if (conversationId.isBlank() || clientMsgId.isBlank()) return false
        return try {
            val d = request(
                "/v1/social/messages/send-ack",
                method = "POST",
                body = JSONObject().put("conversation_id", conversationId).put("client_msg_id", clientMsgId),
                connectMs = 4_000,
                readMs = 6_000,
            )
            d.lBool("acked", default = false)
        } catch (_: Exception) {
            false
        }
    }

    suspend fun resolveCallNumber(number: String): Triple<String, String, String> {
        val digits = number.filter { it.isDigit() }
        val d = request("/v1/social/call-numbers/${enc(digits)}", connectMs = 4_000, readMs = 6_000)
        val handle = d.lString("handle")
        val name = d.lString("display_name").ifBlank { handle }
        val callNumber = d.lString("call_number").ifBlank { digits }
        require(handle.isNotBlank()) { "Number not found" }
        return Triple(handle, name, callNumber)
    }

    suspend fun getMyCallNumber(): String? {
        return try {
            val d = request("/v1/social/me/call-number", connectMs = 4_000, readMs = 6_000)
            d.lString("call_number").ifBlank { null }
        } catch (_: Exception) {
            null
        }
    }

    suspend fun setMyCallNumber(number: String?): String? {
        val body = JSONObject()
        if (number.isNullOrBlank()) body.put("call_number", JSONObject.NULL)
        else body.put("call_number", number.filter { it.isDigit() })
        val d = request("/v1/social/me/call-number", method = "PUT", body = body, connectMs = 4_000, readMs = 8_000)
        return d.lString("call_number").ifBlank { null }
    }

    internal suspend fun messageFields(handles: List<String>, text: String, silent: Boolean = false): JSONObject {
        val engine = encryption ?: error("Wait for your account to finish loading before sending.")
        val payload = JSONObject().put("t", "text").put("body", text).put("sent_at", System.currentTimeMillis())
        if (silent) payload.put("silent", true)
        val fields = engine.fields(handles, payload) ?: JSONObject().put("body", text)
        if (silent) fields.put("silent", true)
        return fields
    }

    suspend fun flushPendingMessages() {
        if (myProfileId.isBlank() || encryption == null) return
        for (item in pendingMessages.toList()) {
            try {
                request("/v1/social/messages", method = "POST", body = messageFields(listOf(item.handle), item.body).put("handle", item.handle))
                pendingMessages.removeAll { it.id == item.id }
                statusMessage = "Queued message to @${item.handle} sent."
            } catch (_: IOException) {
                break
            } catch (e: Exception) {
                statusMessage = friendly(e, "A queued message could not be sent.")
            }
        }
        local.pending = pendingMessages.toList()
    }

    fun discardPending(item: PendingMessage) {
        pendingMessages.removeAll { it.id == item.id }
        local.pending = pendingMessages.toList()
    }

    // Call history, blocks, notifications

    suspend fun loadCallHistory() {
        if (callHistory.isEmpty()) historyState = LoadState.Loading
        historyState = try {
            val parsed = request("/v1/social/calls/history?limit=50").items().mapNotNull { runCatching { CallRecord.parse(it) }.getOrNull() }
            callHistory.clear(); callHistory.addAll(parsed)
            LoadState.Loaded
        } catch (e: Exception) { LoadState.Failed(friendly(e, "Could not load call history.")) }
    }

    suspend fun loadBlocked() {
        blockedState = LoadState.Loading
        blockedState = try {
            val parsed = request("/v1/social/blocks").items().mapNotNull { BlockedProfile.parse(it) }
            blocked.clear(); blocked.addAll(parsed)
            LoadState.Loaded
        } catch (e: Exception) { LoadState.Failed(friendly(e, "Could not load blocked accounts.")) }
    }

    suspend fun unblock(handle: String): Boolean = try {
        request("/v1/social/profiles/${enc(normalizeHandle(handle))}/block", method = "DELETE")
        blocked.removeAll { it.handle == handle }
        statusMessage = "Unblocked @$handle."
        true
    } catch (e: Exception) {
        statusMessage = friendly(e, "Could not unblock.")
        false
    }

    suspend fun loadNotifications() {
        if (notifications.isEmpty()) notificationsState = LoadState.Loading
        notificationsState = try {
            val parsed = request("/v1/social/notifications?limit=50").items().map { SocialNotification.parse(it) }
            notifications.clear(); notifications.addAll(parsed)
            LoadState.Loaded
        } catch (e: Exception) { LoadState.Failed(friendly(e, "Could not load notifications.")) }
    }

    suspend fun markAllNotificationsRead(): Boolean = try {
        request("/v1/social/notifications/read", method = "POST", body = JSONObject())
        val updated = notifications.map { it.copy(isRead = true) }
        notifications.clear(); notifications.addAll(updated)
        statusMessage = "All notifications marked as read."
        true
    } catch (e: Exception) {
        statusMessage = friendly(e, "Could not mark notifications as read.")
        false
    }

    // Calls

    private var lastWarmMs = 0L
    /** Warm DNS+TLS to LiveKit + native-speed API paths so call/send feel instant (iOS CallWarmup parity). */
    fun warmCallPath() {
        val now = System.currentTimeMillis()
        if (now - lastWarmMs < 25_000L) return
        lastWarmMs = now
        scope.launch(Dispatchers.IO) {
            // LiveKit HEAD over https
            runCatching {
                val lk = AppConfig.liveKitUrl.replace("wss://", "https://")
                val c = (URL(lk).openConnection() as HttpURLConnection).apply {
                    requestMethod = "HEAD"; connectTimeout = 4_000; readTimeout = 4_000
                }
                try { c.responseCode } finally { c.disconnect() }
            }
            for (path in listOf("/v1/health", "/v1/social/me/call-number", "/v1/social/inbox?limit=1", "/v1/social/calls/incoming")) {
                runCatching {
                    // Best-effort warm — ignore auth failures; still primes TLS.
                    request(path, connectMs = 4_000, readMs = 4_000)
                }
            }
        }
    }

    suspend fun startCall(recipient: String, video: Boolean) {
        val target = normalizeHandle(recipient)
        if (target.isBlank()) {
            statusMessage = "Enter the person's Blindbandit username first."
            return
        }
        if (isInCall || isRinging) return
        warmCallPath()
        // Phase 1: US dial tone while dialing / connecting (before remote ring).
        callPeerName = "@$target"
        callPeerHandle = target
        isRinging = true
        statusMessage = "Calling @$target…"
        Announcer.announce(appContext, statusMessage)
        callSounds.callInitiated()
        var callId: String? = null
        try {
            val response = request("/v1/social/calls", method = "POST", body = JSONObject().put("handle", target).put("kind", if (video) "video" else "voice"), connectMs = 6_000, readMs = 8_000)
            callId = response.lString("id", "call_id").ifBlank { null }
            callPeerName = response.optJSONObject("recipient")?.lString("display_name").orEmpty().ifBlank { "@$target" }
            callPeerHandle = target
            // Phase 2: server minted the call — switch dial → US ringback.
            statusMessage = "Ringing ${callPeerName}…"
            callSounds.startRingback()
            // Do NOT await call-key E2EE before LiveKit — that serial wait was a multi-second stall.
            // Connect immediately; deliver frame key in parallel (connectCall tolerates null key).
            val id = callId
            if (id != null) {
                scope.launch {
                    val key = runCatching { sendCallFrameKey(id, target) }.getOrNull()
                    // Key after connect is best-effort; late key still helps peer decrypt.
                    if (key != null && activeCallId == id) {
                        // already connected without E2EE label — leave as-is
                    }
                }
            }
            connectCall(response, video, outgoing = true, frameKey = null)
        } catch (e: Exception) {
            // Always end the call on the server so it never stays "ringing".
            isRinging = false
            callSounds.busyOrFailed()
            callId?.let { id -> scope.launch { endOnServer(id) } }
            cleanupRoom()
            statusMessage = "Call failed: ${friendly(e, "Unknown error")}"
            Announcer.announce(appContext, statusMessage)
        }
    }

    suspend fun refreshIncomingCalls() {
        if (activeCallId != null || isInCall || isRinging) return
        try {
            val items = request("/v1/social/calls/incoming").items()
            val incoming = items.firstOrNull { row ->
                val created = row.lTime("created_at") ?: 0L
                created > 0 && System.currentTimeMillis() - created in 0..RING_TIMEOUT_MS
            }
            incomingCallId = incoming?.lString("id", "call_id")?.takeIf { it.isNotBlank() }
        } catch (_: Exception) { /* FCM still works if the optional polling route is unavailable. */ }
    }

    suspend fun startGroupCall(groupId: String, video: Boolean) {
        if (isInCall || isRinging) return
        var id: String? = null
        try {
            val response = request("/v1/social/calls", "POST", JSONObject().put("group_id", groupId).put("kind", if (video) "video" else "voice"))
            id = response.lString("id", "call_id").ifBlank { null }
            callPeerName = response.lString("group_name").ifBlank { "Group" }
            callPeerHandle = ""
            // Fan out the same frame key to every member who has device keys (group frame E2EE).
            val key = id?.let { callId -> sendGroupCallFrameKey(callId, groupId) }
            connectCall(response, video, outgoing = true, frameKey = key)
        } catch (e: Exception) {
            id?.let { endOnServer(it) }; cleanupRoom()
            statusMessage = friendly(e, "Group call could not start")
        }
    }

    suspend fun joinCall(callId: String) {
        if (callId.isBlank()) return
        // Already joined this call — ignore duplicate answer taps.
        if (activeCallId == callId && (isInCall || joiningCallId == callId)) return
        // Stuck outbound ringing / failed place must not block Answer.
        if (isRinging && activeCallId == null && joiningCallId == null) {
            isRinging = false
            callSounds.stopOutgoingProgress()
        }
        if (isInCall || activeCallId != null) {
            statusMessage = "Already in a call. Hang up before answering another."
            Announcer.announce(appContext, statusMessage)
            return
        }
        incomingCallId = null
        joiningCallId = callId
        joinedAt[callId] = System.currentTimeMillis()
        statusMessage = "Joining…"
        Announcer.announce(appContext, "Joining call")
        try {
            // Join first (fast). Identity + frame key must NOT serialize ahead of LiveKit.
            val response = request(
                "/v1/social/calls/${enc(callId)}/join",
                method = "POST",
                body = JSONObject().put("installation_id", DeviceIdentity.installationId(appContext)),
                connectMs = 6_000,
                readMs = 8_000,
            )
            val invite = runCatching {
                request("/v1/social/calls/incoming", connectMs = 4_000, readMs = 6_000)
                    .items().firstOrNull { it.lString("id", "call_id") == callId }
            }.getOrNull()
            val caller = response.optJSONObject("caller") ?: response.optJSONObject("other") ?: invite?.optJSONObject("caller")
            callPeerName = caller?.lString("display_name", "handle").orEmpty().ifBlank { "Blindbandit caller" }
            callPeerHandle = caller?.lString("handle").orEmpty()
                .ifBlank { invite?.lString("from_handle", "caller_handle").orEmpty() }
            // Connect immediately — media first. Frame E2EE catches up in background.
            connectCall(
                response.apply { if (!has("id")) put("id", callId) },
                response.lString("kind") == "video",
                outgoing = false,
                frameKey = null,
            )
            val handle = callPeerHandle
            val groupBlank = response.lString("group_id").isBlank() && invite?.lString("group_id").isNullOrBlank()
            if (groupBlank && handle.isNotBlank()) {
                scope.launch {
                    val callerId = caller?.lString("id")?.takeIf { it.isNotBlank() }
                        ?: invite?.lString("caller_id")?.takeIf { it.isNotBlank() }
                        ?: runCatching {
                            request("/v1/social/profiles/${enc(handle)}", connectMs = 4_000, readMs = 6_000)
                                .lString("id").takeIf { it.isNotBlank() }
                        }.getOrNull()
                    if (callerId != null && activeCallId == callId) {
                        awaitCallFrameKey(callId, handle, callerId, maxAttempts = 4, delayMs = 400L)?.let { key ->
                            applyLateFrameKey(key)
                        }
                    }
                }
            }
        } catch (e: BlindbanditApiException) {
            cleanupRoom()
            // Only hang up the server call on definitive "gone" — never on auth/network blips.
            if (e.status in setOf(404, 409, 410)) {
                scope.launch { endOnServer(callId) }
            }
            statusMessage = "Could not join call: ${friendly(e, "Unknown error")}"
            Announcer.announce(appContext, statusMessage)
        } catch (e: Exception) {
            cleanupRoom()
            // Transient failure — leave the call ringing for the peer / retry.
            statusMessage = "Could not join call: ${friendly(e, "Unknown error")}"
            Announcer.announce(appContext, statusMessage)
        } finally {
            // Keep answer-echo grace via joinedAt; drop joining flag shortly after connect.
            if (joiningCallId == callId) {
                scope.launch {
                    delay(1_500)
                    if (joiningCallId == callId) joiningCallId = null
                }
            }
        }
    }

    /** Apply a late call-frame key after LiveKit is already up (answer path). */
    private fun applyLateFrameKey(key: CallFrameKeys.Key) {
        val provider = callKeyProvider
        if (provider != null) {
            runCatching { provider.setSharedKey(key.secret, key.index % 16) }
            callEncryptionLabel = "End-to-end encrypted"
            return
        }
        // Room already created without E2EEOptions — label stays transit-encrypted.
        runCatching {
            val p = BaseKeyProvider(enableSharedKey = true).also {
                check(it.setSharedKey(key.secret, key.index % 16))
            }
            callKeyProvider = p
            callEncryptionLabel = "End-to-end encrypted"
        }
    }

    /** True when this device just answered/joined and a late "answered elsewhere" echo would kill the call. */
    fun shouldIgnoreAnswerEcho(callId: String): Boolean {
        if (joiningCallId == callId) return true
        val t0 = joinedAt[callId] ?: return false
        // 12s grace — join+LiveKit connect can exceed 8s on slow networks.
        if (System.currentTimeMillis() - t0 < 12_000L) return true
        return false
    }

    /** Caller hung up, answered elsewhere, or server sent call_end. Honours answer-echo grace. */
    fun remoteEnded(callId: String) {
        if (callId.isBlank()) return
        if (shouldIgnoreAnswerEcho(callId)) return
        if (incomingCallId == callId) incomingCallId = null
        if (activeCallId == callId) endCall("Call ended.")
    }

    suspend fun declineCall(callId: String) {
        incomingCallId = null
        try {
            request("/v1/social/calls/${enc(callId)}/decline", "POST", JSONObject())
        } catch (e: BlindbanditApiException) {
            if (e.status == 404 || e.status == 405) endOnServer(callId) else throw e
        }
        statusMessage = "Call declined."
    }

    private suspend fun connectCall(response: JSONObject, video: Boolean, outgoing: Boolean, frameKey: CallFrameKeys.Key? = null) {
        val grant = CallRtcGrant.parse(response)
        activeCallId = response.lString("id", "call_id").ifBlank { null }
        if (grant.usesAgora) {
            connectAgora(grant, video, outgoing)
        } else {
            connectLiveKit(grant, video, outgoing, frameKey)
        }
    }

    private suspend fun connectAgora(grant: CallRtcGrant, video: Boolean, outgoing: Boolean) {
        activeRtcProvider = "agora"
        callKeyProvider = null
        callEncryptionLabel = "Media encrypted in transit (Agora); frame E2EE follow-up"
        val appId = grant.agoraAppId!!
        val token = grant.agoraToken!!
        val channel = grant.agoraChannel!!
        val uid = grant.agoraUid!!
        var remoteJoined = false
        val session = AgoraCallSession(
            appContext = appContext,
            onJoined = { },
            onUserJoined = {
                remoteJoined = true
                scope.launch(Dispatchers.Main.immediate) {
                    if (isRinging) {
                        isRinging = false
                        callSounds.callConnected()
                        statusMessage = "Connected with ${callPeerName.ifBlank { "Blindbandit user" }}."
                        Announcer.announce(appContext, statusMessage)
                    }
                }
            },
            onUserOffline = {
                scope.launch(Dispatchers.Main.immediate) {
                    if (isInCall && (agoraSession?.remoteUids?.isEmpty() != false)) {
                        endCall(reason = "${callPeerName.ifBlank { "The other person" }} left the call.")
                    }
                }
            },
            onError = { msg ->
                scope.launch(Dispatchers.Main.immediate) { statusMessage = msg }
            },
        )
        withContext(Dispatchers.Main) {
            session.join(appId = appId, channel = channel, token = token, uid = uid, video = video)
            agoraSession = session
            room = null
        }
        callSounds.resumeOutgoingProgressIfNeeded()
        val cameraOn = video && !startWithCameraOff && androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        session.setMic(true)
        if (cameraOn) session.setCamera(true) else session.setCamera(false)
        isVideoCall = video
        micEnabled = true
        cameraEnabled = cameraOn
        callSeconds = 0
        setSpeaker(speakerByDefault || video, announce = false)
        callSounds.resumeOutgoingProgressIfNeeded()
        if (outgoing && !remoteJoined && (agoraSession?.remoteUids?.isEmpty() != false)) {
            isRinging = true
            statusMessage = "Ringing ${callPeerName}…"
            Announcer.announce(appContext, statusMessage)
            val started = System.currentTimeMillis()
            while (agoraSession === session && (session.remoteUids.isEmpty())) {
                if (System.currentTimeMillis() - started >= RING_TIMEOUT_MS) {
                    isRinging = false
                    endCall(reason = "No answer from ${callPeerName}.")
                    return
                }
                delay(500)
            }
            isRinging = false
            callSounds.callConnected()
            if (agoraSession !== session) return
        }
        isInCall = true
        statusMessage = "Connected with ${callPeerName.ifBlank { "Blindbandit user" }}."
        Announcer.announce(appContext, statusMessage)
        scope.launch { while (agoraSession === session && isInCall) { delay(1000); if (agoraSession === session && isInCall) callSeconds += 1 } }
    }

    private suspend fun connectLiveKit(grant: CallRtcGrant, video: Boolean, outgoing: Boolean, frameKey: CallFrameKeys.Key? = null) {
        activeRtcProvider = "livekit"
        agoraSession?.leave()
        agoraSession = null
        val token = grant.livekitToken.orEmpty()
        val url = grant.livekitUrl?.ifBlank { null } ?: AppConfig.liveKitUrl
        require(java.net.URI(url).scheme == "wss") { "The call server must use a secure connection" }
        if (token.isBlank() || url.isBlank()) error("The call server is unavailable right now. Please try again shortly.")

        // FrameCryptorFactory uses native WebRTC; initialize it before constructing the provider.
        LiveKit.init(appContext)
        val provider = frameKey?.let { key ->
            BaseKeyProvider(enableSharedKey = true).also { check(it.setSharedKey(key.secret, key.index % 16)) { "Call encryption could not be initialized" } }
        }
        callKeyProvider = provider
        callEncryptionLabel = if (provider != null) "End-to-end encrypted" else "Media encrypted in transit; end-to-end encryption unavailable"
        val newRoom = LiveKit.create(appContext = appContext, options = RoomOptions(e2eeOptions = provider?.let { E2EEOptions(keyProvider = it) }))
        room = newRoom
        newRoom.connect(url = url, token = token)
        newRoom.localParticipant.setMicrophoneEnabled(true)
        // Local LiveKit connect is NOT remote answer — keep US ringback looping.
        callSounds.resumeOutgoingProgressIfNeeded()
        val cameraOn = video && !startWithCameraOff && androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraOn) newRoom.localParticipant.setCameraEnabled(true)
        isVideoCall = video
        micEnabled = true
        cameraEnabled = cameraOn
        callSeconds = 0
        setSpeaker(speakerByDefault || video, announce = false)
        callSounds.resumeOutgoingProgressIfNeeded()
        if (outgoing && newRoom.remoteParticipants.isEmpty()) {
            isRinging = true
            statusMessage = "Ringing ${callPeerName}…"
            // Do not stop ringback / play connected yet — wait for remote.
            Announcer.announce(appContext, statusMessage)
            val started = System.currentTimeMillis()
            while (room === newRoom && newRoom.remoteParticipants.isEmpty()) {
                if (System.currentTimeMillis() - started >= RING_TIMEOUT_MS) {
                    isRinging = false
                    endCall(reason = "No answer from ${callPeerName}.")
                    return
                }
                delay(500)
            }
            isRinging = false
            callSounds.callConnected()
            if (room !== newRoom) return
        }
        isInCall = true
        statusMessage = "Connected with ${callPeerName.ifBlank { "Blindbandit user" }}."
        Announcer.announce(appContext, statusMessage)
        scope.launch { watchForHangup(newRoom) }
        scope.launch { while (room === newRoom && isInCall) { delay(1000); if (room === newRoom && isInCall) callSeconds += 1 } }
    }

    /** Fan out one shared frame key to every group member with device keys. */
    private suspend fun sendGroupCallFrameKey(callId: String, groupId: String): CallFrameKeys.Key? {
        val engine = encryption ?: return null
        val key = CallFrameKeys.newKey(callId)
        val members = try {
            groupDetail(groupId).optJSONArray("members") ?: JSONArray()
        } catch (_: Exception) {
            return null
        }
        val handles = (0 until members.length()).mapNotNull { i ->
            members.getJSONObject(i).lString("handle").takeIf { it.isNotBlank() }
        }.map(::normalizeHandle).filter { it.isNotBlank() && !it.equals(myHandle, true) }.distinct()
        var sent = 0
        for (handle in handles) {
            try {
                val payload = JSONObject().put("t", "call_key").put("body", key.wire()).put("silent", true)
                    .put("sent_at", System.currentTimeMillis())
                val fields = engine.fields(listOf(handle), payload) ?: continue
                request("/v1/social/messages", "POST", fields.put("handle", handle).put("silent", true))
                sent++
            } catch (_: Exception) {
                // Skip peers without keys or transient failures; keep trying others.
            }
        }
        return if (sent > 0) key else null
    }

    /** A call key is sent only inside an authenticated p256-v1 envelope, never as plaintext. */
    private suspend fun sendCallFrameKey(callId: String, handle: String): CallFrameKeys.Key? {
        val engine = encryption ?: error("Encryption is not ready. Retry after your account loads.")
        val key = CallFrameKeys.newKey(callId)
        val payload = JSONObject().put("t", "call_key").put("body", key.wire()).put("silent", true)
            .put("sent_at", System.currentTimeMillis())
        val fields = engine.fields(listOf(handle), payload) ?: return null // legacy peer without device keys
        request("/v1/social/messages", "POST", fields.put("handle", handle).put("silent", true))
        return key
    }

    private suspend fun fetchCallFrameKeys(handle: String) {
        val rows = request("/v1/social/messages?limit=100").items()
        val conversation = rows.mapNotNull(ServerConversation::parse).firstOrNull { it.peerHandle.equals(handle, true) } ?: return
        request("/v1/social/messages/${enc(conversation.id)}?limit=100").items().forEach { encryption?.resolve(it) }
    }

    private suspend fun awaitCallFrameKey(
        callId: String,
        handle: String,
        senderId: String,
        maxAttempts: Int = 8,
        delayMs: Long = 1_000L,
    ): CallFrameKeys.Key? {
        repeat(maxAttempts) { attempt ->
            encryption?.callKeys?.get(callId, senderId)?.let { return it }
            try { fetchCallFrameKeys(handle) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) { }
            encryption?.callKeys?.get(callId, senderId)?.let { return it }
            if (attempt < maxAttempts - 1) delay(delayMs)
        }
        return null
    }

    /** Ends our side when the other person leaves the room. */
    private suspend fun watchForHangup(watched: Room) {
        var hadPeer = watched.remoteParticipants.isNotEmpty()
        while (room === watched && isInCall) {
            val now = watched.remoteParticipants.isNotEmpty()
            if (hadPeer && !now) { endCall(reason = "${callPeerName.ifBlank { "The other person" }} left the call."); return }
            hadPeer = hadPeer || now
            delay(1000)
        }
    }

    fun tick() { if (isInCall) callSeconds += 1 }

    fun toggleMic() {
        val target = !micEnabled
        scope.launch {
            try {
                agoraSession?.setMic(target) ?: room?.localParticipant?.setMicrophoneEnabled(target)
                micEnabled = target
                Announcer.announce(appContext, if (target) "Microphone on" else "Muted")
            } catch (e: Exception) { Announcer.announce(appContext, "Microphone could not be changed.") }
        }
    }

    fun toggleCamera() {
        if (!isVideoCall) return
        val target = !cameraEnabled
        scope.launch {
            try {
                agoraSession?.setCamera(target) ?: room?.localParticipant?.setCameraEnabled(target)
                cameraEnabled = target
                Announcer.announce(appContext, if (target) "Camera on" else "Camera off")
            } catch (e: Exception) { Announcer.announce(appContext, "Camera could not be changed. Check camera permission.") }
        }
    }

    fun toggleSpeaker() = setSpeaker(!speakerOn, announce = true)

    private fun setSpeaker(on: Boolean, announce: Boolean) {
        val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        runCatching {
            audio.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                when {
                    on -> audio.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.let { audio.setCommunicationDevice(it) }
                    preferBluetoothHeadset -> {
                        val bt = audio.availableCommunicationDevices.firstOrNull {
                            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == AudioDeviceInfo.TYPE_BLE_HEADSET || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
                        }
                        if (bt != null) audio.setCommunicationDevice(bt) else audio.clearCommunicationDevice()
                    }
                    else -> audio.clearCommunicationDevice()
                }
            } else {
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = on
            }
        }
        speakerOn = on
        if (announce) Announcer.announce(appContext, if (on) "Speaker on" else "Speaker off")
    }

    fun endCall(reason: String = "Call ended.") {
        val callId = activeCallId
        callId?.let { encryption?.callKeys?.clear(it) }
        callKeyProvider = null
        callEncryptionLabel = "Media encrypted in transit"
        val wasConnected = isInCall
        activeCallId = null
        isInCall = false
        isRinging = false
        if (wasConnected) callSounds.hangup() else callSounds.stopOutgoingProgress()
        isVideoCall = false
        cameraEnabled = false
        callSeconds = 0
        statusMessage = reason
        Announcer.announce(appContext, reason)
        val activeRoom = room
        val activeAgora = agoraSession
        room = null
        agoraSession = null
        activeRtcProvider = "livekit"
        scope.launch {
            try { activeAgora?.leave() } catch (_: Exception) {}
            try { activeRoom?.localParticipant?.setMicrophoneEnabled(false) } catch (_: Exception) {}
            try { activeRoom?.localParticipant?.setCameraEnabled(false) } catch (_: Exception) {}
            try { activeRoom?.disconnect(); activeRoom?.release() } catch (_: Exception) {}
            resetAudio()
            if (!callId.isNullOrBlank()) endOnServer(callId)
            if (wasConnected || callId != null) loadCallHistory()
        }
    }

    private fun cleanupRoom() {
        callSounds.stopOutgoingProgress()
        activeCallId?.let { encryption?.callKeys?.clear(it) }
        callKeyProvider = null
        callEncryptionLabel = "Media encrypted in transit"
        val r = room
        val a = agoraSession
        room = null
        agoraSession = null
        activeRtcProvider = "livekit"
        activeCallId = null
        isRinging = false
        isInCall = false
        scope.launch {
            runCatching { a?.leave() }
            runCatching { r?.disconnect(); r?.release() }
            resetAudio()
        }
    }

    private fun resetAudio() {
        val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        runCatching {
            if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice() else @Suppress("DEPRECATION") { audio.isSpeakerphoneOn = false }
            audio.mode = AudioManager.MODE_NORMAL
        }
        speakerOn = false
    }

    private suspend fun endOnServer(callId: String) {
        repeat(3) { attempt ->
            try {
                request("/v1/social/calls/${enc(callId)}/end", method = "POST", body = JSONObject())
                return
            } catch (e: BlindbanditApiException) {
                if (e.status in setOf(404, 409, 410)) return
                if (e.status < 500 && e.status != 429) { statusMessage = "Could not confirm call ended on server."; return }
                delay(1000L * (attempt + 1))
            } catch (_: Exception) {
                delay(1000L * (attempt + 1))
            }
        }
    }

    /** Registers this device's FCM token so the Blindbandit API can deliver call/message alerts. */
    suspend fun registerDevice(token: String, installationId: String, appVersion: String, language: String): Boolean = try {
        request(
            "/v1/social/devices/register",
            method = "POST",
            body = JSONObject().put("installation_id", installationId).put("platform", "android")
                .put("token", token).put("app_version", appVersion).put("language", language),
        )
        true
    } catch (_: Exception) {
        false
    }

    /** Blocks a profile so they can no longer message or call this account. */
    suspend fun blockUser(handle: String): Boolean = try {
        request("/v1/social/profiles/${enc(normalizeHandle(handle))}/block", method = "POST", body = JSONObject())
        statusMessage = "Blocked @${normalizeHandle(handle)}. They can no longer message or call you."
        refreshConversations()
        true
    } catch (e: Exception) {
        statusMessage = friendly(e, "Could not block this person.")
        false
    }

    /** Sends an abuse report (target_type: profile, message, call or comment) to Trust & Safety. */
    suspend fun report(targetType: String, targetId: String, reason: String, details: String = ""): Boolean = try {
        request(
            "/v1/social/reports",
            method = "POST",
            body = JSONObject().put("target_type", targetType).put("target_id", targetId.take(100))
                .put("reason", reason.take(200)).put("details", details.take(2000)),
        )
        statusMessage = "Thanks. Your report was sent to the Blindbandit safety team."
        true
    } catch (e: Exception) {
        statusMessage = friendly(e, "Could not send the report.")
        false
    }

    private fun friendly(e: Exception, fallback: String): String = when (e) {
        is IOException -> "You're offline or the Blindbandit service can't be reached. Check your connection and try again."
        else -> e.localizedMessage?.takeIf { it.isNotBlank() } ?: fallback
    }

    internal fun enc(value: String) = URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")


    suspend fun uploadPublicAvatar(jpeg: ByteArray): String = withContext(Dispatchers.IO) {
        require(jpeg.isNotEmpty() && jpeg.size <= 5 * 1024 * 1024) { "Choose a JPEG under 5 MB" }
        val token = auth.sessionToken() ?: error("Sign in to update your profile picture.")
        val connection = (URL(AppConfig.API_BASE_URL.trimEnd('/') + "/v1/social/me/avatar").openConnection() as HttpURLConnection).apply {
            requestMethod = "PUT"
            doOutput = true
            setFixedLengthStreamingMode(jpeg.size)
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "image/jpeg")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Installation-ID", DeviceIdentity.installationId(appContext))
            connectTimeout = 20_000
            readTimeout = 45_000
        }
        try {
            connection.outputStream.use { it.write(jpeg) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status == 404) error("Profile photo upload is not available on the server yet.")
            val profile = BlindbanditApiEnvelope.unwrap(status, text)
            val url = profile.lString("avatar_url")
            require(url.isNotBlank()) { "Upload succeeded but no public avatar URL was returned." }
            myAvatarUrl = url
            url
        } finally { connection.disconnect() }
    }

    suspend fun clearPublicAvatar() {
        val profile = request("/v1/social/me", "PATCH", JSONObject().put("avatar_url", ""))
        myAvatarUrl = profile.lString("avatar_url")
        statusMessage = "Profile picture removed."
    }

    internal suspend fun request(
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
        connectMs: Int = 8_000,
        readMs: Int = 12_000,
    ): JSONObject = withContext(Dispatchers.IO) {
        val token = auth.sessionToken() ?: error("Sign in to use calls and messages.")
        val connection = (URL(AppConfig.API_BASE_URL.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            // Android's platform HttpURLConnection (OkHttp-backed) accepts PATCH.
            requestMethod = method
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Installation-ID", DeviceIdentity.installationId(appContext))
            connectTimeout = connectMs
            readTimeout = readMs
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (body != null) connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            BlindbanditApiEnvelope.unwrap(status, text)
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        const val RING_TIMEOUT_MS = 45_000L

    }
}

/** Blindbandit handles are stored without the leading @ and in lowercase. */
fun normalizeHandle(raw: String): String = raw.trim().removePrefix("@").lowercase()

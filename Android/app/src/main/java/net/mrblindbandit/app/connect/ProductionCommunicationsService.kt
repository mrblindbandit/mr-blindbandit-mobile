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
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.config.AppConfig
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
    var callEncryptionLabel by mutableStateOf("Media encrypted in transit"); private set
    private var callKeyProvider: BaseKeyProvider? = null

    var room by mutableStateOf<Room?>(null); private set
    private var lastTypingSent = 0L

    /** Mirrors the "Start video calls with camera off" setting. */
    var startWithCameraOff: Boolean = false
    var speakerByDefault: Boolean = false

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
    }

    suspend fun refreshUnreadCount() {
        try {
            val r = request("/v1/social/messages/unread-count")
            serverUnreadCount = (r.lLong("unread_count", "count", "unread", "value") ?: 0L).toInt().coerceAtLeast(0)
        } catch (_: Exception) { }
    }

    suspend fun refreshConversations(): Boolean {
        if (conversations.isEmpty()) conversationsState = LoadState.Loading
        return try {
            val parsed = request("/v1/social/messages?limit=100").items().mapNotNull { runCatching { ServerConversation.parse(it) }.getOrNull() }
            announceNewIncoming(parsed)
            conversations.clear()
            conversations.addAll(parsed)
            conversationsState = LoadState.Loaded
            refreshUnreadCount()
            true
        } catch (e: Exception) {
            conversationsState = LoadState.Failed(friendly(e, "Could not load your conversations."))
            false
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
    suspend fun reloadThread(conversationId: String): List<ServerMessage> = try {
        val result = request("/v1/social/messages/${enc(conversationId)}?limit=100")
        val parsed = result.items().mapNotNull { runCatching { encryption?.resolve(it) ?: if (!it.lBool("e2ee")) ServerMessage.parse(it) else ServerMessage.parse(it)?.copy(body = "Encrypted message unavailable on this device", encrypted = true, decryptFailed = true) }.getOrNull() }.sortedBy { it.createdAt }
        if (openConversationId != conversationId) emptyList() else {
            val known = messages.map { it.id }.toSet()
            val hadMessages = messages.isNotEmpty()
            val incoming = parsed.filter { it.id !in known && it.senderId != myProfileId }
            messages.clear()
            messages.addAll(parsed)
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

    /** Sends a message. If the device is offline the message is queued and sent later. */
    suspend fun sendMessage(recipient: String, body: String, conversationId: String = ""): String? {
        val target = normalizeHandle(recipient)
        val text = body.trim().take(4000)
        if (target.isBlank() || text.isBlank()) {
            statusMessage = "Enter the person's Blindbandit username and a message."
            return null
        }
        return try {
            val fields = messageFields(listOf(target), text).put("handle", target)
            val response = request("/v1/social/messages", method = "POST", body = fields)
            val who = response.optJSONObject("recipient")?.lString("display_name").orEmpty().ifBlank { "@$target" }
            statusMessage = if (fields.optBoolean("e2ee")) "Encrypted message sent to $who." else "Message sent to $who without end-to-end encryption."
            val id = response.lString("conversation_id").ifBlank { conversationId }
            refreshConversations()
            if (id.isNotBlank() && openConversationId == id) reloadThread(id)
            id.ifBlank { null }
        } catch (e: IOException) {
            val item = PendingMessage(UUID.randomUUID().toString(), target, text, conversationId, System.currentTimeMillis())
            pendingMessages.add(item)
            local.pending = pendingMessages.toList()
            statusMessage = "You're offline. The message to @$target will send when you're back online."
            Announcer.announce(appContext, statusMessage)
            null
        } catch (e: Exception) {
            statusMessage = friendly(e, "Message could not be sent.")
            Announcer.announce(appContext, statusMessage)
            null
        }
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

    suspend fun startCall(recipient: String, video: Boolean) {
        val target = normalizeHandle(recipient)
        if (target.isBlank()) {
            statusMessage = "Enter the person's Blindbandit username first."
            return
        }
        if (isInCall || isRinging) return
        statusMessage = "Calling @$target…"
        var callId: String? = null
        try {
            val response = request("/v1/social/calls", method = "POST", body = JSONObject().put("handle", target).put("kind", if (video) "video" else "voice"))
            callId = response.lString("id", "call_id").ifBlank { null }
            callPeerName = response.optJSONObject("recipient")?.lString("display_name").orEmpty().ifBlank { "@$target" }
            callPeerHandle = target
            val key = callId?.let { sendCallFrameKey(it, target) }
            connectCall(response, video, outgoing = true, frameKey = key)
        } catch (e: Exception) {
            // Always end the call on the server so it never stays "ringing".
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
            connectCall(response, video, outgoing = true)
        } catch (e: Exception) {
            id?.let { endOnServer(it) }; cleanupRoom()
            statusMessage = friendly(e, "Group call could not start")
        }
    }

    suspend fun joinCall(callId: String) {
        if (callId.isBlank()) return
        if (isInCall || isRinging || activeCallId != null) return
        incomingCallId = null
        try {
            // A push tap only has a call ID. Resolve caller identity from the authenticated invite,
            // never trust a sender-supplied call_key control to identify the caller.
            val invite = request("/v1/social/calls/incoming").items().firstOrNull { it.lString("id", "call_id") == callId }
            val response = request("/v1/social/calls/${enc(callId)}/join", method = "POST", body = JSONObject().put("installation_id", DeviceIdentity.installationId(appContext)))
            val caller = response.optJSONObject("caller") ?: response.optJSONObject("other") ?: invite?.optJSONObject("caller")
            callPeerName = caller?.lString("display_name", "handle").orEmpty().ifBlank { "Blindbandit caller" }
            callPeerHandle = caller?.lString("handle").orEmpty().ifBlank { invite?.lString("from_handle", "caller_handle").orEmpty() }
            val callerId = caller?.lString("id")?.takeIf { it.isNotBlank() } ?: invite?.lString("caller_id")?.takeIf { it.isNotBlank() } ?: callPeerHandle.takeIf { it.isNotBlank() }?.let {
                request("/v1/social/profiles/${enc(it)}").lString("id").takeIf { id -> id.isNotBlank() }
            }
            val key = if (response.lString("group_id").isBlank() && invite?.lString("group_id").isNullOrBlank() && callPeerHandle.isNotBlank() && callerId != null)
                awaitCallFrameKey(callId, callPeerHandle, callerId) else null
            connectCall(response.apply { if (!has("id")) put("id", callId) }, response.lString("kind") == "video", outgoing = false, frameKey = key)
        } catch (e: Exception) {
            endOnServer(callId)
            cleanupRoom()
            statusMessage = "Could not join call: ${friendly(e, "Unknown error")}"
            Announcer.announce(appContext, statusMessage)
        }
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
        val livekit = response.optJSONObject("livekit") ?: JSONObject()
            .put("token", response.lString("token")).put("url", response.lString("livekit_url"))
        val token = livekit.lString("token")
        val url = livekit.lString("url").ifBlank { AppConfig.liveKitUrl }
        require(java.net.URI(url).scheme == "wss") { "The call server must use a secure connection" }
        if (token.isBlank() || url.isBlank()) error("The call server is unavailable right now. Please try again shortly.")
        activeCallId = response.lString("id", "call_id").ifBlank { null }

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
        val cameraOn = video && !startWithCameraOff && androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraOn) newRoom.localParticipant.setCameraEnabled(true)
        isVideoCall = video
        micEnabled = true
        cameraEnabled = cameraOn
        callSeconds = 0
        setSpeaker(speakerByDefault || video, announce = false)
        if (outgoing && newRoom.remoteParticipants.isEmpty()) {
            isRinging = true
            statusMessage = "Ringing ${callPeerName}…"
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
            if (room !== newRoom) return
        }
        isInCall = true
        statusMessage = "Connected with ${callPeerName.ifBlank { "Blindbandit user" }}."
        Announcer.announce(appContext, statusMessage)
        scope.launch { watchForHangup(newRoom) }
        scope.launch { while (room === newRoom && isInCall) { delay(1000); if (room === newRoom && isInCall) callSeconds += 1 } }
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

    private suspend fun awaitCallFrameKey(callId: String, handle: String, senderId: String): CallFrameKeys.Key? {
        repeat(8) { attempt ->
            encryption?.callKeys?.get(callId, senderId)?.let { return it }
            try { fetchCallFrameKeys(handle) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Exception) { }
            encryption?.callKeys?.get(callId, senderId)?.let { return it }
            if (attempt < 7) delay(1000)
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
            try { room?.localParticipant?.setMicrophoneEnabled(target); micEnabled = target; Announcer.announce(appContext, if (target) "Microphone on" else "Muted") }
            catch (e: Exception) { Announcer.announce(appContext, "Microphone could not be changed.") }
        }
    }

    fun toggleCamera() {
        if (!isVideoCall) return
        val target = !cameraEnabled
        scope.launch {
            try { room?.localParticipant?.setCameraEnabled(target); cameraEnabled = target; Announcer.announce(appContext, if (target) "Camera on" else "Camera off") }
            catch (e: Exception) { Announcer.announce(appContext, "Camera could not be changed. Check camera permission.") }
        }
    }

    fun toggleSpeaker() = setSpeaker(!speakerOn, announce = true)

    private fun setSpeaker(on: Boolean, announce: Boolean) {
        val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        runCatching {
            audio.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                if (on) audio.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.let { audio.setCommunicationDevice(it) }
                else audio.clearCommunicationDevice()
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
        isVideoCall = false
        cameraEnabled = false
        callSeconds = 0
        statusMessage = reason
        Announcer.announce(appContext, reason)
        val activeRoom = room
        room = null
        scope.launch {
            try { activeRoom?.localParticipant?.setMicrophoneEnabled(false) } catch (_: Exception) {}
            try { activeRoom?.localParticipant?.setCameraEnabled(false) } catch (_: Exception) {}
            try { activeRoom?.disconnect(); activeRoom?.release() } catch (_: Exception) {}
            resetAudio()
            if (!callId.isNullOrBlank()) endOnServer(callId)
            if (wasConnected || callId != null) loadCallHistory()
        }
    }

    private fun cleanupRoom() {
        activeCallId?.let { encryption?.callKeys?.clear(it) }
        callKeyProvider = null
        callEncryptionLabel = "Media encrypted in transit"
        val r = room
        room = null
        activeCallId = null
        isRinging = false
        isInCall = false
        scope.launch { runCatching { r?.disconnect(); r?.release() }; resetAudio() }
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

    internal suspend fun request(path: String, method: String = "GET", body: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        val token = auth.sessionToken() ?: error("Sign in to use calls and messages.")
        val connection = (URL(AppConfig.API_BASE_URL.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            // Android's platform HttpURLConnection (OkHttp-backed) accepts PATCH.
            requestMethod = method
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Installation-ID", DeviceIdentity.installationId(appContext))
            connectTimeout = 15_000
            readTimeout = 20_000
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

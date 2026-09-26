package net.mrblindbandit.app.connect

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.config.AppConfig
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.nio.charset.StandardCharsets


data class ServerConversation(
    val id: String,
    val peerHandle: String,
    val peerName: String,
    val lastBody: String,
    val lastCreatedAt: Long,
    val verified: Boolean,
)

data class ServerMessage(
    val id: String,
    val senderId: String,
    val body: String,
    val createdAt: Long,
)

/**
 * Production communications client. Clerk session JWTs authenticate every API request.
 * Messages are persisted by the Blindbandit API. LiveKit tokens are minted server-side per call.
 */
class ProductionCommunicationsService(
    private val context: Context,
    private val auth: ClerkAuthService,
) {
    val conversations = mutableStateListOf<ServerConversation>()
    val messages = mutableStateListOf<ServerMessage>()

    var myProfileId by mutableStateOf(""); private set
    var myHandle by mutableStateOf(""); private set
    var statusMessage by mutableStateOf("")
    var isLoading by mutableStateOf(false); private set
    var isInCall by mutableStateOf(false); private set
    var isVideoCall by mutableStateOf(false); private set
    var micEnabled by mutableStateOf(true); private set
    var cameraEnabled by mutableStateOf(false); private set
    var callSeconds by mutableIntStateOf(0); private set
    var activeCallId by mutableStateOf<String?>(null); private set
    var callPeerName by mutableStateOf(""); private set

    private var room: Room? = null

    /** Mirrors the "Start video calls with camera off" setting. */
    var startWithCameraOff: Boolean = false

    val callTimeLabel: String get() = "%02d:%02d".format(callSeconds / 60, callSeconds % 60)

    suspend fun bootstrap() {
        isLoading = true
        try {
            val me = request("/v1/social/me")
            myProfileId = me.optString("id")
            myHandle = me.optString("handle")
            refreshConversations()
            statusMessage = "Calls and messages are online."
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Could not connect to Blindbandit communications."
        } finally {
            isLoading = false
        }
    }

    suspend fun refreshConversations() {
        try {
            val result = request("/v1/social/messages?limit=100")
            val items = result.optJSONArray("items") ?: JSONArray()
            val parsed = buildList {
                for (i in 0 until items.length()) {
                    val row = items.optJSONObject(i) ?: continue
                    val other = row.optJSONObject("other")
                    val last = row.optJSONObject("last_message")
                    add(
                        ServerConversation(
                            id = row.optString("id"),
                            peerHandle = other?.optString("handle").orEmpty(),
                            peerName = other?.optString("display_name").orEmpty().ifBlank { other?.optString("handle").orEmpty().ifBlank { "Blindbandit user" } },
                            lastBody = last?.optString("body").orEmpty(),
                            lastCreatedAt = last?.optLong("created_at") ?: 0L,
                            verified = other?.optBoolean("verified") ?: false,
                        )
                    )
                }
            }
            conversations.clear()
            conversations.addAll(parsed)
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Could not refresh conversations."
        }
    }

    suspend fun openConversation(conversationId: String) {
        try {
            val encoded = URLEncoder.encode(conversationId, StandardCharsets.UTF_8.name())
            val result = request("/v1/social/messages/$encoded?limit=100")
            val items = result.optJSONArray("items") ?: JSONArray()
            val parsed = buildList {
                for (i in 0 until items.length()) {
                    val row = items.optJSONObject(i) ?: continue
                    add(
                        ServerMessage(
                            id = row.optString("id"),
                            senderId = row.optString("sender_id"),
                            body = row.optString("body"),
                            createdAt = row.optLong("created_at"),
                        )
                    )
                }
            }.sortedBy { it.createdAt }
            messages.clear()
            messages.addAll(parsed)
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Could not load messages."
        }
    }

    suspend fun sendMessage(recipient: String, body: String): String? {
        val target = recipient.trim()
        val text = body.trim()
        if (target.isBlank() || text.isBlank()) {
            statusMessage = "Enter the person's Blindbandit username and a message."
            return null
        }
        return try {
            val response = request(
                "/v1/social/messages",
                method = "POST",
                body = JSONObject().put("handle", normalizeHandle(target)).put("body", text),
            )
            val recipientInfo = response.optJSONObject("recipient")
            statusMessage = "Message sent to ${recipientInfo?.optString("display_name").orEmpty().ifBlank { target }}."
            refreshConversations()
            response.optString("conversation_id").takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            statusMessage = e.localizedMessage ?: "Message could not be sent."
            null
        }
    }

    suspend fun startCall(recipient: String, video: Boolean) {
        val target = recipient.trim()
        if (target.isBlank()) {
            statusMessage = "Enter the person's Blindbandit username first."
            return
        }
        statusMessage = "Calling $target…"
        try {
            val response = request(
                "/v1/social/calls",
                method = "POST",
                body = JSONObject().put("handle", normalizeHandle(target)).put("kind", if (video) "video" else "voice"),
            )
            val recipientInfo = response.optJSONObject("recipient")
            callPeerName = recipientInfo?.optString("display_name").orEmpty().ifBlank { target }
            connectCall(response, video)
        } catch (e: Exception) {
            statusMessage = "Call failed: ${e.localizedMessage ?: "Unknown error"}"
        }
    }

    suspend fun joinCall(callId: String) {
        if (callId.isBlank()) return
        try {
            val encoded = URLEncoder.encode(callId, StandardCharsets.UTF_8.name())
            val response = request("/v1/social/calls/$encoded/join", method = "POST", body = JSONObject())
            callPeerName = "Incoming call"
            connectCall(response, response.optString("kind") == "video")
        } catch (e: Exception) {
            statusMessage = "Could not join call: ${e.localizedMessage ?: "Unknown error"}"
        }
    }

    private suspend fun connectCall(response: JSONObject, video: Boolean) {
        val livekit = response.optJSONObject("livekit") ?: error("The call server is unavailable right now. Please try again shortly.")
        val token = livekit.optString("token")
        // The API returns an empty url when LIVEKIT_URL is not set on the Worker; fall back to the
        // public LiveKit Cloud endpoint bundled with the app.
        val url = livekit.optString("url").ifBlank { net.mrblindbandit.app.config.AppConfig.liveKitUrl }
        if (token.isBlank() || url.isBlank()) error("The call server is unavailable right now. Please try again shortly.")

        val newRoom = LiveKit.create(appContext = context.applicationContext)
        newRoom.connect(url = url, token = token)
        newRoom.localParticipant.setMicrophoneEnabled(true)
        val cameraOn = video && !startWithCameraOff
        if (cameraOn) newRoom.localParticipant.setCameraEnabled(true)
        room = newRoom
        activeCallId = response.optString("id").takeIf { it.isNotBlank() }
        isVideoCall = video
        micEnabled = true
        cameraEnabled = cameraOn
        callSeconds = 0
        isInCall = true
        statusMessage = "Connected with ${callPeerName.ifBlank { "Blindbandit user" }}."
    }

    fun tick() {
        if (isInCall) callSeconds += 1
    }

    fun toggleMic() {
        micEnabled = !micEnabled
        val target = micEnabled
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launchSafely {
            room?.localParticipant?.setMicrophoneEnabled(target)
        }
    }

    fun toggleCamera() {
        if (!isVideoCall) return
        cameraEnabled = !cameraEnabled
        val target = cameraEnabled
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launchSafely {
            room?.localParticipant?.setCameraEnabled(target)
        }
    }

    fun endCall() {
        val callId = activeCallId
        val activeRoom = room
        room = null
        activeCallId = null
        isInCall = false
        isVideoCall = false
        cameraEnabled = false
        callSeconds = 0
        statusMessage = "Call ended."
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launchSafely {
            try { activeRoom?.localParticipant?.setMicrophoneEnabled(false) } catch (_: Exception) {}
            try { activeRoom?.localParticipant?.setCameraEnabled(false) } catch (_: Exception) {}
            try { activeRoom?.disconnect() } catch (_: Exception) {}
            if (!callId.isNullOrBlank()) {
                val encoded = URLEncoder.encode(callId, StandardCharsets.UTF_8.name())
                try { request("/v1/social/calls/$encoded/end", method = "POST", body = JSONObject()) } catch (_: Exception) {}
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
        val encoded = URLEncoder.encode(normalizeHandle(handle), StandardCharsets.UTF_8.name())
        request("/v1/social/profiles/$encoded/block", method = "POST", body = JSONObject())
        statusMessage = "Blocked @${normalizeHandle(handle)}. They can no longer message or call you."
        refreshConversations()
        true
    } catch (e: Exception) {
        statusMessage = e.localizedMessage ?: "Could not block this person."
        false
    }

    /** Sends an abuse report to the Blindbandit trust & safety queue. */
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
        statusMessage = e.localizedMessage ?: "Could not send the report."
        false
    }

    private suspend fun request(path: String, method: String = "GET", body: JSONObject? = null): JSONObject = withContext(Dispatchers.IO) {
        val token = auth.sessionToken() ?: error("Sign in to use calls and messages.")
        val connection = (URL(AppConfig.API_BASE_URL.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
            connectTimeout = 15_000
            readTimeout = 20_000
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        if (body != null) connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        connection.disconnect()
        BlindbanditApiEnvelope.unwrap(status, text)
    }
}

/** Blindbandit handles are stored without the leading @ and in lowercase. */
fun normalizeHandle(raw: String): String = raw.trim().removePrefix("@").lowercase()

private fun kotlinx.coroutines.CoroutineScope.launchSafely(block: suspend () -> Unit) =
    launch { try { block() } catch (_: Exception) {} }

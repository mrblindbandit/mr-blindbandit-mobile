package net.mrblindbandit.app.connect

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import io.livekit.android.room.track.DataPublishReliability
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import net.mrblindbandit.app.config.AppConfig
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val sender: String,
    val body: String,
    val isLocal: Boolean,
    val isVoiceNote: Boolean = false,
    val voiceNotePath: String? = null
)

enum class ConnectionState { Disconnected, Connecting, Connected, Error }

/** LiveKit façade — real Room.connect via scaffold token or POST /v1/livekit/token. */
class LiveKitService(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sounds = CallSounds(context)
    val threadStore = DMThreadStore(context)

    var connectionState by mutableStateOf(ConnectionState.Disconnected); private set
    var isInCall by mutableStateOf(false); private set
    var isVideoCall by mutableStateOf(false); private set
    var micEnabled by mutableStateOf(true)
    var cameraEnabled by mutableStateOf(false)
    var statusMessage by mutableStateOf("")
    var callElapsedSeconds by mutableIntStateOf(0); private set
    var isRecordingVoiceNote by mutableStateOf(false); private set
    var usingScaffoldToken by mutableStateOf(false); private set
    var tokenSourceLabel by mutableStateOf("Not connected"); private set
    var peerTypingName by mutableStateOf<String?>(null)
    var activeThreadId by mutableStateOf<String?>(null)
    val messages = mutableStateListOf<ChatMessage>()
    val participants = mutableStateListOf<String>()

    private var room: Room? = null
    private var dataConnected = false
    private var recorder: MediaRecorder? = null
    private var voiceNotePath: String? = null
    private var player: MediaPlayer? = null
    private val localIdentity = "you-${UUID.randomUUID().toString().take(8)}"

    val isConfigured: Boolean get() = AppConfig.isLiveKitConfigured
    val hasScaffoldToken: Boolean get() = AppConfig.hasLiveKitScaffoldToken
    val callTimeLabel: String get() = "%02d:%02d".format(callElapsedSeconds / 60, callElapsedSeconds % 60)

    private fun resolveToken(roomName: String): Pair<String, Boolean>? {
        try {
            val url = URL("${AppConfig.API_BASE_URL.trimEnd('/')}/v1/livekit/token")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                doOutput = true
                connectTimeout = 3500
                readTimeout = 3500
            }
            conn.outputStream.use {
                it.write("""{"room":"$roomName","identity":"$localIdentity","name":"You"}""".toByteArray())
            }
            if (conn.responseCode in 200..299) {
                val body = conn.inputStream.bufferedReader().readText()
                val json = JSONObject(body)
                val token = json.optString("token").ifBlank { json.optString("accessToken") }
                if (token.isNotBlank()) return token to false
            }
        } catch (_: Exception) {
            // Scaffold path expected until token endpoint ships.
        }
        val scaffold = AppConfig.liveKitScaffoldToken
        return if (scaffold.isNotBlank()) scaffold to true else null
    }

    suspend fun connect(asVideo: Boolean, dataOnly: Boolean = false) {
        if (!isConfigured) {
            connectionState = ConnectionState.Error
            statusMessage = "LiveKit URL missing. Set LIVEKIT_URL in local.properties."
            return
        }
        if (dataConnected && room != null && (dataOnly || isInCall)) {
            if (!dataOnly) {
                publishAV(asVideo)
                isInCall = true
                isVideoCall = asVideo
            }
            return
        }
        isVideoCall = asVideo && !dataOnly
        cameraEnabled = isVideoCall
        connectionState = ConnectionState.Connecting
        statusMessage = if (dataOnly) "Connecting messaging (TEST SCAFFOLD)…" else "Connecting…"
        if (!dataOnly) sounds.callInitiated() else sounds.callConnecting()

        val resolved = resolveToken(AppConfig.DEFAULT_LIVEKIT_ROOM)
        if (resolved == null) {
            connectionState = ConnectionState.Error
            statusMessage = "No LiveKit token. Add LIVEKIT_SCAFFOLD_TOKEN in local.properties (TEST SCAFFOLD)."
            sounds.busyOrFailed()
            return
        }
        usingScaffoldToken = resolved.second
        tokenSourceLabel = if (resolved.second) "TEST SCAFFOLD token" else "Server token (/v1/livekit/token)"

        try {
            val r = LiveKit.create(appContext = context.applicationContext)
            r.connect(url = AppConfig.liveKitUrl, token = resolved.first)
            room = r
            dataConnected = true
            connectionState = ConnectionState.Connected
            if (!dataOnly) {
                publishAV(asVideo)
                isInCall = true
                sounds.callConnected()
                statusMessage = if (usingScaffoldToken) {
                    if (asVideo) "Video call connected — TEST SCAFFOLD" else "Voice call connected — TEST SCAFFOLD"
                } else if (asVideo) "Video call connected" else "Voice call connected"
                messages.add(ChatMessage(sender = "System", body = "Joined room via $tokenSourceLabel", isLocal = false))
            } else {
                statusMessage = if (usingScaffoldToken) "Messaging connected — TEST SCAFFOLD" else "Messaging connected"
            }
            participants.clear()
            participants.add("You")
            participants.addAll(r.remoteParticipants.values.map { it.name ?: it.identity?.value ?: "Peer" })
        } catch (e: Exception) {
            connectionState = ConnectionState.Error
            isInCall = false
            dataConnected = false
            room = null
            statusMessage = "Connect failed: ${e.message}"
            sounds.busyOrFailed()
        }
    }

    private suspend fun publishAV(asVideo: Boolean) {
        val r = room ?: return
        try {
            r.localParticipant.setMicrophoneEnabled(micEnabled)
            if (asVideo) {
                r.localParticipant.setCameraEnabled(true)
                cameraEnabled = true
            }
        } catch (e: Exception) {
            statusMessage = "Media publish issue: ${e.message}"
        }
    }

    suspend fun ensureMessagingConnected() {
        if (dataConnected && room != null) return
        connect(asVideo = false, dataOnly = true)
    }

    fun tick() { if (isInCall) callElapsedSeconds += 1 }

    fun disconnect() {
        sounds.hangup()
        scope.launch {
            try {
                room?.localParticipant?.setMicrophoneEnabled(false)
                room?.localParticipant?.setCameraEnabled(false)
                room?.disconnect()
            } catch (_: Exception) {}
            room = null
        }
        dataConnected = false
        connectionState = ConnectionState.Disconnected
        isInCall = false
        cameraEnabled = false
        participants.clear()
        callElapsedSeconds = 0
        usingScaffoldToken = false
        tokenSourceLabel = "Not connected"
        statusMessage = "Call ended / disconnected"
        messages.add(ChatMessage(sender = "System", body = "Left the call", isLocal = false))
    }

    fun endCallKeepMessaging() {
        sounds.hangup()
        scope.launch {
            try {
                room?.localParticipant?.setMicrophoneEnabled(false)
                room?.localParticipant?.setCameraEnabled(false)
            } catch (_: Exception) {}
        }
        isInCall = false
        isVideoCall = false
        cameraEnabled = false
        callElapsedSeconds = 0
        statusMessage = if (usingScaffoldToken) "Call ended — messaging still on TEST SCAFFOLD" else "Call ended — messaging still connected"
    }

    fun toggleMic() {
        micEnabled = !micEnabled
        scope.launch { try { room?.localParticipant?.setMicrophoneEnabled(micEnabled) } catch (_: Exception) {} }
        statusMessage = if (micEnabled) "Microphone on" else "Microphone muted"
    }

    fun toggleCamera() {
        cameraEnabled = !cameraEnabled
        scope.launch { try { room?.localParticipant?.setCameraEnabled(cameraEnabled) } catch (_: Exception) {} }
        statusMessage = if (cameraEnabled) "Camera on" else "Camera off"
    }

    fun sendText(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        messages.add(ChatMessage(sender = "You", body = trimmed, isLocal = true))
        sounds.messageSent()
        val thread = activeThreadId?.let { threadStore.thread(it) }
            ?: threadStore.ensureThread("studio", "Studio")
        scope.launch { sendDMText(trimmed, thread) }
    }

    suspend fun sendDMText(text: String, thread: DMThread) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        ensureMessagingConnected()
        val messageId = UUID.randomUUID().toString()
        val msg = DMMessage(
            id = messageId, threadId = thread.id, senderId = localIdentity, senderName = "You",
            body = trimmed, isLocal = true, receipt = MessageReceipt.SENDING
        )
        threadStore.appendMessage(msg, thread.peerId, thread.peerName)
        val ok = publishJson(
            JSONObject()
                .put("v", 1).put("type", "text").put("threadId", thread.id).put("messageId", messageId)
                .put("senderId", localIdentity).put("senderName", "You").put("body", trimmed)
                .put("sentAt", System.currentTimeMillis() / 1000.0)
        )
        threadStore.updateReceipt(thread.id, messageId, if (ok) MessageReceipt.SENT else MessageReceipt.SENDING)
        if (ok) sounds.messageSent()
    }

    private suspend fun publishJson(obj: JSONObject): Boolean {
        val r = room ?: return false
        return try {
            r.localParticipant.publishData(
                data = obj.toString().toByteArray(Charsets.UTF_8),
                reliability = DataPublishReliability.RELIABLE,
            ).isSuccess
        } catch (_: Exception) {
            false
        }
    }

    fun startVoiceNote() {
        val file = File(context.cacheDir, "vn-${UUID.randomUUID()}.m4a")
        try {
            @Suppress("DEPRECATION")
            recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
            recorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            voiceNotePath = file.absolutePath
            isRecordingVoiceNote = true
            CallHaptics.voiceNotePress(context)
            statusMessage = "Recording voice note"
        } catch (e: Exception) {
            statusMessage = "Could not start voice note: ${e.message}"
            isRecordingVoiceNote = false
        }
    }

    fun stopVoiceNoteAndSend() {
        try { recorder?.stop() } catch (_: Exception) {}
        recorder?.release()
        recorder = null
        isRecordingVoiceNote = false
        val path = voiceNotePath ?: return
        voiceNotePath = null
        messages.add(ChatMessage(sender = "You", body = "Voice note", isLocal = true, isVoiceNote = true, voiceNotePath = path))
        sounds.voiceNoteSent()
        statusMessage = "Voice note sent"
        val thread = activeThreadId?.let { threadStore.thread(it) } ?: threadStore.ensureThread("studio", "Studio")
        val msg = DMMessage(
            threadId = thread.id, senderId = localIdentity, senderName = "You", body = "Voice note",
            isLocal = true, kind = DMKind.VOICE_NOTE, localFilePath = path, attachmentMime = "audio/mp4",
            attachmentName = "voice-note.m4a", receipt = MessageReceipt.SENT
        )
        threadStore.appendMessage(msg, thread.peerId, thread.peerName)
    }

    fun playVoiceNote(path: String) {
        try {
            player?.release()
            player = MediaPlayer().apply {
                setDataSource(path)
                prepare()
                start()
            }
        } catch (_: Exception) {
            statusMessage = "Could not play voice note"
        }
    }
}

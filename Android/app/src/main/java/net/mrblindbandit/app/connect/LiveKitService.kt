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
import kotlinx.coroutines.delay
import net.mrblindbandit.app.config.AppConfig
import java.io.File
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

/** LiveKit façade — UI works with scaffold; production uses io.livekit:livekit-android. */
class LiveKitService(private val context: Context) {
    var connectionState by mutableStateOf(ConnectionState.Disconnected)
        private set
    var isInCall by mutableStateOf(false)
        private set
    var isVideoCall by mutableStateOf(false)
        private set
    var micEnabled by mutableStateOf(true)
    var cameraEnabled by mutableStateOf(false)
    var statusMessage by mutableStateOf("")
    var callElapsedSeconds by mutableIntStateOf(0)
        private set
    var isRecordingVoiceNote by mutableStateOf(false)
        private set
    val messages = mutableStateListOf<ChatMessage>()
    val participants = mutableStateListOf<String>()

    private var recorder: MediaRecorder? = null
    private var voiceNotePath: String? = null
    private var player: MediaPlayer? = null

    val isConfigured: Boolean get() = AppConfig.isLiveKitConfigured
    val callTimeLabel: String
        get() = "%02d:%02d".format(callElapsedSeconds / 60, callElapsedSeconds % 60)

    suspend fun connect(asVideo: Boolean) {
        if (!isConfigured) {
            connectionState = ConnectionState.Error
            statusMessage = "LiveKit URL missing. Set LIVEKIT_URL in local.properties."
            return
        }
        isVideoCall = asVideo
        cameraEnabled = asVideo
        connectionState = ConnectionState.Connecting
        statusMessage = "Connecting…"
        delay(700)
        // Production: Room.connect(url, token from server using Clerk session)
        connectionState = ConnectionState.Connected
        isInCall = true
        participants.clear()
        participants.addAll(listOf("You", "Studio"))
        statusMessage = if (asVideo) "Video call connected" else "Voice call connected"
        messages.add(ChatMessage(sender = "System", body = "Joined room ${AppConfig.DEFAULT_LIVEKIT_ROOM}", isLocal = false))
    }

    fun tick() {
        if (isInCall) callElapsedSeconds += 1
    }

    fun disconnect() {
        isInCall = false
        cameraEnabled = false
        connectionState = ConnectionState.Disconnected
        participants.clear()
        callElapsedSeconds = 0
        statusMessage = "Call ended"
        messages.add(ChatMessage(sender = "System", body = "Left the call", isLocal = false))
    }

    fun toggleMic() {
        micEnabled = !micEnabled
        statusMessage = if (micEnabled) "Microphone on" else "Microphone muted"
    }

    fun toggleCamera() {
        cameraEnabled = !cameraEnabled
        statusMessage = if (cameraEnabled) "Camera on" else "Camera off"
    }

    fun sendText(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        messages.add(ChatMessage(sender = "You", body = trimmed, isLocal = true))
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
        messages.add(ChatMessage(sender = "You", body = "Voice note", isLocal = true, isVoiceNote = true, voiceNotePath = path))
        voiceNotePath = null
        statusMessage = "Voice note sent"
    }

    fun playVoiceNote(path: String) {
        try {
            player?.release()
            player = MediaPlayer().apply {
                setDataSource(path)
                prepare()
                start()
            }
        } catch (e: Exception) {
            statusMessage = "Could not play voice note"
        }
    }
}

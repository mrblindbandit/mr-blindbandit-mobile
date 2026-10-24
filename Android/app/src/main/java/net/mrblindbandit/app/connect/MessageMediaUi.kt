package net.mrblindbandit.app.connect

import android.Manifest
import android.media.MediaDataSource
import android.media.MediaPlayer
import android.media.MediaRecorder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.security.AttachmentCrypto
import java.io.File

@Composable
fun MessageMediaComposer(c: ProductionCommunicationsService, chatId: String, handles: List<String>, group: Boolean = false, onSent: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var recorder by remember { mutableStateOf<MediaRecorder?>(null) }
    var recording by remember { mutableStateOf(false) }
    var file by remember { mutableStateOf<File?>(null) }
    var started by remember { mutableLongStateOf(0L) }
    fun cancel() {
        runCatching { recorder?.stop() }; recorder?.release(); recorder = null
        file?.delete(); file = null; recording = false
    }
    fun send(bytes: ByteArray, mime: String, filename: String, duration: Double? = null) {
        busy = true
        scope.launch {
            try { c.sendAttachment(chatId, handles, group, bytes, mime, filename, duration); status = "Encrypted attachment sent"; onSent() }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) { status = e.localizedMessage.orEmpty() }
            finally { busy = false }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            busy = true
            try {
                val bytes = withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)?.use { readLimited(it, AttachmentCrypto.MAX_SIZE) } ?: error("File cannot be opened") }
                send(bytes, context.contentResolver.getType(uri) ?: "application/octet-stream", "attachment")
            } catch (e: Exception) { status = e.localizedMessage.orEmpty(); busy = false }
        }
    }
    val microphone = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) status = "Microphone permission is needed for voice messages."
        else if (c.isInCall || c.isRinging) status = "End your call before recording a voice message."
        else {
            try {
                val output = File.createTempFile("bb-voice-", ".m4a", context.cacheDir); file = output
                @Suppress("DEPRECATION")
                val r = MediaRecorder()
                recorder = r
                r.setAudioSource(MediaRecorder.AudioSource.MIC); r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC); r.setAudioSamplingRate(24000); r.setAudioChannels(1); r.setAudioEncodingBitRate(64000)
                r.setOutputFile(output.absolutePath); r.setMaxDuration(120_000); r.prepare(); r.start()
                recording = true; started = System.currentTimeMillis(); status = "Recording voice message"
            } catch (e: Exception) { cancel(); status = "Recording could not start." }
        }
    }
    LaunchedEffect(recording) {
        if (recording) { delay(120_000); if (recording) { cancel(); status = "Two-minute recording limit reached. Recording cancelled." } }
    }
    DisposableEffect(Unit) { onDispose { cancel() } }
    Column {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(enabled = !busy && !recording, onClick = { picker.launch(arrayOf("*/*")) }) { Text("Attach file") }
            if (recording) {
                Button(enabled = !busy, onClick = {
                    val duration = (System.currentTimeMillis() - started) / 1000.0
                    val output = file
                    try {
                        recorder?.stop(); recorder?.release(); recorder = null; recording = false
                        if (duration < 0.6) { output?.delete(); status = "Recording too short" }
                        else if (output != null) {
                            scope.launch {
                                try { val bytes = withContext(Dispatchers.IO) { output.readBytes() }; send(bytes, "audio/mp4", "voice.m4a", duration) }
                                finally { output.delete(); file = null }
                            }
                        }
                    } catch (e: Exception) { cancel(); status = "Voice recording could not be saved." }
                }) { Text("Send recording") }
                TextButton(onClick = { cancel(); status = "Recording cancelled" }) { Text("Cancel") }
            } else OutlinedButton(enabled = !busy && !c.isInCall && !c.isRinging, onClick = { microphone.launch(Manifest.permission.RECORD_AUDIO) }) { Text("Record voice") }
        }
        Text(status, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
}

private class BytesAudioSource(private val bytes: ByteArray) : MediaDataSource() {
    override fun getSize() = bytes.size.toLong()
    override fun close() {}
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (position >= bytes.size) return -1
        val count = minOf(size, bytes.size - position.toInt())
        bytes.copyInto(buffer, offset, position.toInt(), position.toInt() + count)
        return count
    }
}

/** Separate controls remain exposed to TalkBack even when the message bubble merges its semantics. */
@Composable
fun MessageMediaActions(message: ServerMessage, c: ProductionCommunicationsService) {
    val media = message.media ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var bytes by remember(message.id) { mutableStateOf<ByteArray?>(null) }
    var status by remember(message.id) { mutableStateOf("") }
    var busy by remember(message.id) { mutableStateOf(false) }
    var playing by remember(message.id) { mutableStateOf(false) }
    var player by remember(message.id) { mutableStateOf<MediaPlayer?>(null) }
    val audio = media.lString("mime").startsWith("audio/")
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument(media.lString("mime").ifBlank { "application/octet-stream" })) { uri ->
        val content = bytes
        if (uri != null && content != null) scope.launch {
            try { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(content) } ?: error("File could not be saved") }; status = "Attachment saved" }
            catch (e: Exception) { status = "Could not save attachment" }
        }
    }
    DisposableEffect(message.id) { onDispose { player?.release(); player = null; bytes?.fill(0) } }
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
        Button(enabled = !busy, modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = if (audio) (if (playing) "Pause voice message" else "Play voice message") else "Save encrypted attachment" }, onClick = {
            scope.launch {
                busy = true
                try {
                    val plain = bytes ?: c.downloadAttachment(media).also { bytes = it }
                    if (audio) {
                        if (playing) { player?.pause(); playing = false }
                        else if (player != null) { player?.start(); playing = true }
                        else {
                            val p = MediaPlayer(); player = p
                            p.setDataSource(BytesAudioSource(plain))
                            p.setOnCompletionListener { playing = false }
                            p.setOnErrorListener { _, _, _ -> playing = false; status = "Audio playback failed"; true }
                            p.prepare(); p.start(); playing = true
                        }
                    } else export.launch(media.lString("filename").ifBlank { "attachment" })
                } catch (e: kotlinx.coroutines.CancellationException) { throw e }
                catch (e: Exception) { status = "Attachment could not be opened or verified." }
                finally { busy = false }
            }
        }) { Text(if (audio) (if (playing) "Pause voice message" else "Play voice message") else "Save attachment") }
        Text(status, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
}

package net.mrblindbandit.app.connect

import android.Manifest
import android.media.MediaRecorder
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
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
import org.json.JSONObject
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
    var listenOnce by remember { mutableStateOf(false) }
    fun cancel() {
        runCatching { recorder?.stop() }; recorder?.release(); recorder = null
        file?.delete(); file = null; recording = false
    }
    fun send(bytes: ByteArray, mime: String, filename: String, duration: Double? = null, once: Boolean = false) {
        busy = true
        scope.launch {
            try {
                c.sendAttachment(chatId, handles, group, bytes, mime, filename, duration, listenOnce = once)
                status = if (once) "Listen-once voice message sent" else "Encrypted attachment sent"
                onSent()
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
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
                Announcer.announce(context, "Recording")
            } catch (e: Exception) { cancel(); status = "Recording could not start." }
        }
    }
    LaunchedEffect(recording) {
        if (recording) { delay(120_000); if (recording) { cancel(); status = "Two-minute recording limit reached. Recording cancelled." } }
    }
    DisposableEffect(Unit) { onDispose { cancel() } }
    Column {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(enabled = !busy && !recording, onClick = { picker.launch(arrayOf("*/*")) }) { Text("Attach file") }
            if (recording) {
                Button(enabled = !busy, onClick = {
                    val duration = (System.currentTimeMillis() - started) / 1000.0
                    val output = file
                    val once = listenOnce
                    try {
                        recorder?.stop(); recorder?.release(); recorder = null; recording = false
                        if (duration < 0.6) { output?.delete(); status = "Recording too short" }
                        else if (output != null) {
                            scope.launch {
                                try { val bytes = withContext(Dispatchers.IO) { output.readBytes() }; send(bytes, "audio/mp4", "voice.m4a", duration, once) }
                                finally { output.delete(); file = null }
                            }
                        }
                    } catch (e: Exception) { cancel(); status = "Voice recording could not be saved." }
                }) { Text("Send recording") }
                TextButton(onClick = { cancel(); status = "Recording cancelled" }) { Text("Cancel") }
            } else OutlinedButton(enabled = !busy && !c.isInCall && !c.isRinging, onClick = { microphone.launch(Manifest.permission.RECORD_AUDIO) }) { Text("Record voice") }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = listenOnce, onCheckedChange = { listenOnce = it }, enabled = !busy)
            Text("Listen once", modifier = Modifier.semantics { contentDescription = "Send as listen-once voice message" })
        }
        Text(status, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
}

/** Separate controls remain exposed to TalkBack even when the message bubble merges its semantics. */
@Composable
fun MessageMediaActions(message: ServerMessage, c: ProductionCommunicationsService) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val voiceRow = VoicePlayback.isVoiceMessage(null, message.media, message.body)
    val media = message.media ?: if (voiceRow) {
        JSONObject().put("mime", "audio/mp4").put("filename", "voice.m4a")
            .put("transcript", message.body).put("alt", "transcript-only")
    } else return
    var bytes by remember(message.id) { mutableStateOf<ByteArray?>(null) }
    var status by remember(message.id) { mutableStateOf("") }
    var busy by remember(message.id) { mutableStateOf(false) }
    var tick by remember { mutableIntStateOf(0) }
    val audio = VoicePlayback.isVoiceMedia(media) || voiceRow
    val listenOnce = media.optBoolean("listen_once") || media.optBoolean("view_once")
    val mine = message.senderId.isNotBlank() && message.senderId == c.myProfileId
    val item = remember(message.id, mine) {
        VoicePlayback.Item(
            id = message.id,
            media = media,
            from = message.senderId,
            mine = mine,
            listenOnce = listenOnce,
        )
    }
    LaunchedEffect(Unit) { VoicePlayback.loadPlayed(context) }
    DisposableEffect(message.id) {
        val listener = { tick += 1 }
        VoicePlayback.addListener(listener)
        VoicePlayback.register(item)
        onDispose {
            VoicePlayback.removeListener(listener)
            bytes?.fill(0)
        }
    }
    val isCurrent = VoicePlayback.isCurrent(message.id)
    val playing = isCurrent && VoicePlayback.playing
    val loading = VoicePlayback.loadingId == message.id
    val elapsed = if (isCurrent) VoicePlayback.elapsedMs else 0L
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument(media.lString("mime").ifBlank { "application/octet-stream" })) { uri ->
        val content = bytes
        if (uri != null && content != null) scope.launch {
            try { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(content) } ?: error("File could not be saved") }; status = "Attachment saved" }
            catch (e: Exception) { status = "Could not save attachment" }
        }
    }
    // keep tick observed so Compose recomposes on player updates
    @Suppress("UNUSED_EXPRESSION")
    tick
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
        if (audio) {
            val durationSec = media.optDouble("duration", 0.0)
            val label = when {
                loading -> "Loading voice message"
                playing -> "Pause voice message"
                isCurrent -> "Resume voice message"
                else -> "Play voice message"
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(
                    enabled = !busy && !loading,
                    modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = label },
                    onClick = {
                        scope.launch {
                            busy = true
                            try {
                                VoicePlayback.toggle(context, item) { m ->
                                    c.downloadAttachment(m).also { bytes = it }
                                }
                            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
                            catch (e: Exception) { status = "Attachment could not be opened or verified." }
                            finally { busy = false }
                        }
                    },
                ) { Text(if (playing) "Pause" else if (loading) "…" else "Play") }
                TextButton(
                    enabled = !busy,
                    onClick = { VoicePlayback.cycleRate(context) },
                    modifier = Modifier.semantics { contentDescription = "Playback speed ${VoicePlayback.rateLabel()}" },
                ) { Text(VoicePlayback.rateLabel()) }
                if (isCurrent) {
                    TextButton(onClick = { VoicePlayback.skip(context, -5) }, modifier = Modifier.semantics { contentDescription = "Skip back 5 seconds" }) { Text("−5s") }
                    TextButton(onClick = { VoicePlayback.skip(context, 5) }, modifier = Modifier.semantics { contentDescription = "Skip forward 5 seconds" }) { Text("+5s") }
                }
            }
            val clock = buildString {
                append(VoicePlayback.clock(elapsed / 1000.0))
                if (durationSec > 0) append(" / ").append(VoicePlayback.clock(durationSec))
                if (listenOnce) append(" · once")
                if (!mine && VoicePlayback.wasPlayed(message.id)) append(" · played")
            }
            Text(clock, style = MaterialTheme.typography.bodySmall)
        } else {
            Button(
                enabled = !busy,
                modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = "Save encrypted attachment" },
                onClick = {
                    scope.launch {
                        busy = true
                        try {
                            val plain = bytes ?: c.downloadAttachment(media).also { bytes = it }
                            export.launch(media.lString("filename").ifBlank { "attachment" })
                            @Suppress("UNUSED_VARIABLE") val _keep = plain
                        } catch (e: kotlinx.coroutines.CancellationException) { throw e }
                        catch (e: Exception) { status = "Attachment could not be opened or verified." }
                        finally { busy = false }
                    }
                },
            ) { Text("Save attachment") }
        }
        Text(status, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
}

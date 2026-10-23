package net.mrblindbandit.app.connect

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.speech.tts.TextToSpeech
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import net.mrblindbandit.app.ui.Feedback
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** Haptics that honour Settings > Accessibility > Haptic feedback. */
class Haptics(private val feedback: Feedback, private val enabled: () -> Boolean) {
    fun tap() = feedback.tap(enabled())
    fun success() = feedback.success(enabled())
}

@Composable
fun rememberHaptics(enabled: () -> Boolean): Haptics {
    val context = LocalContext.current
    return remember { Haptics(Feedback(context), enabled) }
}

/** Text-to-speech for "Read aloud", with its own speed. Works alongside TalkBack (explicit user action). */
class ReadAloud(context: Context) {
    private var ready = false
    private var queued: String? = null
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        ready = status == TextToSpeech.SUCCESS
        if (ready) { tts.language = Locale.getDefault(); queued?.let { speakNow(it) }; queued = null }
    }
    var rate: Float = 1.0f

    fun speak(text: String) { if (ready) speakNow(text) else queued = text }
    private fun speakNow(text: String) {
        tts.setSpeechRate(rate)
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "bb-read-aloud")
    }
    fun stop() { runCatching { tts.stop() } }
    fun shutdown() { runCatching { tts.shutdown() } }
}

@Composable
fun rememberReadAloud(): ReadAloud {
    val context = LocalContext.current
    val engine = remember { ReadAloud(context) }
    DisposableEffect(engine) { onDispose { engine.shutdown() } }
    return engine
}

fun copyText(context: Context, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    cm.setPrimaryClip(ClipData.newPlainText("Message", text))
    Announcer.announce(context, "Copied")
}

fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    runCatching { context.startActivity(Intent.createChooser(send, "Share message").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

fun timeLabel(ms: Long): String {
    if (ms <= 0) return ""
    val d = Date(ms)
    val today = System.currentTimeMillis() - ms < 20 * 3600_000L
    return if (today) DateFormat.getTimeInstance(DateFormat.SHORT).format(d) else DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(d)
}

/** Reusable failure view: plain message plus a Retry button. */
@Composable
fun ErrorRetry(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(message, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        Button(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp)) { Text("Retry") }
    }
}

@Composable
fun CenteredText(text: String) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Text(text, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

val REPORT_REASONS = listOf("Harassment or bullying", "Spam or scam", "Hate speech", "Sexual or explicit content", "Threats or violence", "Impersonation", "Something else")

data class ReportTarget(val type: String, val id: String, val label: String)

/** Report dialog for a person, message, call or comment. */
@Composable
fun ReportDialog(target: ReportTarget, communications: ProductionCommunicationsService, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var reason by remember { mutableStateOf(REPORT_REASONS.first()) }
    var details by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text("Report ${target.label}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Choose a reason")
                REPORT_REASONS.forEach { option ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .selectable(selected = reason == option, onClick = { reason = option }, role = Role.RadioButton),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = reason == option, onClick = null)
                        Text(option, Modifier.padding(start = 8.dp))
                    }
                }
                OutlinedTextField(details, { details = it.take(2000) }, label = { Text("Details (optional)") }, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = {
            TextButton(enabled = !sending, onClick = {
                sending = true
                scope.launch {
                    communications.report(target.type, target.id, reason, details)
                    Announcer.announce(context, communications.statusMessage)
                    sending = false
                    onDone()
                }
            }) { Text(if (sending) "Sending…" else "Send report") }
        },
        dismissButton = { TextButton(onClick = onDone) { Text("Cancel") } },
    )
}

@Composable
fun BlockDialog(name: String, handle: String, communications: ProductionCommunicationsService, onDone: (Boolean) -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = { onDone(false) },
        title = { Text("Block $name?") },
        text = { Text("They will no longer be able to message or call you. You can unblock them in Blocked accounts.") },
        confirmButton = {
            TextButton(onClick = {
                scope.launch {
                    val ok = communications.blockUser(handle)
                    Announcer.announce(context, communications.statusMessage)
                    onDone(ok)
                }
            }) { Text("Block") }
        },
        dismissButton = { TextButton(onClick = { onDone(false) }) { Text("Cancel") } },
    )
}

@Composable
fun rememberCommunications(auth: net.mrblindbandit.app.auth.ClerkAuthService): ProductionCommunicationsService {
    val context = LocalContext.current
    return remember(auth) { ProductionCommunicationsService(context, auth) }
}

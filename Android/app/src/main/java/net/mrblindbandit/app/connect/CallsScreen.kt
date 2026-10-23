package net.mrblindbandit.app.connect

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Calls tab: dial by @username, in-call controls, incoming call, favourites and history. */
@Composable
fun CallsTab(
    communications: ProductionCommunicationsService,
    haptics: Haptics,
    signedIn: Boolean,
    dialRequest: Pair<String, Boolean>?,
    onDialHandled: () -> Unit,
    onMessage: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var handle by remember { mutableStateOf("") }
    var missedOnly by remember { mutableStateOf(false) }
    var report by remember { mutableStateOf<ReportTarget?>(null) }
    var pendingCall by remember { mutableStateOf<Pair<String, Boolean>?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val call = pendingCall ?: return@rememberLauncherForActivityResult
        pendingCall = null
        if (result[Manifest.permission.RECORD_AUDIO] == true || hasPermission(context, Manifest.permission.RECORD_AUDIO)) {
            scope.launch { communications.startCall(call.first, call.second) }
        } else {
            communications.statusMessage = "Microphone permission is needed to make calls."
            Announcer.announce(context, communications.statusMessage)
        }
    }
    fun dial(target: String, video: Boolean) {
        if (normalizeHandle(target).isBlank()) { Announcer.announce(context, "Enter a username first."); return }
        haptics.tap()
        val needed = buildList {
            if (!hasPermission(context, Manifest.permission.RECORD_AUDIO)) add(Manifest.permission.RECORD_AUDIO)
            if (video && !hasPermission(context, Manifest.permission.CAMERA)) add(Manifest.permission.CAMERA)
        }
        if (needed.isEmpty()) scope.launch { communications.startCall(target, video) }
        else { pendingCall = target to video; permissionLauncher.launch(needed.toTypedArray()) }
    }

    LaunchedEffect(dialRequest) { dialRequest?.let { dial(it.first, it.second); onDialHandled() } }
    LaunchedEffect(signedIn) { if (signedIn) communications.loadCallHistory() }
    LaunchedEffect(communications.isInCall) {
        while (communications.isInCall) { delay(1000); communications.tick() }
        if (signedIn) communications.loadCallHistory()
    }

    if (!signedIn) { CenteredText("Sign in from the Home tab to make and receive calls."); return }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
        item {
            Text("Calls", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp, 8.dp).semantics { heading() })
        }
        communications.incomingCallId?.let { callId ->
            item {
                Surface(color = MaterialTheme.colorScheme.tertiaryContainer, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().padding(16.dp, 8.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Incoming call", fontWeight = FontWeight.Bold, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(onClick = {
                                haptics.success()
                                if (hasPermission(context, Manifest.permission.RECORD_AUDIO)) scope.launch { communications.joinCall(callId) }
                                else permissionLauncher.launch(arrayOf(Manifest.permission.RECORD_AUDIO)).also { scope.launch { communications.joinCall(callId) } }
                            }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Answer") }
                            Button(onClick = { haptics.tap(); scope.launch { communications.declineCall(callId) } },
                                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error), modifier = Modifier.heightIn(min = 48.dp)) { Text("Decline") }
                        }
                    }
                }
            }
        }
        if (communications.isRinging || communications.isInCall) {
            item { ActiveCallPanel(communications, haptics) }
        } else {
            item {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(handle, { handle = it }, singleLine = true, label = { Text("Call @username") }, modifier = Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Button(onClick = { dial(handle, false) }, modifier = Modifier.heightIn(min = 48.dp)) {
                            Icon(Icons.Default.Call, null); Text("Voice call", Modifier.padding(start = 8.dp))
                        }
                        FilledTonalButton(onClick = { dial(handle, true) }, modifier = Modifier.heightIn(min = 48.dp)) {
                            Icon(Icons.Default.Videocam, null); Text("Video call", Modifier.padding(start = 8.dp))
                        }
                    }
                    if (communications.statusMessage.isNotBlank()) {
                        Text(communications.statusMessage, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                    }
                }
            }
        }
        if (communications.favorites.isNotEmpty()) {
            item { Text("Favourites", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(16.dp, 12.dp, 16.dp, 4.dp).semantics { heading() }) }
            item {
                LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(communications.favorites) { fav ->
                        AssistChip(onClick = { dial(fav, false) }, label = { Text("@$fav") },
                            leadingIcon = { Icon(Icons.Default.Call, null) },
                            modifier = Modifier.semantics { contentDescription = "Call favourite @$fav" })
                    }
                }
            }
        }
        item {
            Row(Modifier.padding(16.dp, 12.dp, 16.dp, 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Recent calls", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f).semantics { heading() })
                FilterChip(selected = !missedOnly, onClick = { missedOnly = false }, label = { Text("All") })
                FilterChip(selected = missedOnly, onClick = { missedOnly = true }, label = { Text("Missed") })
            }
        }
        val state = communications.historyState
        val rows = communications.callHistory.filter { !missedOnly || it.isMissed }
        when {
            state is LoadState.Failed && communications.callHistory.isEmpty() ->
                item { ErrorRetry(state.message, { scope.launch { communications.loadCallHistory() } }) }
            (state is LoadState.Loading || state is LoadState.Idle) && communications.callHistory.isEmpty() ->
                item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading call history" }) } }
            rows.isEmpty() -> item { CenteredText(if (missedOnly) "No missed calls." else "No calls yet.") }
            else -> items(rows, key = { it.id }) { call ->
                CallRow(call, communications, onCallBack = { dial(call.peerHandle, call.isVideo) }, onMessage = { onMessage(call.peerHandle) }, onReport = { report = ReportTarget("call", call.id, "this call") })
                HorizontalDivider()
            }
        }
    }
    report?.let { t -> ReportDialog(t, communications) { report = null } }
}

@Composable
private fun CallRow(call: CallRecord, communications: ProductionCommunicationsService, onCallBack: () -> Unit, onMessage: () -> Unit, onReport: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val state = call.stateLabel()
    val favourite = call.peerHandle in communications.favorites
    val duration = call.durationSeconds?.let { s -> if (s >= 60) "${s / 60} min ${s % 60} s" else "$s s" }
    val description = listOfNotNull(
        call.peerName.ifBlank { "@${call.peerHandle}" },
        (if (call.isIncoming) "Incoming " else "Outgoing ") + (if (call.isVideo) "video call" else "voice call"),
        state, duration, timeLabel(call.createdAt),
    ).joinToString(", ")
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).clickable(enabled = call.peerHandle.isNotBlank(), onClickLabel = "Call back", onClick = onCallBack)
            .semantics(mergeDescendants = true) { contentDescription = description }.padding(vertical = 8.dp)) {
            Text(call.peerName.ifBlank { "@${call.peerHandle}" }, fontWeight = FontWeight.SemiBold,
                color = if (call.isMissed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
            Text(listOfNotNull(if (call.isVideo) "Video" else "Voice", state, duration, timeLabel(call.createdAt)).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (call.peerHandle.isNotBlank()) {
            IconButton(onClick = onCallBack) { Icon(Icons.Default.Call, contentDescription = "Call back ${call.peerName}") }
            IconButton(onClick = { communications.toggleFavorite(call.peerHandle) }) {
                Icon(if (favourite) Icons.Default.Star else Icons.Default.StarBorder,
                    contentDescription = if (favourite) "Remove ${call.peerName} from favourites" else "Add ${call.peerName} to favourites")
            }
        }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, contentDescription = "More options for call with ${call.peerName}") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                if (call.peerHandle.isNotBlank()) DropdownMenuItem(text = { Text("Message") }, onClick = { menu = false; onMessage() })
                DropdownMenuItem(text = { Text("Report call") }, onClick = { menu = false; onReport() })
            }
        }
    }
}

@Composable
private fun ActiveCallPanel(communications: ProductionCommunicationsService, haptics: Haptics) {
    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth().padding(16.dp, 8.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val status = if (communications.isRinging) "Ringing ${communications.callPeerName}…" else "In call with ${communications.callPeerName}, ${communications.callTimeLabel}"
            Text(status, style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { if (communications.isRinging) liveRegion = LiveRegionMode.Polite })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(onClick = { haptics.tap(); communications.toggleMic() },
                    modifier = Modifier.heightIn(min = 48.dp).semantics { stateDescription = if (communications.micEnabled) "Microphone on" else "Muted" }) {
                    Text(if (communications.micEnabled) "Mute" else "Unmute")
                }
                FilledTonalButton(onClick = { haptics.tap(); communications.toggleSpeaker() },
                    modifier = Modifier.heightIn(min = 48.dp).semantics { stateDescription = if (communications.speakerOn) "Speaker on" else "Speaker off" }) {
                    Text("Speaker")
                }
                FilledTonalButton(onClick = { haptics.tap(); communications.toggleCamera() },
                    modifier = Modifier.heightIn(min = 48.dp).semantics { stateDescription = if (communications.cameraEnabled) "Camera on" else "Camera off" }) {
                    Text("Camera")
                }
            }
            Button(onClick = { haptics.tap(); communications.endCall() }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                Icon(Icons.Default.CallEnd, null); Text("End call", Modifier.padding(start = 8.dp))
            }
        }
    }
}

private fun hasPermission(context: android.content.Context, permission: String) =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

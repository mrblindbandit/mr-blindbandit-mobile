package net.mrblindbandit.app.connect

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.RadioButton
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.brand.BlindbanditLogo
import net.mrblindbandit.app.brand.SpinningBrandLogo

@Composable
fun ConnectHubScreen(
    auth: ClerkAuthService,
    reduceMotion: Boolean,
    communications: ProductionCommunicationsService = rememberCommunications(auth),
) {
    val context = LocalContext.current
    val sounds = remember { CallSounds(context) }
    val scope = rememberCoroutineScope()
    var tab by remember { mutableIntStateOf(0) }
    var callRecipient by remember { mutableStateOf("") }
    var messageRecipient by remember { mutableStateOf("") }
    var messageDraft by remember { mutableStateOf("") }
    var replyDraft by remember { mutableStateOf("") }
    var selectedConversation by remember { mutableStateOf<ServerConversation?>(null) }
    var keypadDigits by remember { mutableStateOf("") }

    var pendingVoiceRecipient by remember { mutableStateOf<String?>(null) }
    var pendingVideoRecipient by remember { mutableStateOf<String?>(null) }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val target = pendingVoiceRecipient
        pendingVoiceRecipient = null
        if (granted && !target.isNullOrBlank()) scope.launch {
            sounds.callInitiated()
            communications.startCall(target, false)
            if (communications.isInCall) sounds.callConnected() else sounds.busyOrFailed()
        }
    }
    val camMicPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val target = pendingVideoRecipient
        pendingVideoRecipient = null
        val granted = result[Manifest.permission.CAMERA] == true && result[Manifest.permission.RECORD_AUDIO] == true
        if (granted && !target.isNullOrBlank()) scope.launch {
            sounds.callInitiated()
            communications.startCall(target, true)
            if (communications.isInCall) sounds.callConnected() else sounds.busyOrFailed()
        }
    }

    fun startVoice(recipient: String) {
        val target = recipient.trim()
        if (target.isBlank()) {
            communications.statusMessage = "Enter the person's Blindbandit username first."
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            scope.launch {
                sounds.callInitiated()
                communications.startCall(target, false)
                if (communications.isInCall) sounds.callConnected() else sounds.busyOrFailed()
            }
        } else {
            pendingVoiceRecipient = target
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    fun startVideo(recipient: String) {
        val target = recipient.trim()
        if (target.isBlank()) {
            communications.statusMessage = "Enter the person's Blindbandit username first."
            return
        }
        val mic = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val camera = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        if (mic && camera) {
            scope.launch {
                sounds.callInitiated()
                communications.startCall(target, true)
                if (communications.isInCall) sounds.callConnected() else sounds.busyOrFailed()
            }
        } else {
            pendingVideoRecipient = target
            camMicPermissions.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
        }
    }

    LaunchedEffect(Unit) { communications.bootstrap() }
    LaunchedEffect(communications.isInCall) {
        while (communications.isInCall) {
            delay(1000)
            communications.tick()
        }
    }

    Column(Modifier.fillMaxSize()) {
        ScrollableTabRow(selectedTabIndex = tab) {
            listOf("Calls", "Messages").forEachIndexed { index, label ->
                Tab(selected = tab == index, onClick = { tab = index }, text = { Text(label) })
            }
        }

        if (communications.statusMessage.isNotBlank()) {
            Text(
                communications.statusMessage,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { contentDescription = communications.statusMessage }
            )
        }

        when (tab) {
            0 -> CallsPane(
                communications = communications,
                sounds = sounds,
                reduceMotion = reduceMotion,
                recipient = callRecipient,
                onRecipientChange = { callRecipient = it },
                onVoice = { startVoice(callRecipient) },
                onVideo = { startVideo(callRecipient) },
            )
            else -> MessagesPane(
                communications = communications,
                selectedConversation = selectedConversation,
                onSelectConversation = { conversation ->
                    selectedConversation = conversation
                    scope.launch { communications.openConversation(conversation.id) }
                },
                onBack = { selectedConversation = null },
                recipient = messageRecipient,
                onRecipientChange = { messageRecipient = it },
                draft = messageDraft,
                onDraftChange = { messageDraft = it },
                replyDraft = replyDraft,
                onReplyDraftChange = { replyDraft = it },
                onSendNew = {
                    val target = messageRecipient
                    val text = messageDraft
                    scope.launch {
                        val id = communications.sendMessage(target, text)
                        if (id != null) {
                            sounds.messageSent()
                            messageDraft = ""
                            selectedConversation = communications.conversations.firstOrNull { it.id == id }
                            communications.openConversation(id)
                        }
                    }
                },
                onSendReply = { conversation ->
                    val text = replyDraft
                    scope.launch {
                        val id = communications.sendMessage(conversation.peerHandle, text)
                        if (id != null) {
                            sounds.messageSent()
                            replyDraft = ""
                            communications.openConversation(conversation.id)
                        }
                    }
                },
                onCall = { conversation ->
                    callRecipient = conversation.peerHandle
                    tab = 0
                },
                onRefresh = { scope.launch { communications.refreshConversations() } },
            )
        }
    }
}

@Composable
private fun CallsPane(
    communications: ProductionCommunicationsService,
    sounds: CallSounds,
    reduceMotion: Boolean,
    recipient: String,
    onRecipientChange: (String) -> Unit,
    onVoice: () -> Unit,
    onVideo: () -> Unit,
) {
    LazyColumn(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column(
                Modifier.fillMaxWidth().background(Color.Black, RoundedCornerShape(24.dp)).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (communications.isInCall) {
                    SpinningBrandLogo(88.dp, reduceMotion)
                    Text(communications.callPeerName.ifBlank { "Blindbandit call" }, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 22.sp,
                        modifier = Modifier.semantics { heading() })
                    Text(communications.callTimeLabel, color = Color(0xFFFFD54F), fontSize = 28.sp,
                        modifier = Modifier.semantics { contentDescription = "Call duration ${communications.callTimeLabel}" })
                    Text(if (communications.isVideoCall) "Video call" else "Voice call", color = Color.White.copy(alpha = 0.72f))
                } else {
                    BlindbanditLogo(96.dp)
                    Text("Blindbandit Calling", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                    Text("Call anyone on Blindbandit by their username", color = Color.White.copy(alpha = 0.72f), textAlign = TextAlign.Center)
                }
            }
        }

        if (!communications.isInCall) {
            item {
                Card {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Call someone", fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                        OutlinedTextField(
                            recipient,
                            onRecipientChange,
                            label = { Text("Email address or Blindbandit username") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                onClick = onVoice,
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFD54F), contentColor = Color.Black),
                            ) { Icon(Icons.Default.Call, null); Text(" Voice call") }
                            OutlinedButton(onClick = onVideo, modifier = Modifier.weight(1f)) {
                                Icon(Icons.Default.Videocam, null); Text(" Video call")
                            }
                        }
                    }
                }
            }
        } else {
            item {
                Card {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                            IconButton(onClick = { communications.toggleMic() }, modifier = Modifier.size(64.dp)) {
                                Icon(if (communications.micEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                                    if (communications.micEnabled) "Mute" else "Unmute")
                            }
                            if (communications.isVideoCall) {
                                IconButton(onClick = { communications.toggleCamera() }, modifier = Modifier.size(64.dp)) {
                                    Icon(if (communications.cameraEnabled) Icons.Default.Videocam else Icons.Default.VideocamOff,
                                        if (communications.cameraEnabled) "Turn camera off" else "Turn camera on")
                                }
                            }
                            IconButton(onClick = { communications.endCall(); sounds.hangup() }, modifier = Modifier.size(64.dp)) {
                                Icon(Icons.Default.CallEnd, "End call", tint = Color.Red)
                            }
                        }
                    }
                }
            }
        }

        item {
            Card {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Safety", fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                    Text(
                        "Open any conversation to block or report someone. Reports go to the Blindbandit safety team, and blocked people can no longer message or call you.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun MessagesPane(
    communications: ProductionCommunicationsService,
    selectedConversation: ServerConversation?,
    onSelectConversation: (ServerConversation) -> Unit,
    onBack: () -> Unit,
    recipient: String,
    onRecipientChange: (String) -> Unit,
    draft: String,
    onDraftChange: (String) -> Unit,
    replyDraft: String,
    onReplyDraftChange: (String) -> Unit,
    onSendNew: () -> Unit,
    onSendReply: (ServerConversation) -> Unit,
    onCall: (ServerConversation) -> Unit,
    onRefresh: () -> Unit,
) {
    if (selectedConversation != null) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TextButtonLike("Back", onBack)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(selectedConversation.peerName, fontWeight = FontWeight.Bold)
                    Text("@${selectedConversation.peerHandle}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                }
                Row {
                    IconButton(onClick = { onCall(selectedConversation) }, modifier = Modifier.size(48.dp)) { Icon(Icons.Default.Call, "Call ${selectedConversation.peerName}") }
                    SafetyMenu(communications, selectedConversation, onBack)
                }
            }
            HorizontalDivider()
            LazyColumn(
                Modifier.weight(1f).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(communications.messages, key = { it.id }) { message ->
                    val mine = message.senderId == communications.myProfileId
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
                        Text(
                            message.body,
                            modifier = Modifier
                                .background(
                                    if (mine) Color(0x44FFD54F) else MaterialTheme.colorScheme.surfaceVariant,
                                    RoundedCornerShape(14.dp),
                                )
                                .padding(10.dp)
                                .semantics { contentDescription = if (mine) "You: ${message.body}" else message.body },
                        )
                    }
                }
            }
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(replyDraft, onReplyDraftChange, modifier = Modifier.weight(1f), label = { Text("Message") })
                IconButton(onClick = { onSendReply(selectedConversation) }, enabled = replyDraft.trim().isNotEmpty()) {
                    Icon(Icons.Default.Send, "Send reply")
                }
            }
        }
    } else {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    recipient,
                    onRecipientChange,
                    label = { Text("Blindbandit username") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                )
                OutlinedTextField(draft, onDraftChange, label = { Text("Message") }, modifier = Modifier.fillMaxWidth())
                Button(
                    onClick = onSendNew,
                    enabled = recipient.trim().isNotEmpty() && draft.trim().isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFD54F), contentColor = Color.Black),
                ) { Icon(Icons.Default.Send, null); Text(" Send message") }
            }
            HorizontalDivider()
            Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Conversations", fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                OutlinedButton(onClick = onRefresh) { Text("Refresh") }
            }
            if (communications.isLoading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (communications.conversations.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                    Text("No conversations yet. Start one by entering a Blindbandit username above.", textAlign = TextAlign.Center)
                }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(communications.conversations, key = { it.id }) { conversation ->
                        androidx.compose.material3.TextButton(
                            onClick = { onSelectConversation(conversation) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.Start) {
                                Text(conversation.peerName, fontWeight = FontWeight.Bold)
                                Text(conversation.lastBody.ifBlank { "No messages yet" }, maxLines = 1, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun rememberCommunications(auth: ClerkAuthService): ProductionCommunicationsService {
    val context = LocalContext.current
    return remember(auth) { ProductionCommunicationsService(context, auth) }
}

@Composable
private fun SafetyMenu(
    communications: ProductionCommunicationsService,
    conversation: ServerConversation,
    onBlocked: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var menuOpen by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf(false) }
    var reportOpen by remember { mutableStateOf(false) }
    var reason by remember { mutableStateOf(REPORT_REASONS.first()) }
    var details by remember { mutableStateOf("") }

    Box {
        IconButton(onClick = { menuOpen = true }, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Default.MoreVert, "Safety options for ${conversation.peerName}")
        }
        androidx.compose.material3.DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            androidx.compose.material3.DropdownMenuItem(text = { Text("Report ${conversation.peerName}") }, onClick = { menuOpen = false; reportOpen = true })
            androidx.compose.material3.DropdownMenuItem(text = { Text("Block ${conversation.peerName}") }, onClick = { menuOpen = false; confirmBlock = true })
        }
    }
    if (confirmBlock) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmBlock = false },
            title = { Text("Block ${conversation.peerName}?") },
            text = { Text("They will no longer be able to message or call you. You can unblock them later on mrblindbandit.net.") },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    confirmBlock = false
                    scope.launch { if (communications.blockUser(conversation.peerHandle)) onBlocked() }
                }) { Text("Block") }
            },
            dismissButton = { androidx.compose.material3.TextButton(onClick = { confirmBlock = false }) { Text("Cancel") } },
        )
    }
    if (reportOpen) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { reportOpen = false },
            title = { Text("Report ${conversation.peerName}") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Why are you reporting this conversation?")
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
                androidx.compose.material3.TextButton(onClick = {
                    reportOpen = false
                    scope.launch {
                        communications.report("profile", conversation.peerHandle, reason, details)
                        details = ""
                    }
                }) { Text("Send report") }
            },
            dismissButton = { androidx.compose.material3.TextButton(onClick = { reportOpen = false }) { Text("Cancel") } },
        )
    }
}

private val REPORT_REASONS = listOf("Harassment or bullying", "Spam or scam", "Hate speech", "Sexual or explicit content", "Threats or violence", "Something else")

@Composable
private fun TextButtonLike(text: String, onClick: () -> Unit) {
    androidx.compose.material3.TextButton(onClick = onClick) { Text(text) }
}

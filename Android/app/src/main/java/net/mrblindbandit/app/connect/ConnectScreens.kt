package net.mrblindbandit.app.connect

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import net.mrblindbandit.app.brand.BlindbanditLogo
import net.mrblindbandit.app.brand.SpinningBrandLogo
import net.mrblindbandit.app.brand.WaveformLoader
import net.mrblindbandit.app.config.AppConfig

@Composable
fun ConnectHubScreen(reduceMotion: Boolean) {
    val context = LocalContext.current
    val livekit = remember { LiveKitService(context) }
    var tab by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val camPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }

    LaunchedEffect(livekit.isInCall) {
        while (livekit.isInCall) {
            delay(1000)
            livekit.tick()
        }
    }

    fun ensureMic(then: () -> Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
        then()
    }

    Column(Modifier.fillMaxSize()) {
        ScrollableTabRow(selectedTabIndex = tab) {
            listOf("Calls", "Chat", "Voice notes").forEachIndexed { i, label ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(label) })
            }
        }
        when (tab) {
            0 -> Column(Modifier.padding(16.dp).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(
                    Modifier.fillMaxWidth().background(Color.Black, RoundedCornerShape(24.dp)).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    if (livekit.isInCall) {
                        SpinningBrandLogo(88.dp, reduceMotion)
                        Text(if (livekit.isVideoCall) "Video call" else "Voice call", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 22.sp,
                            modifier = Modifier.semantics { heading() })
                        Text(livekit.callTimeLabel, color = Color(0xFFFFD54F), fontSize = 28.sp,
                            modifier = Modifier.semantics { contentDescription = "Call duration ${livekit.callTimeLabel}" })
                    } else {
                        BlindbanditLogo(96.dp)
                        Text("Studio line", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 22.sp)
                        Text(
                            if (livekit.isConfigured) "Ready to connect via LiveKit" else "Configure LiveKit URL to go live",
                            color = Color.White.copy(0.7f)
                        )
                    }
                }
                if (livekit.statusMessage.isNotBlank()) Text(livekit.statusMessage, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = { ensureMic { scope.launch { livekit.connect(false) } } },
                        enabled = !livekit.isInCall,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFD54F), contentColor = Color.Black),
                        modifier = Modifier.weight(1f).semantics { contentDescription = "Start voice call" }
                    ) { Icon(Icons.Default.Call, null); Text(" Voice") }
                    Button(
                        onClick = {
                            if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                                camPermission.launch(Manifest.permission.CAMERA)
                            }
                            ensureMic { scope.launch { livekit.connect(true) } }
                        },
                        enabled = !livekit.isInCall,
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Black, contentColor = Color(0xFFFFD54F)),
                        modifier = Modifier.weight(1f).semantics { contentDescription = "Start video call" }
                    ) { Icon(Icons.Default.Videocam, null); Text(" Video") }
                }
                if (livekit.isInCall) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        IconButton(onClick = { livekit.toggleMic() }, modifier = Modifier.size(56.dp)) {
                            Icon(if (livekit.micEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                                if (livekit.micEnabled) "Mute" else "Unmute")
                        }
                        IconButton(onClick = { livekit.disconnect() }, modifier = Modifier.size(56.dp)) {
                            Icon(Icons.Default.CallEnd, "End call", tint = Color.Red)
                        }
                    }
                }
                Text("Room: ${AppConfig.DEFAULT_LIVEKIT_ROOM} · ${livekit.connectionState}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            1 -> {
                var draft by remember { mutableStateOf("") }
                Column(Modifier.fillMaxSize()) {
                    LazyColumn(Modifier.weight(1f).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(livekit.messages, key = { it.id }) { msg ->
                            Text("${msg.sender}: ${msg.body}", modifier = Modifier.semantics {
                                contentDescription = "${msg.sender}: ${msg.body}"
                            })
                        }
                    }
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(draft, { draft = it }, modifier = Modifier.weight(1f), label = { Text("Message") })
                        IconButton(onClick = { livekit.sendText(draft); draft = "" },
                            enabled = draft.isNotBlank(),
                            modifier = Modifier.semantics { contentDescription = "Send message" }) {
                            Icon(Icons.Default.Send, null)
                        }
                    }
                }
            }
            else -> Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Record a voice note and send it into studio chat.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(
                    onClick = {
                        if (livekit.isRecordingVoiceNote) livekit.stopVoiceNoteAndSend()
                        else ensureMic { livekit.startVoiceNote() }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (livekit.isRecordingVoiceNote) Color.Red else Color(0xFFFFD54F),
                        contentColor = if (livekit.isRecordingVoiceNote) Color.White else Color.Black
                    ),
                    modifier = Modifier.fillMaxWidth().height(56.dp)
                ) {
                    Text(if (livekit.isRecordingVoiceNote) "Stop & send voice note" else "Record voice note", fontWeight = FontWeight.Bold)
                }
                if (livekit.isRecordingVoiceNote) {
                    WaveformLoader(reduceMotion)
                    Text("Recording…", fontWeight = FontWeight.SemiBold)
                }
                LazyColumn {
                    items(livekit.messages.filter { it.isVoiceNote }, key = { it.id }) { note ->
                        Button(onClick = { note.voiceNotePath?.let { livekit.playVoiceNote(it) } }, modifier = Modifier.fillMaxWidth()) {
                            Text("Play voice note from ${note.sender}")
                        }
                    }
                }
            }
        }
    }
}

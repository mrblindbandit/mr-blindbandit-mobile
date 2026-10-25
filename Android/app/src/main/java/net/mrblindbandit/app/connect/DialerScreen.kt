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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Backspace
import androidx.compose.material.icons.filled.Call
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch

/** Calls-tab Dialer — landline keypad with US dial tone + DTMF (iOS TF 39 parity). */
@Composable
fun DialerScreen(
    communications: ProductionCommunicationsService,
    haptics: Haptics,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val directory = remember { CallNumberDirectory(context) }
    val sounds = communications.callSoundsPublic
    var digits by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var placing by remember { mutableStateOf(false) }
    var showNotFound by remember { mutableStateOf(false) }
    var pendingPlace by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && pendingPlace) {
            pendingPlace = false
            placeCall(digits, directory, communications, sounds, haptics, scope,
                setPlacing = { placing = it }, setStatus = { status = it }, setNotFound = { showNotFound = it })
        } else {
            pendingPlace = false
            if (!granted) {
                status = "Microphone permission is needed to make calls."
                Announcer.announce(context, status)
            }
        }
    }

    DisposableEffect(Unit) {
        status = ""
        sounds.openDialerIdleTone()
        Announcer.announce(context, "Dialer. Dial tone.")
        onDispose {
            if (!placing) sounds.closeDialer()
        }
    }

    val keys = listOf(
        listOf("1" to "", "2" to "ABC", "3" to "DEF"),
        listOf("4" to "GHI", "5" to "JKL", "6" to "MNO"),
        listOf("7" to "PQRS", "8" to "TUV", "9" to "WXYZ"),
        listOf("*" to "", "0" to "+", "#" to ""),
    )

    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("Back") }
            Text("Dialer", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
        }
        Spacer(Modifier.height(16.dp))
        Text(
            if (digits.isEmpty()) " " else formatDialDisplay(digits),
            fontSize = 34.sp,
            fontWeight = FontWeight.Light,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .semantics {
                    contentDescription = if (digits.isEmpty()) "No number entered" else "Number ${digits.toCharArray().joinToString(" ")}"
                },
        )
        if (status.isNotBlank()) {
            Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(12.dp))
        keys.forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                row.forEach { (label, letters) ->
                    DialKey(label, letters) {
                        digits += label
                        status = ""
                        sounds.dialerKeyPress(label)
                        haptics.tap()
                        Announcer.announce(context, when (label) { "*" -> "Star"; "#" -> "Pound"; else -> label })
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
        }
        Spacer(Modifier.height(8.dp))
        Row(
            Modifier.fillMaxWidth().padding(bottom = 24.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(72.dp))
            IconButton(
                enabled = digits.isNotEmpty() && !placing,
                onClick = {
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        pendingPlace = true
                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    } else {
                        placeCall(digits, directory, communications, sounds, haptics, scope,
                            setPlacing = { placing = it }, setStatus = { status = it }, setNotFound = { showNotFound = it })
                    }
                },
                modifier = Modifier
                    .size(76.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
                    .semantics { contentDescription = "Call" },
            ) {
                Icon(Icons.Default.Call, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(32.dp))
            }
            IconButton(
                enabled = digits.isNotEmpty(),
                onClick = {
                    digits = digits.dropLast(1)
                    haptics.tap()
                    if (digits.isEmpty()) {
                        sounds.openDialerIdleTone()
                        status = ""
                    }
                },
                modifier = Modifier.size(72.dp).semantics { contentDescription = "Delete" },
            ) {
                Icon(Icons.Default.Backspace, contentDescription = null)
            }
        }
    }

    if (showNotFound) {
        AlertDialog(
            onDismissRequest = { showNotFound = false },
            confirmButton = {
                TextButton(onClick = {
                    showNotFound = false
                    sounds.busyOrFailed()
                }) { Text("OK") }
            },
            title = { Text("Number not found") },
            text = {
                Text("No BlindBandit profile is assigned to ${formatDialDisplay(digits)}. Set a call number in settings, or ask them for theirs.")
            },
        )
    }
}

@Composable
private fun DialKey(label: String, letters: String, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier
            .size(76.dp)
            .semantics {
                contentDescription = when (label) {
                    "*" -> "Star"
                    "#" -> "Pound"
                    else -> if (letters.isBlank()) label else "$label, $letters"
                }
            },
    ) {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text(label, fontSize = 28.sp, fontWeight = FontWeight.Medium)
            Text(if (letters.isEmpty()) " " else letters, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun formatDialDisplay(raw: String): String {
    val d = raw.filter { it.isDigit() }
    return when {
        d.length == 10 -> "(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}"
        d.length == 11 && d.startsWith("1") -> "+1 (${d.substring(1, 4)}) ${d.substring(4, 7)}-${d.substring(7)}"
        else -> raw
    }
}

private fun placeCall(
    digits: String,
    directory: CallNumberDirectory,
    communications: ProductionCommunicationsService,
    sounds: CallSounds,
    haptics: Haptics,
    scope: kotlinx.coroutines.CoroutineScope,
    setPlacing: (Boolean) -> Unit,
    setStatus: (String) -> Unit,
    setNotFound: (Boolean) -> Unit,
) {
    val normalized = directory.normalize(digits)
    if (normalized.isEmpty()) return
    setPlacing(true)
    setStatus("Looking up…")
    sounds.closeDialer()
    scope.launch {
        val handle = directory.resolve(normalized)
            ?: runCatching {
                val resolved = communications.resolveCallNumber(normalized)
                directory.assign(resolved.third, resolved.first)
                resolved.first
            }.getOrNull()
        if (handle.isNullOrBlank()) {
            setPlacing(false)
            setNotFound(true)
            sounds.busyOrFailed()
            setStatus("Not found")
            return@launch
        }
        setStatus("Calling @$handle…")
        haptics.success()
        communications.startCall(handle, video = false)
        setPlacing(false)
    }
}

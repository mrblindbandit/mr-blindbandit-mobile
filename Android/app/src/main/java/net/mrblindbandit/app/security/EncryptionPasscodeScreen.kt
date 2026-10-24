package net.mrblindbandit.app.security

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import net.mrblindbandit.app.connect.Announcer
import net.mrblindbandit.app.connect.ProductionCommunicationsService
import net.mrblindbandit.app.connect.lString
import org.json.JSONObject

/** Create or restore encryption passcode backup (PUT/GET /v1/keys/backup). */
@Composable
fun EncryptionPasscodeScreen(c: ProductionCommunicationsService, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf("loading") } // loading | create | restore
    var backup by remember { mutableStateOf(JSONObject()) }
    var pass by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    val handle = c.myHandle

    fun say(s: String) { status = s; Announcer.announce(context, s) }

    LaunchedEffect(Unit) {
        try {
            val raw = c.request("/v1/keys/backup", "GET", null)
            val inner = raw.optJSONObject("data") ?: raw
            if (inner.has("ciphertext") || inner.has("blob")) {
                backup = inner; mode = "restore"
            } else mode = "create"
        } catch (_: Exception) { mode = "create" }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TextButton(onClick = onBack) { Text("Back") }
        Text("Encryption passcode", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
        when (mode) {
            "loading" -> CircularProgressIndicator()
            "create" -> {
                Text("Use 6 or more digits or letters. It protects a server backup of your Android encryption keys. We can't see your passcode or reset it for you. Android and iPhone backups are not interchangeable because each platform stores keys differently.")
                OutlinedTextField(pass, { pass = it.take(128) }, label = { Text("Passcode") },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(confirm, { confirm = it.take(128) }, label = { Text("Enter it again") },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth())
                Button(
                    enabled = !busy && EncryptionPasscode.isValid(pass) && pass == confirm,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            busy = true
                            try {
                                val engine = c.encryption?.engine ?: error("Encryption keys aren't ready yet.")
                                val body = EncryptionPasscode.seal(engine.exportIdentity(), pass)
                                c.request("/v1/keys/backup", "PUT", body)
                                EncryptionPasscode.markSet(context, handle)
                                pass = ""; confirm = ""
                                say("Encryption passcode created.")
                            } catch (e: Exception) { say("Couldn't save the backup: ${e.localizedMessage ?: "error"}") }
                            finally { busy = false }
                        }
                    },
                ) { Text("Create passcode") }
            }
            "restore" -> {
                Text("This restores your encryption keys so contacts' security numbers stay the same on this Android device.")
                OutlinedTextField(pass, { pass = it.take(128) }, label = { Text("Encryption passcode") },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth())
                Button(enabled = !busy && pass.length >= 6, modifier = Modifier.fillMaxWidth(), onClick = {
                    scope.launch {
                        busy = true
                        try {
                            val data = EncryptionPasscode.open(backup, pass) ?: run {
                                say("That passcode didn't work. Try again."); return@launch
                            }
                            val engine = c.encryption?.engine ?: error("Encryption is not ready.")
                            val current = engine.exportIdentity()
                            if (!data.contentEquals(current)) {
                                if (!engine.importIdentity(data)) { say("The backup couldn't be read."); return@launch }
                                c.encryption?.bootstrap()
                            }
                            EncryptionPasscode.markSet(context, handle)
                            pass = ""
                            say("Your encryption keys are restored. Your security numbers stay the same.")
                        } catch (e: Exception) { say(e.localizedMessage ?: "Restore failed.") }
                        finally { busy = false }
                    }
                }) { Text("Restore my keys") }
                TextButton(onClick = { confirmReset = true }) { Text("Forgot passcode — reset keys") }
            }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        Text(status, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text("Reset encryption keys?") },
            text = { Text("Resetting creates a new security number. Contacts will see that your number changed, and old encrypted messages may not open on this phone.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmReset = false
                    scope.launch {
                        busy = true
                        try {
                            c.encryption?.engine?.resetIdentity()
                            EncryptionPasscode.clearSet(context, handle)
                            c.encryption?.bootstrap()
                            mode = "create"; pass = ""; confirm = ""
                            say("New keys created. Now create a new encryption passcode.")
                        } catch (e: Exception) { say(e.localizedMessage ?: "Reset failed.") }
                        finally { busy = false }
                    }
                }) { Text("Reset keys") }
            },
            dismissButton = { TextButton(onClick = { confirmReset = false }) { Text("Cancel") } },
        )
    }
}

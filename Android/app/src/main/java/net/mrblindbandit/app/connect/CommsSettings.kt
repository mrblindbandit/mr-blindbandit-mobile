package net.mrblindbandit.app.connect

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.launch

/** Process-wide unlock flag: the lock asks only on a cold launch, not on every resume. */
object AppLock {
    @Volatile var unlockedThisProcess = false
    private const val AUTHENTICATORS = BIOMETRIC_WEAK or DEVICE_CREDENTIAL

    fun available(activity: FragmentActivity) =
        BiometricManager.from(activity).canAuthenticate(AUTHENTICATORS) == BiometricManager.BIOMETRIC_SUCCESS

    fun prompt(activity: FragmentActivity, title: String, onResult: (Boolean, String) -> Unit) {
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onResult(true, "")
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = onResult(false, errString.toString())
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("Use your fingerprint, face or screen lock")
            .setAllowedAuthenticators(AUTHENTICATORS)
            .build()
        runCatching { prompt.authenticate(info) }.onFailure { onResult(false, it.message ?: "Unlock is unavailable.") }
    }
}

@Composable
fun AppLockScreen(activity: FragmentActivity, onUnlocked: () -> Unit) {
    var message by remember { mutableStateOf("") }
    val context = LocalContext.current
    fun ask() {
        if (!AppLock.available(activity)) { onUnlocked(); return } // Lock removed from the device: never trap the user.
        AppLock.prompt(activity, "Unlock Mr. Blindbandit") { ok, err ->
            if (ok) onUnlocked() else { message = err.ifBlank { "Not unlocked." }; Announcer.announce(context, message) }
        }
    }
    LaunchedEffect(Unit) { ask() }
    Box(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(24.dp)) {
            Text("Mr. Blindbandit is locked", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            if (message.isNotBlank()) Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = { ask() }, modifier = Modifier.heightIn(min = 56.dp)) { Text("Unlock") }
        }
    }
}

/** Settings section: read receipts (synced), read aloud speed, app lock and blocked accounts. */
@Composable
fun CommsSettingsSection(communications: ProductionCommunicationsService, activity: FragmentActivity, haptics: Haptics) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var lockOn by remember { mutableStateOf(communications.local.appLockEnabled) }
    var speed by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { communications.loadSettings() }
    Column(Modifier.fillMaxWidth()) {
        Text("Messages & calls", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(vertical = 8.dp).semantics { heading() })
        Text(communications.encryptionStatus)
        var hidePreviews by remember { mutableStateOf(context.getSharedPreferences(net.mrblindbandit.app.AndroidAppPreferences.FILE, android.content.Context.MODE_PRIVATE).getBoolean("hideMessagePreviews", true)) }
        SettingSwitch("Hide message previews in notifications", hidePreviews) { value ->
            hidePreviews = value
            context.getSharedPreferences(net.mrblindbandit.app.AndroidAppPreferences.FILE, android.content.Context.MODE_PRIVATE).edit().putBoolean("hideMessagePreviews", value).apply()
        }
        SettingSwitch("Send read receipts", communications.shareReadReceipts) { on ->
            haptics.tap()
            scope.launch { communications.setShareReadReceipts(on); Announcer.announce(context, communications.statusMessage) }
        }
        SettingSwitch("Require unlock when the app opens", lockOn) { on ->
            if (on && !AppLock.available(activity)) {
                Announcer.announce(context, "Set up a fingerprint, face or screen lock on this device first.")
                return@SettingSwitch
            }
            AppLock.prompt(activity, if (on) "Turn on app lock" else "Turn off app lock") { ok, _ ->
                if (ok) { communications.local.appLockEnabled = on; lockOn = on; AppLock.unlockedThisProcess = true; haptics.success() }
            }
        }
        Text("Read aloud speed: ${"%.1f".format(communications.local.readAloudRate)}×",
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { speed = true }.padding(vertical = 12.dp))
        Text("Blocked accounts", Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { blocked = true }.padding(vertical = 12.dp))
    }
    if (speed) ReadAloudSpeedDialog(communications.local.readAloudRate) { communications.local.readAloudRate = it; speed = false }
    if (blocked) AlertDialog(
        onDismissRequest = { blocked = false },
        confirmButton = { TextButton(onClick = { blocked = false }) { Text("Close") } },
        text = { Box(Modifier.heightIn(max = 480.dp)) { BlockedAccountsScreen(communications, haptics) { blocked = false } } },
    )
}

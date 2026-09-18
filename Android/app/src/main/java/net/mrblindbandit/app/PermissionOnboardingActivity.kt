package net.mrblindbandit.app

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import net.mrblindbandit.app.brand.BlindbanditLogo

/**
 * One-time permission primer shown before Android runtime dialogs.
 * It explains every requested permission in plain language and never blocks the app if declined.
 */
class PermissionOnboardingActivity : ComponentActivity() {
    private val prefs by lazy { getSharedPreferences("blindbandit_permissions", MODE_PRIVATE) }

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        prefs.edit().putBoolean("initialPermissionsAsked", true).apply()
        openApp()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (prefs.getBoolean("initialPermissionsAsked", false)) {
            openApp()
            return
        }
        setContent {
            MaterialTheme {
                PermissionPrimer(
                    onContinue = { requestInitialPermissions() },
                    onNotNow = {
                        prefs.edit().putBoolean("initialPermissionsAsked", true).apply()
                        openApp()
                    }
                )
            }
        }
    }

    private fun requestInitialPermissions() {
        val permissions = buildList {
            add(Manifest.permission.RECORD_AUDIO)
            add(Manifest.permission.CAMERA)
            if (Build.VERSION.SDK_INT >= 31) add(Manifest.permission.BLUETOOTH_CONNECT)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        permissionLauncher.launch(permissions.toTypedArray())
    }

    private fun openApp() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            data = intent?.data
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        })
        finish()
    }
}

@Composable
private fun PermissionPrimer(onContinue: () -> Unit, onNotNow: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        BlindbanditLogo(104.dp)
        Text(
            "Set up permissions",
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = 24.dp).semantics { heading() },
        )
        Text(
            "Mr. Blind Bandit uses the microphone for voice calls and voice notes, the camera for video calls, Bluetooth access for wireless call audio, and notifications for messages and incoming-call alerts. You can change every choice later in Android Settings.",
            modifier = Modifier.padding(vertical = 18.dp),
            textAlign = TextAlign.Center,
        )
        Button(onClick = onContinue, modifier = Modifier.fillMaxWidth()) {
            Text("Continue and choose permissions")
        }
        Button(onClick = onNotNow, modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) {
            Text("Not now")
        }
        Text(
            "Declining a permission only disables the feature that needs it.",
            modifier = Modifier.padding(top = 16.dp),
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
        )
    }
}

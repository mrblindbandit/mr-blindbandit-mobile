package net.mrblindbandit.app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import net.mrblindbandit.app.auth.AuthState
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.brand.BlindbanditLogo

@Composable
fun MoreHubScreen(
    auth: ClerkAuthService,
    onOpenSite: (String) -> Unit,
    onOpenSettings: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            BlindbanditLogo(56.dp)
            Text("More", fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            when (val s = auth.state) {
                is AuthState.SignedIn -> {
                    Text(s.displayName, fontWeight = FontWeight.SemiBold)
                    Text(s.email, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                else -> Text("Not signed in", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/account") }, modifier = Modifier.fillMaxWidth()) { Text("Manage account") } }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/portal/") }, modifier = Modifier.fillMaxWidth()) { Text("Label portal") } }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/") }, modifier = Modifier.fillMaxWidth()) { Text("Website home") } }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/music/") }, modifier = Modifier.fillMaxWidth()) { Text("Music") } }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/store/") }, modifier = Modifier.fillMaxWidth()) { Text("Store") } }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/support/") }, modifier = Modifier.fillMaxWidth()) { Text("Support") } }
        item { Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/about/") }, modifier = Modifier.fillMaxWidth()) { Text("About") } }
        item { Button(onClick = onOpenSettings, modifier = Modifier.fillMaxWidth()) { Text("Settings") } }
        item {
            Button(
                onClick = { scope.launch { auth.signOut() } },
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Sign out") }
        }
        item {
            TextButton(onClick = {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://mrblindbandit.net/privacy/")))
            }) { Text("Privacy Policy", color = Color(0xFFFFD54F)) }
        }
        item {
            TextButton(onClick = {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://mrblindbandit.net/terms/")))
            }) { Text("Terms of Use", color = Color(0xFFFFD54F)) }
        }
        item {
            TextButton(onClick = {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, "https://mrblindbandit.net/")
                }
                context.startActivity(Intent.createChooser(send, "Share"))
            }) { Text("Share website") }
        }
    }
}

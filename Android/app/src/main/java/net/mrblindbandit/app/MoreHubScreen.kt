package net.mrblindbandit.app

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import net.mrblindbandit.app.auth.AuthState
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.brand.BlindbanditLogo
import net.mrblindbandit.app.ui.Spacing

@Composable
fun MoreHubScreen(
    auth: ClerkAuthService,
    onOpenSite: (String) -> Unit,
    onOpenSettings: () -> Unit,
) {
    val context = LocalContext.current
    val base = BuildConfig.WEB_BASE_URL
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        item {
            Row(Modifier.fillMaxWidth().padding(top = Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                BlindbanditLogo(56.dp)
                Spacer(Modifier.width(Spacing.md))
                Column(Modifier.semantics(mergeDescendants = true) {}) {
                    Text("More", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.semantics { heading() })
                    when (val s = auth.state) {
                        is AuthState.SignedIn -> Text("Signed in as ${s.displayName}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        else -> Text("Not signed in", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        item {
            Group("Your account") {
                Entry(Icons.Default.Settings, "Settings", onOpenSettings)
                Entry(Icons.Default.AccountCircle, "Profile & account") { onOpenSite("$base/account") }
            }
        }
        item {
            Group("Blindbandit Records") {
                Entry(Icons.Default.MusicNote, "Music") { onOpenSite("$base/music/") }
                Entry(Icons.Default.ShoppingBag, "Store") { onOpenSite("$base/store/") }
                Entry(Icons.Default.Groups, "Community") { onOpenSite("$base/community/") }
                Entry(Icons.Default.Business, "Label portal") { onOpenSite("$base/portal/") }
                Entry(Icons.Default.Info, "About Mr. Blindbandit") { onOpenSite("$base/about/") }
                Entry(Icons.Default.SupportAgent, "Help & support") { onOpenSite("$base/support/") }
            }
        }
        item {
            Group("Share") {
                Entry(Icons.Default.Share, "Share mrblindbandit.net") {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, "$base/")
                    }
                    context.startActivity(Intent.createChooser(send, "Share mrblindbandit.net"))
                }
            }
        }
        item { Spacer(Modifier.heightIn(min = Spacing.lg)) }
    }
}

@Composable
private fun Group(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = Spacing.sm)) {
            Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = Spacing.md, vertical = Spacing.sm).semantics { heading() })
            HorizontalDivider()
            content()
        }
    }
}

@Composable
private fun Entry(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(Spacing.md))
        Text(label, style = MaterialTheme.typography.bodyLarge)
    }
}

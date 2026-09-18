package net.mrblindbandit.app

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import net.mrblindbandit.app.brand.BlindbanditLogo

data class MusicService(val name: String, val url: String, val sitePath: String, val subtitle: String)

@Composable
fun ListenHubScreen(onOpenSite: (String) -> Unit, prefs: AndroidAppPreferences) {
    val context = LocalContext.current
    val services = listOf(
        MusicService("Spotify", "https://open.spotify.com/search/Mr%20Blind%20Bandit", "/music/", "Open Spotify or browse on the site"),
        MusicService("Apple Music", "https://music.apple.com/search?term=Mr%20Blind%20Bandit", "/music/", "Open Apple Music"),
        MusicService("Amazon Music", "https://music.amazon.com/search/Mr%20Blind%20Bandit", "/music/", "Amazon Music search"),
        MusicService("Audiomack", "https://audiomack.com/search?q=Mr%20Blind%20Bandit", "/music/", "Audiomack search"),
        MusicService("YouTube Music", "https://music.youtube.com/search?q=Mr%20Blind%20Bandit", "/music/", "YouTube Music search"),
        MusicService("SoundCloud", "https://soundcloud.com/search?q=Mr%20Blind%20Bandit", "/music/", "SoundCloud search"),
        MusicService("Tidal", "https://listen.tidal.com/search?q=Mr%20Blind%20Bandit", "/music/", "Tidal search"),
        MusicService("Blindbandit catalog", "https://mrblindbandit.net/music/", "/music/", "Official releases")
    )
    var favorites by remember { mutableStateOf(prefs.listenFavorites) }
    var status by remember { mutableStateOf("") }

    LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                BlindbanditLogo(56.dp)
                Column(Modifier.padding(start = 12.dp)) {
                    Text("Listen", fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                    Text("Stream Blindbandit Records across major services.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        item {
            Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + "/music/") }, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFD54F), contentColor = Color.Black)) {
                Text("Music on mrblindbandit.net")
            }
        }
        items(services) { service ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(service.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        IconButton(onClick = {
                            favorites = if (service.name in favorites) favorites - service.name else favorites + service.name
                            prefs.setListenFavorites(favorites)
                        }, modifier = Modifier.semantics {
                            contentDescription = if (service.name in favorites) "Unpin ${service.name}" else "Pin ${service.name}"
                        }) {
                            Icon(if (service.name in favorites) Icons.Filled.Star else Icons.Outlined.Star, null, tint = Color(0xFFFFD54F))
                        }
                    }
                    Text(service.subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = {
                            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(service.url))) }
                                .onFailure { status = "Could not open ${service.name}. Use Browse site." }
                        }) { Text("Open service") }
                        Button(onClick = { onOpenSite(BuildConfig.WEB_BASE_URL + service.sitePath) }) { Text("Browse site") }
                    }
                }
            }
        }
        if (status.isNotBlank()) item { Text(status, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item {
            Text("Pinned", fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
            if (favorites.isEmpty()) Text("Star a service to pin it on this device.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            else favorites.forEach { Text("★ $it", color = Color(0xFFFFD54F)) }
        }
    }
}

package net.mrblindbandit.app.profile

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.connect.Announcer
import net.mrblindbandit.app.connect.ProductionCommunicationsService
import net.mrblindbandit.app.ui.Spacing
import java.net.HttpURLConnection
import java.net.URL

/** Public HTTPS avatar (not E2EE). Falls back to initials. */
@Composable
fun ProfileAvatar(url: String?, displayName: String, size: Dp = 40.dp, modifier: Modifier = Modifier) {
    var bitmap by remember(url) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(url) {
        bitmap = null
        val u = url?.trim().orEmpty()
        if (u.startsWith("https://")) {
            bitmap = withContext(Dispatchers.IO) {
                runCatching {
                    val conn = (URL(u).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 8_000; readTimeout = 8_000; instanceFollowRedirects = true
                    }
                    try { conn.inputStream.use { BitmapFactory.decodeStream(it) } } finally { conn.disconnect() }
                }.getOrNull()
            }
        }
    }
    val initials = displayName.trim().split(Regex("\\s+")).take(2).mapNotNull { it.firstOrNull()?.uppercaseChar()?.toString() }.joinToString("").ifBlank { "?" }
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer)
            .semantics { contentDescription = if (bitmap != null) "Profile photo of $displayName" else "Avatar initials $initials for $displayName" },
        contentAlignment = Alignment.Center,
    ) {
        val bmp = bitmap
        if (bmp != null) {
            Image(bmp.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(size).clip(CircleShape))
        } else {
            Text(initials, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
        }
    }
}

/** Settings: choose / remove public profile picture via PUT /v1/social/me/avatar. */
@Composable
fun ProfilePictureEditor(communications: ProductionCommunicationsService) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            status = "Uploading…"
            try {
                val jpeg = withContext(Dispatchers.IO) {
                    val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("Could not read photo")
                    // Re-encode lightly as JPEG if needed — server expects image/jpeg.
                    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: error("Not a valid image")
                    val out = java.io.ByteArrayOutputStream()
                    val scaled = if (bmp.width > 1024 || bmp.height > 1024) {
                        val scale = 1024f / maxOf(bmp.width, bmp.height)
                        android.graphics.Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt().coerceAtLeast(1), (bmp.height * scale).toInt().coerceAtLeast(1), true)
                    } else bmp
                    scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
                    out.toByteArray()
                }
                communications.uploadPublicAvatar(jpeg)
                status = "Profile picture updated"
                Announcer.announce(context, status)
            } catch (e: Exception) {
                status = e.localizedMessage?.takeIf { it.isNotBlank() } ?: "Could not upload profile picture"
                Announcer.announce(context, status)
            } finally { busy = false }
        }
    }
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text("Profile picture", style = MaterialTheme.typography.titleMedium)
        Text(
            "Visible on your Blindbandit profile. Not end-to-end encrypted.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
            ProfileAvatar(
                url = communications.myAvatarUrl.ifBlank { null },
                displayName = communications.myDisplayName.ifBlank { communications.myHandle.ifBlank { "You" } },
                size = 64.dp,
            )
            Spacer(Modifier.width(Spacing.md))
            Column {
                OutlinedButton(enabled = !busy, onClick = { picker.launch("image/*") }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(if (busy) "Uploading…" else "Choose photo")
                }
                if (communications.myAvatarUrl.isNotBlank()) {
                    TextButton(enabled = !busy, onClick = {
                        scope.launch {
                            busy = true
                            try {
                                communications.clearPublicAvatar()
                                status = "Profile picture removed"
                                Announcer.announce(context, status)
                            } catch (e: Exception) {
                                status = e.localizedMessage.orEmpty().ifBlank { "Could not remove photo" }
                            } finally { busy = false }
                        }
                    }) { Text("Remove photo") }
                }
            }
        }
        if (status.isNotBlank()) Text(status, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

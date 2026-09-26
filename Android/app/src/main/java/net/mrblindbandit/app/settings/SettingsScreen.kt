package net.mrblindbandit.app.settings

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.CookieManager
import android.webkit.WebStorage
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.launch
import net.mrblindbandit.app.AndroidAppPreferences
import net.mrblindbandit.app.BuildConfig
import net.mrblindbandit.app.auth.AccountDeletionService
import net.mrblindbandit.app.auth.AuthState
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.config.AppConfig
import net.mrblindbandit.app.ui.Appearance
import net.mrblindbandit.app.ui.Spacing

private enum class SettingsPage { ROOT, LICENSES }

/**
 * Full settings menu. Every toggle is persisted through [AndroidAppPreferences].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    prefs: AndroidAppPreferences,
    auth: ClerkAuthService,
    onBack: () -> Unit,
    onOpenWeb: (String) -> Unit,
    onRequestNotifications: () -> Unit,
) {
    var page by remember { mutableStateOf(SettingsPage.ROOT) }
    androidx.activity.compose.BackHandler { if (page == SettingsPage.LICENSES) page = SettingsPage.ROOT else onBack() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (page == SettingsPage.ROOT) "Settings" else "Open-source licenses", modifier = Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(onClick = { if (page == SettingsPage.LICENSES) page = SettingsPage.ROOT else onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { inner ->
        when (page) {
            SettingsPage.ROOT -> SettingsRoot(prefs, auth, onOpenWeb, onRequestNotifications, onLicenses = { page = SettingsPage.LICENSES }, modifier = Modifier.padding(inner))
            SettingsPage.LICENSES -> LicensesList(Modifier.padding(inner))
        }
    }
}

@Composable
private fun SettingsRoot(
    prefs: AndroidAppPreferences,
    auth: ClerkAuthService,
    onOpenWeb: (String) -> Unit,
    onRequestNotifications: () -> Unit,
    onLicenses: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmSignOut by remember { mutableStateOf(false) }
    var deleteConfirmText by remember { mutableStateOf("") }
    val notificationsAllowed = net.mrblindbandit.app.rememberNotificationsEnabled()

    LazyColumn(
        modifier.fillMaxSize().padding(horizontal = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        item { Spacer(Modifier.heightIn(min = Spacing.sm)) }

        item {
            Section("Account & profile") {
                when (val s = auth.state) {
                    is AuthState.SignedIn -> {
                        Text(s.displayName, style = MaterialTheme.typography.titleMedium)
                        if (s.email.isNotBlank()) Text(s.email, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    else -> Text("Not signed in")
                }
                LinkRow("Edit profile on mrblindbandit.net") { onOpenWeb(BuildConfig.WEB_BASE_URL + "/account") }
                OutlinedButton(onClick = { confirmSignOut = true }, modifier = Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch), enabled = !auth.busy) {
                    Text("Sign out")
                }
                Button(
                    onClick = { deleteConfirmText = ""; confirmDelete = true },
                    modifier = Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch),
                    enabled = !auth.busy,
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError),
                ) { Text("Delete account") }
                Text(
                    "Deleting your account permanently removes your Blindbandit profile, messages, call history, devices, and sign-in account. You can also request deletion at mrblindbandit.net/account/delete.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (auth.busy) CircularProgressIndicator(Modifier.semantics { stateDescription = "Working" })
                if (auth.statusMessage.isNotBlank()) Text(auth.statusMessage, color = MaterialTheme.colorScheme.primary)
            }
        }

        item {
            Section("Notifications") {
                Text(
                    if (notificationsAllowed) "Notifications are allowed for this app." else "Notifications are turned off for this app.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (!notificationsAllowed) {
                    Button(onClick = onRequestNotifications, modifier = Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch)) { Text("Turn on notifications") }
                }
                ToggleRow("New messages", prefs.notifyMessages, "Alert me when someone messages me", prefs::setNotifyMessages)
                ToggleRow("Incoming calls", prefs.notifyCalls, "Alert me when someone calls me", prefs::setNotifyCalls)
                LinkRow("Open system notification settings") { openAppNotificationSettings(context) }
            }
        }

        item {
            Section("Accessibility") {
                ToggleRow("Haptic feedback", prefs.hapticsEnabled, "Vibration for taps, calls, and messages", prefs::setHapticsEnabled)
                ToggleRow("Speech feedback", prefs.speechFeedback, "Speak call and message status out loud. TalkBack users hear these as announcements.", prefs::setSpeechFeedback)
                Text("Speech rate: ${"%.1f".format(prefs.speechRate)}×", style = MaterialTheme.typography.bodyLarge)
                Slider(
                    value = prefs.speechRate,
                    onValueChange = { prefs.setSpeechRate((it * 10).toInt() / 10f) },
                    valueRange = 0.5f..2.0f,
                    steps = 14,
                    modifier = Modifier.semantics { stateDescription = "${"%.1f".format(prefs.speechRate)} times normal speed" },
                )
                ToggleRow("High contrast", prefs.highContrast, "Pure black and white surfaces with stronger outlines", prefs::setHighContrast)
                ToggleRow("Reduce motion", prefs.reduceMotion, "Stop animated logos and loaders", prefs::setReduceMotion)
                ToggleRow("Announce page loads", prefs.announcePageLoads, "Say when a website page finishes loading", prefs::setAnnouncePageLoads)
                ToggleRow("Keep screen awake", prefs.keepScreenAwake, "Prevent the screen from sleeping while the app is open", prefs::setKeepScreenAwake)
                LinkRow("Android accessibility settings") { safeStart(context, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
            }
        }

        item {
            Section("Sounds & calls") {
                ToggleRow("App sounds", prefs.uiSounds, "Ringback, connect, and message sounds", prefs::setUiSounds)
                ToggleRow("Start video calls with camera off", prefs.startCallsWithCameraOff, "Turn your camera on when you are ready", prefs::setStartCallsWithCameraOff)
                ToggleRow("Use speakerphone by default", prefs.speakerphoneByDefault, "Route call audio to the loudspeaker", prefs::setSpeakerphoneByDefault)
                ToggleRow("Echo cancellation", prefs.echoCancellation, "Reduce echo during calls", prefs::setEchoCancellation)
                ToggleRow("Noise suppression", prefs.noiseSuppression, "Reduce background noise during calls", prefs::setNoiseSuppression)
            }
        }

        item {
            Section("Appearance") {
                Column(Modifier.selectableGroup()) {
                    Appearance.entries.forEach { option ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch)
                                .selectable(selected = prefs.appearance == option, onClick = { prefs.setAppearance(option) }, role = Role.RadioButton),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = prefs.appearance == option, onClick = null)
                            Spacer(Modifier.width(Spacing.sm))
                            Text(option.label, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
        }

        item {
            Section("Privacy & data") {
                ToggleRow("Allow third-party cookies", prefs.allowThirdPartyCookies, "Needed by some sign-in and payment pages on the website", prefs::setAllowThirdPartyCookies)
                ToggleRow("Autoplay website media", prefs.mediaAutoplay, "Let website audio and video start without a tap", prefs::setMediaAutoplay)
                Text("Website text size: ${prefs.textZoom}%", style = MaterialTheme.typography.bodyLarge)
                Slider(
                    value = prefs.textZoom.toFloat(),
                    onValueChange = { prefs.setTextZoom(it.toInt()) },
                    valueRange = 75f..200f,
                    modifier = Modifier.semantics { stateDescription = "${prefs.textZoom} percent" },
                )
                OutlinedButton(onClick = {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    WebStorage.getInstance().deleteAllData()
                    android.widget.Toast.makeText(context, "Website cookies and storage cleared.", android.widget.Toast.LENGTH_SHORT).show()
                }, modifier = Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch)) { Text("Clear website data on this device") }
                LinkRow("App permissions") { safeStart(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))) }
                LinkRow("Privacy Policy") { openExternal(context, AppConfig.PRIVACY_URL) }
            }
        }

        item {
            Section("Legal") {
                LinkRow("Privacy Policy") { openExternal(context, AppConfig.PRIVACY_URL) }
                LinkRow("Terms of Use") { openExternal(context, AppConfig.TERMS_URL) }
                LinkRow("Accessibility statement") { openExternal(context, AppConfig.ACCESSIBILITY_URL) }
                LinkRow("Open-source licenses", external = false, onClick = onLicenses)
            }
        }

        item {
            Section("Support & contact") {
                LinkRow("Email ${AppConfig.SUPPORT_EMAIL}") {
                    val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${AppConfig.SUPPORT_EMAIL}")).apply {
                        putExtra(Intent.EXTRA_SUBJECT, "Mr. Blindbandit Android ${BuildConfig.VERSION_NAME} support")
                    }
                    safeStart(context, intent)
                }
                LinkRow("Help center") { openExternal(context, AppConfig.SUPPORT_URL) }
            }
        }

        item {
            Section("About") {
                Text("Mr. Blindbandit for Android", style = MaterialTheme.typography.titleMedium)
                Text("Version ${BuildConfig.VERSION_NAME} (build ${BuildConfig.VERSION_CODE})", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Made by Blindbandit Records for artists, fans, and creators.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                LinkRow("mrblindbandit.net") { openExternal(context, BuildConfig.WEB_BASE_URL) }
            }
        }
        item { Spacer(Modifier.heightIn(min = Spacing.xl)) }
    }

    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false },
            title = { Text("Sign out?") },
            text = { Text("You will need to sign in again to use calls and messages.") },
            confirmButton = { TextButton(onClick = { confirmSignOut = false; scope.launch { auth.signOut() } }) { Text("Sign out") } },
            dismissButton = { TextButton(onClick = { confirmSignOut = false }) { Text("Cancel") } },
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete your account permanently?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text("This deletes your Blindbandit profile, messages, call history, registered devices, and your sign-in account. This cannot be undone.")
                    Text("Type DELETE to confirm.")
                    OutlinedTextField(deleteConfirmText, { deleteConfirmText = it }, singleLine = true, label = { Text("Confirmation") })
                }
            },
            confirmButton = {
                TextButton(
                    enabled = deleteConfirmText.trim().equals("DELETE", ignoreCase = true),
                    onClick = {
                        confirmDelete = false
                        scope.launch { if (auth.requestAccountDeletion()) prefs.clearAll() }
                    },
                ) { Text("Delete account") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            HorizontalDivider()
            content()
        }
    }
}

/** Whole row is one toggleable target (label + switch read together by TalkBack). */
@Composable
fun ToggleRow(label: String, checked: Boolean, description: String? = null, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch)
            .toggleable(value = checked, onValueChange = onChange, role = Role.Switch),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = Spacing.md)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            if (description != null) Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = null)
    }
}

@Composable
private fun LinkRow(label: String, external: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = Spacing.minTouch).clickable(role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
        if (external) Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun LicensesList(modifier: Modifier = Modifier) {
    LazyColumn(modifier.fillMaxSize().padding(horizontal = Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        item { Text("Mr. Blindbandit is built with these open-source libraries. Thank you to their authors.", Modifier.padding(vertical = Spacing.md)) }
        OpenSourceLicenses.all.forEach { lib ->
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(Spacing.md)) {
                        Text(lib.name, style = MaterialTheme.typography.titleMedium)
                        Text(lib.license, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(lib.url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        item { Spacer(Modifier.heightIn(min = Spacing.xl)) }
    }
}

data class OpenSourceLibrary(val name: String, val license: String, val url: String)

object OpenSourceLicenses {
    val all = listOf(
        OpenSourceLibrary("AndroidX, Jetpack Compose & Material Components", "Apache License 2.0", "https://developer.android.com/jetpack"),
        OpenSourceLibrary("Kotlin & kotlinx.coroutines", "Apache License 2.0", "https://kotlinlang.org"),
        OpenSourceLibrary("Clerk Android SDK", "MIT License", "https://github.com/clerk/clerk-android"),
        OpenSourceLibrary("LiveKit Android SDK", "Apache License 2.0", "https://github.com/livekit/client-sdk-android"),
        OpenSourceLibrary("WebRTC", "BSD 3-Clause License", "https://webrtc.org"),
        OpenSourceLibrary("Firebase Cloud Messaging", "Apache License 2.0", "https://firebase.google.com"),
        OpenSourceLibrary("OkHttp", "Apache License 2.0", "https://square.github.io/okhttp/"),
        OpenSourceLibrary("Timber", "Apache License 2.0", "https://github.com/JakeWharton/timber"),
    )
}

private fun openExternal(context: Context, url: String) = safeStart(context, Intent(Intent.ACTION_VIEW, Uri.parse(url)))

private fun openAppNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
    safeStart(context, intent)
}

private fun safeStart(context: Context, intent: Intent) {
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        android.widget.Toast.makeText(context, "No app is available to open this.", android.widget.Toast.LENGTH_SHORT).show()
    }
}

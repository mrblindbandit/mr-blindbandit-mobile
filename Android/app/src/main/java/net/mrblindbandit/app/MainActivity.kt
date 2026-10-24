package net.mrblindbandit.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.util.Locale
import kotlinx.coroutines.launch
import androidx.lifecycle.repeatOnLifecycle
import java.util.UUID
import net.mrblindbandit.app.auth.AuthGatewayScreen
import net.mrblindbandit.app.auth.AuthState
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.brand.BlindbanditLogo
import net.mrblindbandit.app.brand.BrandProgressOverlay
import net.mrblindbandit.app.brand.SpinningBrandLogo
import net.mrblindbandit.app.config.AppConfig
import net.mrblindbandit.app.connect.AppLock
import net.mrblindbandit.app.connect.AppLockScreen
import net.mrblindbandit.app.connect.CallsTab
import net.mrblindbandit.app.connect.CommsDestination
import net.mrblindbandit.app.connect.MessagesTab
import net.mrblindbandit.app.connect.UnreadBadge
import net.mrblindbandit.app.connect.rememberCommunications
import net.mrblindbandit.app.connect.rememberHaptics
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.automirrored.filled.Chat
import net.mrblindbandit.app.creator.NativeCreatorToolkitScreen
import net.mrblindbandit.app.settings.SettingsScreen
import net.mrblindbandit.app.ui.BlindbanditTheme
import net.mrblindbandit.app.ui.Spacing
import net.mrblindbandit.app.ui.openInBrowser

class MainActivity : androidx.fragment.app.FragmentActivity() {
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var pendingMediaRequest: PermissionRequest? = null
    private var pendingMediaResources: Array<String> = emptyArray()
    private val deepLinkState = mutableStateOf<String?>(null)
    val commsDestinationState = mutableStateOf<CommsDestination?>(null)

    private val fileChooserLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val callback = filePathCallback ?: return@registerForActivityResult
        callback.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data))
        filePathCallback = null
    }

    private val notificationPermissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        getSharedPreferences(AndroidAppPreferences.FILE, MODE_PRIVATE).edit().putBoolean("notificationPermissionAsked", true).apply()
        if (!granted) Toast.makeText(this, "Notifications are off. You can turn them on any time in Settings.", Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        BlindbanditFirebaseMessagingService.ensureChannels(this)
        deepLinkState.value = resolveDeepLink(intent)
        setContent { BlindbanditAndroidApp(this, deepLinkState) }
    }

    /**
     * Deep link from a VIEW intent, or from FCM data extras (`url` / `deep_link`) when the
     * system tray displayed the notification while the app was in the background.
     */
    private fun resolveDeepLink(intent: Intent?): String? {
        if (intent == null) return null
        val link = intent.dataString ?: intent.getStringExtra("url") ?: intent.getStringExtra("deep_link") ?: intent.getStringExtra("link")
        CommsDestination.parse(link,
            conversationId = intent.getStringExtra("conversation_id"),
            callId = intent.getStringExtra("call_id"),
            groupId = intent.getStringExtra("group_id"),
        )?.let { commsDestinationState.value = it; return null }
        val raw = intent.dataString
            ?: intent.getStringExtra("url")
            ?: intent.getStringExtra("deep_link")
            ?: return null
        net.mrblindbandit.app.chronicle.ChronicleDeepLink.articleUrl(raw)?.let { return it }
        val absolute = if (raw.startsWith("/")) "https://mrblindbandit.net$raw" else raw
        return absolute.takeIf { UrlPolicy.isFirstParty(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkState.value = resolveDeepLink(intent)
    }

    fun launchFileChooser(callback: ValueCallback<Array<Uri>>, params: WebChromeClient.FileChooserParams): Boolean {
        filePathCallback?.onReceiveValue(null)
        filePathCallback = callback
        return try {
            fileChooserLauncher.launch(params.createIntent())
            true
        } catch (_: Exception) {
            filePathCallback = null
            callback.onReceiveValue(null)
            Toast.makeText(this, "No compatible file picker is available.", Toast.LENGTH_LONG).show()
            false
        }
    }

    fun handleMediaPermission(request: PermissionRequest) {
        runOnUiThread {
            if (!UrlPolicy.isFirstParty(request.origin.toString())) {
                request.deny()
                return@runOnUiThread
            }
            val allowed = request.resources.filter {
                it == PermissionRequest.RESOURCE_VIDEO_CAPTURE || it == PermissionRequest.RESOURCE_AUDIO_CAPTURE
            }.toTypedArray()
            if (allowed.isEmpty()) {
                request.deny()
                return@runOnUiThread
            }
            val androidPermissions = mutableListOf<String>()
            if (allowed.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) androidPermissions += Manifest.permission.CAMERA
            if (allowed.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) androidPermissions += Manifest.permission.RECORD_AUDIO
            val missing = androidPermissions.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
            if (missing.isEmpty()) {
                request.grant(allowed)
            } else {
                pendingMediaRequest?.deny()
                pendingMediaRequest = request
                pendingMediaResources = allowed
                ActivityCompat.requestPermissions(this, missing.toTypedArray(), MEDIA_PERMISSION_REQUEST)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MEDIA_PERMISSION_REQUEST) return
        val request = pendingMediaRequest ?: return
        val allGranted = permissions.indices.all { grantResults.getOrNull(it) == PackageManager.PERMISSION_GRANTED }
        if (allGranted) request.grant(pendingMediaResources) else request.deny()
        pendingMediaRequest = null
        pendingMediaResources = emptyArray()
    }

    /**
     * Called only from an explicit user action (Home "Turn on notifications" card or Settings), never at launch.
     * If the system will no longer show the dialog (denied twice, or blocked in Settings), opens the app's
     * notification settings instead so the button always does something.
     */
    fun requestNotificationPermission() {
        if (NotificationPermission.isGranted(this)) return
        val asked = getSharedPreferences(AndroidAppPreferences.FILE, MODE_PRIVATE).getBoolean("notificationPermissionAsked", false)
        val needsRuntimePermission = Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        val dialogAvailable = needsRuntimePermission &&
            (!asked || ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.POST_NOTIFICATIONS))
        if (dialogAvailable) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            openNotificationSettings()
        }
    }

    private fun openNotificationSettings() {
        val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
        runCatching { startActivity(intent) }
    }

    companion object { private const val MEDIA_PERMISSION_REQUEST = 7301 }
}

enum class AppTab(val label: String, val icon: ImageVector, val description: String) {
    HOME("Home", Icons.Default.Home, "Home"),
    MESSAGES("Messages", Icons.AutoMirrored.Filled.Chat, "Messages"),
    CALLS("Calls", Icons.Default.Phone, "Calls"),
    LISTEN("Listen", Icons.Default.Headphones, "Listen to music"),
    MORE("More", Icons.Default.MoreHoriz, "More options"),
}

@Composable
fun BlindbanditAndroidApp(activity: MainActivity, deepLinkState: MutableState<String?>) {
    val context = LocalContext.current
    val prefs = remember { AndroidAppPreferences(context) }
    BlindbanditTheme(appearance = prefs.appearance, highContrast = prefs.highContrast, dynamicColor = prefs.dynamicColor) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            AppRoot(activity, deepLinkState, prefs)
        }
    }
}

@Composable
private fun AppRoot(activity: MainActivity, deepLinkState: MutableState<String?>, prefs: AndroidAppPreferences) {
    val context = LocalContext.current
    val auth = remember { ClerkAuthService(context) }
    val screenshot = remember { StoreScreenshotMode.from(activity.intent) }
    var tab by rememberSaveable { mutableStateOf(screenshot?.tab ?: AppTab.HOME) }
    var currentUrl by rememberSaveable { mutableStateOf(BuildConfig.WEB_BASE_URL + (screenshot?.webPath ?: "/")) }
    var showSettings by rememberSaveable { mutableStateOf(screenshot?.settings == true) }
    var showWeb by rememberSaveable { mutableStateOf(screenshot?.webPath != null) }
    var showAssistant by remember { mutableStateOf(false) }
    var showCreator by rememberSaveable { mutableStateOf(false) }
    var showChronicle by rememberSaveable { mutableStateOf(screenshot?.chronicle == true) }
    var chronicleArticle by rememberSaveable { mutableStateOf<String?>(screenshot?.articleUrl) }

    LaunchedEffect(Unit) {
        if (screenshot != null) auth.useStoreScreenshotAccount("Bandit Fan", AppConfig.SUPPORT_EMAIL) else auth.configure()
    }
    LaunchedEffect(deepLinkState.value) {
        deepLinkState.value?.let {
            val article = net.mrblindbandit.app.chronicle.ChronicleDeepLink.articleUrl(it)
            if (article != null) {
                chronicleArticle = article
                showChronicle = true
            } else {
                currentUrl = it
                showWeb = true
            }
            deepLinkState.value = null
        }
    }
    LaunchedEffect(prefs.keepScreenAwake) {
        if (prefs.keepScreenAwake) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    when (val state = auth.state) {
        AuthState.Unknown -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            SpinningBrandLogo(112.dp, prefs.reduceMotion)
        }
        AuthState.SignedOut -> Box(Modifier.fillMaxSize().safeDrawingPadding()) { AuthGatewayScreen(auth, prefs.reduceMotion) }
        is AuthState.SignedIn -> {
            val communications = rememberCommunications(auth)
            communications.startWithCameraOff = prefs.startCallsWithCameraOff
            communications.speakerByDefault = prefs.speakerphoneByDefault
            communications.preferBluetoothHeadset = prefs.preferBluetoothHeadset
            val haptics = rememberHaptics { prefs.hapticsEnabled }
            var locked by remember { mutableStateOf(screenshot == null && communications.local.appLockEnabled && !AppLock.unlockedThisProcess) }
            var pendingThread by remember { mutableStateOf<String?>(null) }
            var dialRequest by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
            LaunchedEffect(state.email) { if (screenshot == null) communications.bootstrap() }
            DisposableEffect(communications) {
                val receiver = object : android.content.BroadcastReceiver() {
                    override fun onReceive(ctx: android.content.Context?, event: Intent?) {
                        val ended = event?.getStringExtra("call_id") ?: return
                        communications.remoteEnded(ended)
                    }
                }
                ContextCompat.registerReceiver(context, receiver, android.content.IntentFilter(BlindbanditFirebaseMessagingService.ACTION_CALL_ENDED), ContextCompat.RECEIVER_NOT_EXPORTED)
                onDispose { context.unregisterReceiver(receiver); communications.endCall() }
            }

            val appLifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
            LaunchedEffect(communications) {
                appLifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.RESUMED) {
                    while (true) { communications.refreshIncomingCalls(); kotlinx.coroutines.delay(5_000) }
                }
            }
            LaunchedEffect(communications.incomingCallId) {
                if (communications.incomingCallId != null) { tab = AppTab.CALLS; showAssistant = false; showWeb = false; showSettings = false }
            }
            val destination = activity.commsDestinationState.value
            LaunchedEffect(destination) {
                when (destination) {
                    is CommsDestination.Thread -> { pendingThread = destination.conversationId; tab = AppTab.MESSAGES }
                    is CommsDestination.Group -> { communications.openGroupId = destination.groupId; tab = AppTab.MESSAGES }
                    is CommsDestination.Call -> { communications.incomingCallId = destination.callId; tab = AppTab.CALLS }
                    CommsDestination.Calls -> tab = AppTab.CALLS
                    CommsDestination.Messages -> tab = AppTab.MESSAGES
                    null -> Unit
                }
                if (destination != null) { showAssistant = false; showSettings = false; showWeb = false; showChronicle = false; showCreator = false; activity.commsDestinationState.value = null }
            }
            if (locked) {
                AppLockScreen(activity) { AppLock.unlockedThisProcess = true; locked = false }
            } else {
            LaunchedEffect(state.email) { if (screenshot == null) registerPushToken(context, communications) }
            val openWeb: (String) -> Unit = { currentUrl = it; showWeb = true }
            when {
                showSettings -> SettingsScreen(
                    prefs = prefs,
                    auth = auth,
                    onBack = { showSettings = false },
                    onOpenWeb = { showSettings = false; openWeb(it) },
                    onRequestNotifications = { activity.requestNotificationPermission() },
                    commsSection = { net.mrblindbandit.app.connect.CommsSettingsSection(communications, activity, haptics) },
                )
                showAssistant -> net.mrblindbandit.app.ai.AssistantScreen(communications) { showAssistant = false }
                showCreator -> {
                    BackHandler { showCreator = false }
                    Box(Modifier.fillMaxSize().safeDrawingPadding()) { NativeCreatorToolkitScreen() }
                }
                showChronicle && !showWeb -> net.mrblindbandit.app.chronicle.ChronicleScreen(
                    onBack = { showChronicle = false; chronicleArticle = null },
                    initialArticleUrl = chronicleArticle,
                    onOpenWeb = openWeb,
                )
                showWeb -> Box(Modifier.fillMaxSize().safeDrawingPadding()) { WebScreen(activity, currentUrl, prefs, onClose = { showWeb = false }) }
                else -> {
                    BackHandler(enabled = tab != AppTab.HOME) { tab = AppTab.HOME }
                    Scaffold(bottomBar = {
                        NavigationBar {
                            AppTab.entries.forEach { item ->
                                NavigationBarItem(
                                    selected = tab == item,
                                    onClick = { haptics.tap(); tab = item },
                                    icon = {
                                        if (item == AppTab.MESSAGES) UnreadBadge(communications.unreadBadge) { Icon(item.icon, contentDescription = null) }
                                        else Icon(item.icon, contentDescription = null)
                                    },
                                    modifier = Modifier.semantics {
                                        val n = communications.unreadBadge
                                        if (item == AppTab.MESSAGES && n > 0) stateDescription = "$n unread"
                                    },
                                    label = { Text(item.label) },
                                )
                            }
                        }
                    }) { inner ->
                        Box(Modifier.fillMaxSize().padding(inner)) {
                            when (tab) {
                                AppTab.HOME -> HomeScreen(
                                    displayName = state.displayName,
                                    onAssistant = { showAssistant = true },
                                    onCreator = { showCreator = true },
                                    onConnect = { tab = AppTab.MESSAGES },
                                    onListen = { tab = AppTab.LISTEN },
                                    onWeb = openWeb,
                                    onChronicle = { chronicleArticle = null; showChronicle = true },
                                    onSettings = { showSettings = true },
                                    onEnableNotifications = { activity.requestNotificationPermission() },
                                )
                                AppTab.MESSAGES -> MessagesTab(
                                    communications, haptics, signedIn = true,
                                    pendingThread = pendingThread, onPendingThreadHandled = { pendingThread = null },
                                    onCall = { h, v -> dialRequest = h to v; tab = AppTab.CALLS },
                                    onDestination = { d -> activity.commsDestinationState.value = d },
                                )
                                AppTab.CALLS -> CallsTab(
                                    communications, haptics, signedIn = true,
                                    dialRequest = dialRequest, onDialHandled = { dialRequest = null },
                                    onMessage = { h -> tab = AppTab.MESSAGES; activity.commsDestinationState.value = null; dialRequest = null; messageHandle(communications, h) { id -> pendingThread = id } },
                                )
                                AppTab.LISTEN -> ListenHubScreen(onOpenSite = openWeb, prefs = prefs)
                                AppTab.MORE -> MoreHubScreen(auth = auth, onOpenSite = openWeb, onOpenSettings = { showSettings = true }, onOpenCreator = { showCreator = true })
                            }
                        }
                    }
                }
            }
            }
        }
    }
}

private fun messageHandle(c: net.mrblindbandit.app.connect.ProductionCommunicationsService, handle: String, open: (String) -> Unit) {
    val id = c.conversations.firstOrNull { it.peerHandle.equals(handle, ignoreCase = true) }?.id
    if (id != null) open(id) else net.mrblindbandit.app.connect.Announcer.announce(c.local.context, "No conversation with @$handle yet. Use New message to start one.")
}

private fun registerPushToken(context: android.content.Context, communications: net.mrblindbandit.app.connect.ProductionCommunicationsService) {
    if (FirebaseApp.getApps(context).isEmpty()) return
    FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
        val store = context.getSharedPreferences(AndroidAppPreferences.FILE, android.content.Context.MODE_PRIVATE)
        val installationId = store.getString("installationId", null) ?: UUID.randomUUID().toString().also {
            store.edit().putString("installationId", it).apply()
        }
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
            communications.registerDevice(token, installationId, BuildConfig.VERSION_NAME, Locale.getDefault().language.ifBlank { "en" })
        }
    }
}

@Composable
private fun HomeScreen(
    displayName: String,
    onAssistant: () -> Unit,
    onCreator: () -> Unit,
    onConnect: () -> Unit,
    onListen: () -> Unit,
    onWeb: (String) -> Unit,
    onChronicle: () -> Unit,
    onSettings: () -> Unit,
    onEnableNotifications: () -> Unit,
) {
    val context = LocalContext.current
    val notificationsOn = rememberNotificationsEnabled()
    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        item {
            Row(Modifier.fillMaxWidth().padding(top = Spacing.md), verticalAlignment = Alignment.CenterVertically) {
                BlindbanditLogo(64.dp)
                Spacer(Modifier.width(Spacing.md))
                Column(Modifier.weight(1f)) {
                    Text("Welcome, ${displayName.substringBefore(' ')}", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.semantics { heading() })
                    Text("Blindbandit Records", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = onSettings, modifier = Modifier.size(Spacing.minTouch)) {
                    Icon(Icons.Default.Settings, contentDescription = "Settings")
                }
            }
        }
        if (!notificationsOn) {
            item {
                HomeCard(
                    icon = Icons.Default.Notifications,
                    title = "Turn on notifications",
                    body = "Get alerted about new messages and incoming calls.",
                    onClick = onEnableNotifications,
                    highlighted = true,
                )
            }
        }
        item { HomeCard(Icons.Default.Language, "The Chronicle", "Read the latest Blindbandit Chronicle stories natively. Saved for offline reading.", onChronicle, highlighted = notificationsOn) }
        item { HomeCard(Icons.Default.Phone, "Calls & messages", "Voice calls, video calls, and chat with people on Blindbandit.", onConnect) }
        item { HomeCard(Icons.Default.Build, "AI assistant", "Cloud chat, translation, images and on-device speech.", onAssistant) }
        item { HomeCard(Icons.Default.Build, "Creator tools", "Metronome, BPM tapper, royalty splits, release checklist, and more. Works offline.", onCreator) }
        item { HomeCard(Icons.Default.Headphones, "Listen", "Mr. Blindbandit on your favourite music services.", onListen) }
        item { HomeCard(Icons.Default.Language, "Music & releases", "Releases and news from mrblindbandit.net.", { onWeb(BuildConfig.WEB_BASE_URL + "/music/") }) }
        item { HomeCard(Icons.Default.OpenInBrowser, "Label portal", "Blindbandit Records artist and client portal.", { onWeb(BuildConfig.WEB_BASE_URL + "/portal/") }) }
        item { Spacer(Modifier.heightIn(min = Spacing.lg)) }
    }
}

@Composable
private fun HomeCard(icon: ImageVector, title: String, body: String, onClick: () -> Unit, highlighted: Boolean = false) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().heightIn(min = 72.dp),
        colors = if (highlighted) CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary)
        else CardDefaults.cardColors(),
    ) {
        Row(Modifier.padding(Spacing.md), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(32.dp))
            Spacer(Modifier.width(Spacing.md))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(body, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WebScreen(activity: MainActivity, url: String, prefs: AndroidAppPreferences, onClose: () -> Unit) {
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var loading by remember(url) { mutableStateOf(true) }
    var progress by remember(url) { mutableIntStateOf(0) }
    var title by remember(url) { mutableStateOf("mrblindbandit.net") }

    BackHandler {
        val web = webViewRef
        if (web != null && web.canGoBack()) web.goBack() else onClose()
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text(title, maxLines = 1) },
            navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close website") } },
            actions = {
                IconButton(onClick = { webViewRef?.reload() }) { Icon(Icons.Default.Refresh, contentDescription = "Reload page") }
                IconButton(onClick = {
                    openInBrowser(activity, webViewRef?.url ?: url)
                }) { Icon(Icons.Default.OpenInBrowser, contentDescription = "Open in browser") }
            },
        )
    }) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { context ->
                    WebView(context).apply {
                        webViewRef = this
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                        isFocusable = true
                        isFocusableInTouchMode = true
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.allowFileAccess = false
                        settings.allowContentAccess = false
                        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                        settings.mediaPlaybackRequiresUserGesture = !prefs.mediaAutoplay
                        settings.builtInZoomControls = true
                        settings.displayZoomControls = false
                        settings.textZoom = prefs.textZoom
                        settings.safeBrowsingEnabled = true
                        // Global Privacy Control: the site's consent manager then keeps ads and analytics off
                        // inside the app, so the "no tracking, no ads" Data safety answers stay true.
                        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                            WebViewCompat.addDocumentStartJavaScript(this, GLOBAL_PRIVACY_CONTROL_SCRIPT, setOf("https://mrblindbandit.net", "https://www.mrblindbandit.net"))
                            StoreScreenshotMode.consentScript(activity.intent)?.let { script ->
                                WebViewCompat.addDocumentStartJavaScript(this, script, setOf("https://mrblindbandit.net", "https://www.mrblindbandit.net"))
                            }
                        }
                        CookieManager.getInstance().setAcceptCookie(true)
                        CookieManager.getInstance().setAcceptThirdPartyCookies(this, prefs.allowThirdPartyCookies)
                        webViewClient = object : WebViewClient() {
                            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                                val target = request?.url?.toString() ?: return false
                                if (UrlPolicy.isFirstParty(target)) return false
                                if (target.startsWith("https://") || target.startsWith("mailto:") || target.startsWith("tel:")) {
                                    openInBrowser(context, target)
                                }
                                return true
                            }
                            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) { loading = true; progress = 0 }
                            override fun onPageFinished(view: WebView?, url: String?) {
                                loading = false; progress = 100
                                title = view?.title?.takeIf { it.isNotBlank() } ?: title
                                if (prefs.announcePageLoads) view?.let { it.contentDescription = null; it.announceForAccessibilityCompat("Page loaded: $title") }
                            }
                            override fun onRenderProcessGone(view: WebView?, detail: android.webkit.RenderProcessGoneDetail?): Boolean {
                                // The page's renderer crashed or was stopped to free memory. Without this, Android
                                // closes the whole app. Drop the dead WebView and return to the app instead.
                                view?.let { (it.parent as? android.view.ViewGroup)?.removeView(it); it.destroy() }
                                webViewRef = null
                                Toast.makeText(context, "The page stopped responding. Please open it again.", Toast.LENGTH_LONG).show()
                                onClose()
                                return true
                            }
                        }
                        webChromeClient = object : WebChromeClient() {
                            override fun onProgressChanged(view: WebView?, newProgress: Int) { progress = newProgress; loading = newProgress < 100 }
                            override fun onShowFileChooser(webView: WebView?, callback: ValueCallback<Array<Uri>>?, params: FileChooserParams?): Boolean {
                                if (callback == null || params == null) return false
                                return activity.launchFileChooser(callback, params)
                            }
                            override fun onPermissionRequest(request: PermissionRequest?) { if (request != null) activity.handleMediaPermission(request) }
                        }
                        setDownloadListener { downloadUrl, _, _, _, _ ->
                            if (downloadUrl.startsWith("https://")) openInBrowser(context, downloadUrl)
                        }
                        loadUrl(url)
                    }
                },
                update = { web ->
                    web.settings.textZoom = prefs.textZoom
                    web.settings.mediaPlaybackRequiresUserGesture = !prefs.mediaAutoplay
                    CookieManager.getInstance().setAcceptThirdPartyCookies(web, prefs.allowThirdPartyCookies)
                    if (web.url != url && web.originalUrl != url && web.url == null) web.loadUrl(url)
                },
            )
            if (loading) {
                if (prefs.reduceMotion) LinearProgressIndicator(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth())
                else BrandProgressOverlay("Loading page", progress, prefs.reduceMotion)
            }
        }
    }
    DisposableEffect(Unit) { onDispose { webViewRef?.destroy() } }
}

private const val GLOBAL_PRIVACY_CONTROL_SCRIPT =
    "(function(){try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:function(){return true;},configurable:true});}catch(e){}})();"

/** Posts a polite accessibility announcement without the deprecated View API. */
private fun View.announceForAccessibilityCompat(text: String) {
    val manager = context.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE) as? android.view.accessibility.AccessibilityManager ?: return
    if (!manager.isEnabled) return
    val event = if (Build.VERSION.SDK_INT >= 30) android.view.accessibility.AccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_ANNOUNCEMENT)
    else @Suppress("DEPRECATION") android.view.accessibility.AccessibilityEvent.obtain(android.view.accessibility.AccessibilityEvent.TYPE_ANNOUNCEMENT)
    event.text.add(text)
    manager.sendAccessibilityEvent(event)
}

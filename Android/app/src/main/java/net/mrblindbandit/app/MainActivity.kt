package net.mrblindbandit.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.filled.Web
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : ComponentActivity() {
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var pendingMediaRequest: PermissionRequest? = null
    private var pendingMediaResources: Array<String> = emptyArray()
    private val deepLinkState = mutableStateOf<String?>(null)

    private val fileChooserLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val callback = filePathCallback ?: return@registerForActivityResult
        val uris = WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
        callback.onReceiveValue(uris)
        filePathCallback = null
    }

    private val notificationPermissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        deepLinkState.value = intent?.dataString?.takeIf { UrlPolicy.isFirstParty(it) }
        setContent {
            MaterialTheme {
                BlindbanditAndroidApp(activity = this, deepLinkState = deepLinkState)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkState.value = intent.dataString?.takeIf { UrlPolicy.isFirstParty(it) }
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

            val allowedWebResources = request.resources.filter {
                it == PermissionRequest.RESOURCE_VIDEO_CAPTURE || it == PermissionRequest.RESOURCE_AUDIO_CAPTURE
            }.toTypedArray()
            if (allowedWebResources.isEmpty()) {
                request.deny()
                return@runOnUiThread
            }

            val androidPermissions = mutableListOf<String>()
            if (allowedWebResources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) androidPermissions += Manifest.permission.CAMERA
            if (allowedWebResources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) androidPermissions += Manifest.permission.RECORD_AUDIO

            val missing = androidPermissions.filter {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            }

            if (missing.isEmpty()) {
                request.grant(allowedWebResources)
            } else {
                pendingMediaRequest?.deny()
                pendingMediaRequest = request
                pendingMediaResources = allowedWebResources
                ActivityCompat.requestPermissions(this, missing.toTypedArray(), MEDIA_PERMISSION_REQUEST)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MEDIA_PERMISSION_REQUEST) return
        val request = pendingMediaRequest ?: return
        val allGranted = permissions.indices.all { grantResults.getOrNull(it) == PackageManager.PERMISSION_GRANTED }
        if (allGranted) request.grant(pendingMediaResources) else request.deny()
        pendingMediaRequest = null
        pendingMediaResources = emptyArray()
    }

    fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    companion object {
        private const val MEDIA_PERMISSION_REQUEST = 7301
    }
}

enum class AppTab(val label: String) { HOME("Home"), WEB("Website"), MEDIA("Media"), SETTINGS("Settings") }

@Composable
fun BlindbanditAndroidApp(activity: MainActivity, deepLinkState: MutableState<String?>) {
    val context = LocalContext.current
    val prefs = remember { AndroidAppPreferences(context) }
    var tab by rememberSaveable { mutableStateOf(AppTab.HOME) }
    var currentUrl by rememberSaveable { mutableStateOf(BuildConfig.WEB_BASE_URL + "/") }

    LaunchedEffect(deepLinkState.value) {
        deepLinkState.value?.let {
            currentUrl = it
            tab = AppTab.WEB
            deepLinkState.value = null
        }
    }

    LaunchedEffect(prefs.keepScreenAwake) {
        if (prefs.keepScreenAwake) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    Scaffold(
        bottomBar = {
            NavigationBar {
                AppTab.entries.forEach { item ->
                    val icon = when (item) {
                        AppTab.HOME -> Icons.Default.Home
                        AppTab.WEB -> Icons.Default.Web
                        AppTab.MEDIA -> Icons.Default.Build
                        AppTab.SETTINGS -> Icons.Default.Settings
                    }
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = {
                            tab = item
                            if (item == AppTab.WEB) currentUrl = BuildConfig.WEB_BASE_URL + "/"
                            if (item == AppTab.MEDIA) currentUrl = BuildConfig.WEB_BASE_URL + "/media-tools/"
                        },
                        icon = { Icon(icon, contentDescription = item.label) },
                        label = { Text(item.label) }
                    )
                }
            }
        }
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when (tab) {
                AppTab.HOME -> HomeScreen(
                    onOpen = { url -> currentUrl = url; tab = AppTab.WEB },
                    onMedia = { currentUrl = BuildConfig.WEB_BASE_URL + "/media-tools/"; tab = AppTab.MEDIA },
                    onSettings = { tab = AppTab.SETTINGS }
                )
                AppTab.WEB, AppTab.MEDIA -> BlindbanditWebView(activity, currentUrl, prefs)
                AppTab.SETTINGS -> SettingsScreen(activity, prefs)
            }
        }
    }
}

@Composable
private fun HomeScreen(onOpen: (String) -> Unit, onMedia: () -> Unit, onSettings: () -> Unit) {
    val links = listOf(
        "Public website" to BuildConfig.WEB_BASE_URL + "/",
        "Profile and account" to BuildConfig.WEB_BASE_URL + "/account",
        "Community" to BuildConfig.WEB_BASE_URL + "/community/",
        "Label dashboard" to BuildConfig.WEB_BASE_URL + "/portal/",
        "Payments" to BuildConfig.WEB_BASE_URL + "/portal/payments/"
    )
    LazyColumn(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                BrandLogo(72.dp)
                Spacer(Modifier.width(16.dp))
                Column {
                    Text("Mr. Blindbandit", fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                    Text("Blindbandit Records · Android companion", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        item { Button(onClick = onMedia, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.UploadFile, null); Spacer(Modifier.width(8.dp)); Text("Open Media Suite") } }
        items(links) { (label, url) ->
            Button(onClick = { onOpen(url) }, modifier = Modifier.fillMaxWidth()) { Text(label) }
        }
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Native Android features", fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                    Text("TalkBack-first navigation, Android System WebView, camera and microphone permission handling, native file uploads, Firebase Cloud Messaging scaffold, deep links, branded loading, and system accessibility support.")
                    Button(onClick = onSettings) { Text("Advanced settings") }
                }
            }
        }
    }
}

@Composable
private fun BlindbanditWebView(activity: MainActivity, url: String, prefs: AndroidAppPreferences) {
    var loading by remember(url) { mutableStateOf(true) }
    var progress by remember(url) { mutableIntStateOf(0) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    Box(Modifier.fillMaxSize()) {
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
                    settings.databaseEnabled = true
                    settings.allowFileAccess = false
                    settings.allowContentAccess = true
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                    settings.mediaPlaybackRequiresUserGesture = !prefs.mediaAutoplay
                    settings.builtInZoomControls = true
                    settings.displayZoomControls = false
                    settings.textZoom = prefs.textZoom
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) settings.safeBrowsingEnabled = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, prefs.allowThirdPartyCookies)

                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                            val target = request?.url?.toString() ?: return false
                            if (UrlPolicy.isFirstParty(target)) return false
                            if (target.startsWith("https://") || target.startsWith("mailto:") || target.startsWith("tel:")) {
                                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(target))) }
                            }
                            return true
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                            loading = true
                            progress = 0
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            loading = false
                            progress = 100
                            if (prefs.announcePageLoads) view?.announceForAccessibility("Page loaded")
                        }
                    }

                    webChromeClient = object : WebChromeClient() {
                        override fun onProgressChanged(view: WebView?, newProgress: Int) {
                            progress = newProgress
                            loading = newProgress < 100
                        }

                        override fun onShowFileChooser(
                            webView: WebView?,
                            filePathCallback: ValueCallback<Array<Uri>>?,
                            fileChooserParams: FileChooserParams?
                        ): Boolean {
                            if (filePathCallback == null || fileChooserParams == null) return false
                            return activity.launchFileChooser(filePathCallback, fileChooserParams)
                        }

                        override fun onPermissionRequest(request: PermissionRequest?) {
                            if (request != null) activity.handleMediaPermission(request)
                        }
                    }

                    setDownloadListener { downloadUrl, _, _, _, _ ->
                        if (downloadUrl.startsWith("https://")) {
                            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(downloadUrl))) }
                        }
                    }
                    loadUrl(url)
                }
            },
            update = { web ->
                web.settings.textZoom = prefs.textZoom
                web.settings.mediaPlaybackRequiresUserGesture = !prefs.mediaAutoplay
                CookieManager.getInstance().setAcceptThirdPartyCookies(web, prefs.allowThirdPartyCookies)
                if (web.url != url) web.loadUrl(url)
            }
        )

        Row(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)).padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Button(onClick = { webViewRef?.goBack() }, enabled = webViewRef?.canGoBack() == true) { Text("Back") }
            Button(onClick = { webViewRef?.reload() }) { Icon(Icons.Default.Refresh, contentDescription = "Reload page") }
            Button(onClick = { runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(webViewRef?.url ?: url))) } }) { Text("Browser") }
        }

        if (loading) {
            BrandedLoadingOverlay(progress = progress, reduceMotion = prefs.reduceMotion)
        }
    }
}

@Composable
private fun BrandedLoadingOverlay(progress: Int, reduceMotion: Boolean) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Card(
            Modifier.padding(24.dp).semantics { liveRegion = LiveRegionMode.Polite },
            shape = RoundedCornerShape(24.dp)
        ) {
            Column(Modifier.padding(26.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                PulsingBrandLogo(88.dp, reduceMotion)
                WaveformLoader(reduceMotion)
                Text("Loading page", fontWeight = FontWeight.SemiBold)
                Text("$progress percent", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun BrandLogo(size: androidx.compose.ui.unit.Dp) {
    Box(Modifier.size(size).background(Color.Black, CircleShape), contentAlignment = Alignment.Center) {
        Text("〽", color = Color(0xFFFFD54F), fontSize = (size.value * 0.46f).sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun PulsingBrandLogo(size: androidx.compose.ui.unit.Dp, reduceMotion: Boolean) {
    if (reduceMotion) {
        BrandLogo(size)
        return
    }
    val transition = rememberInfiniteTransition(label = "logoPulse")
    val scale by transition.animateFloat(
        initialValue = 0.94f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(tween(850), RepeatMode.Reverse),
        label = "logoScale"
    )
    val alpha by transition.animateFloat(
        initialValue = 0.76f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(850), RepeatMode.Reverse),
        label = "logoAlpha"
    )
    Box(Modifier.scale(scale).alpha(alpha)) { BrandLogo(size) }
}

@Composable
private fun WaveformLoader(reduceMotion: Boolean) {
    val bars = listOf(14, 28, 40, 22, 46, 30, 18)
    val transition = rememberInfiniteTransition(label = "waveform")
    Row(Modifier.height(52.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        bars.forEachIndexed { index, maxHeight ->
            val animated by transition.animateFloat(
                initialValue = if (reduceMotion) maxHeight.toFloat() else 8f,
                targetValue = maxHeight.toFloat(),
                animationSpec = infiniteRepeatable(tween(480 + index * 45), RepeatMode.Reverse),
                label = "bar$index"
            )
            Box(Modifier.width(4.dp).height((if (reduceMotion) maxHeight.toFloat() else animated).dp).background(MaterialTheme.colorScheme.onSurface, RoundedCornerShape(4.dp)))
        }
    }
}

@Composable
private fun SettingsScreen(activity: MainActivity, prefs: AndroidAppPreferences) {
    val context = LocalContext.current
    var firebaseStatus by remember { mutableStateOf("Checking Google push services") }

    LaunchedEffect(Unit) {
        firebaseStatus = if (FirebaseApp.getApps(context).isNotEmpty()) {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                firebaseStatus = if (task.isSuccessful) "Firebase Cloud Messaging ready" else "Firebase token unavailable"
            }
            "Firebase configured — requesting token"
        } else {
            "FCM framework installed — add google-services.json to activate remote delivery"
        }
    }

    LazyColumn(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { Text("Settings", fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() }) }
        item {
            SettingsCard("Notifications") {
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Notifications, null); Spacer(Modifier.width(8.dp)); Text(firebaseStatus) }
                Button(onClick = { activity.requestNotificationPermission() }) { Text("Enable notification permission") }
            }
        }
        item {
            SettingsCard("Accessibility") {
                SettingSwitch("Announce completed page loads", prefs.announcePageLoads) { prefs.setAnnouncePageLoads(it) }
                SettingSwitch("Reduce app motion", prefs.reduceMotion) { prefs.setReduceMotion(it) }
                SettingSwitch("Keep screen awake", prefs.keepScreenAwake) { prefs.setKeepScreenAwake(it) }
                Text("TalkBack uses the native Android accessibility tree for app controls and the Android System WebView accessibility tree for website content.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = { runCatching { activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) } }) { Text("Open Android accessibility settings") }
            }
        }
        item {
            SettingsCard("Browser") {
                Text("Website text zoom: ${prefs.textZoom} percent")
                Slider(
                    value = prefs.textZoom.toFloat(),
                    onValueChange = { prefs.setTextZoom(it.toInt()) },
                    valueRange = 75f..200f
                )
                SettingSwitch("Allow third-party cookies for sign-in compatibility", prefs.allowThirdPartyCookies) { prefs.setAllowThirdPartyCookies(it) }
                SettingSwitch("Allow media autoplay", prefs.mediaAutoplay) { prefs.setMediaAutoplay(it) }
                SettingSwitch("Pull-to-refresh preference", prefs.pullToRefresh) { prefs.setPullToRefresh(it) }
            }
        }
        item {
            SettingsCard("Camera, microphone, and uploads") {
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Mic, null); Spacer(Modifier.width(8.dp)); Text("First-party web media requests use Android runtime permissions.") }
                Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.UploadFile, null); Spacer(Modifier.width(8.dp)); Text("HTML file inputs use the native Android document/photo picker.") }
                Button(onClick = { runCatching { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))) } }) { Text("Open app permissions") }
            }
        }
        item {
            SettingsCard("Privacy and storage") {
                Button(onClick = {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    WebStorage.getInstance().deleteAllData()
                    Toast.makeText(context, "Website cookies and storage cleared.", Toast.LENGTH_SHORT).show()
                }) { Text("Clear website sessions and storage") }
            }
        }
        item {
            SettingsCard("About") {
                Text("Blindbandit Android version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                Text("Android System WebView · AndroidX · Material 3 · Firebase Cloud Messaging scaffold")
                Text("Accessibility target: TalkBack, large text, display scaling, high contrast, switch access, keyboard navigation, and system reduced-animation preferences.")
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable Column.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 20.sp, modifier = Modifier.semantics { heading() })
            HorizontalDivider()
            content()
        }
    }
}

@Composable
private fun SettingSwitch(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, modifier = Modifier.weight(1f).padding(end = 12.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

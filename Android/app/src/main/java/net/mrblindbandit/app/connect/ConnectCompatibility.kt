package net.mrblindbandit.app.connect

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import net.mrblindbandit.app.auth.ClerkAuthService

/** Keeps the existing MainActivity call site small while sharing Clerk's active global session. */
@Composable
fun ConnectHubScreen(reduceMotion: Boolean) {
    val context = LocalContext.current
    val auth = remember { ClerkAuthService(context) }
    LaunchedEffect(Unit) { auth.configure() }
    ConnectHubScreen(auth = auth, reduceMotion = reduceMotion)
}

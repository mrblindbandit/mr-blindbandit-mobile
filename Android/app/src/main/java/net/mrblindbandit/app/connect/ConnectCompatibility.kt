package net.mrblindbandit.app.connect

import androidx.compose.runtime.Composable
import net.mrblindbandit.app.auth.ClerkAuthService

/** Convenience overload used by the tab host; shares one communications client per session. */
@Composable
fun ConnectTab(auth: ClerkAuthService, communications: ProductionCommunicationsService, reduceMotion: Boolean) {
    ConnectHubScreen(auth = auth, reduceMotion = reduceMotion, communications = communications)
}

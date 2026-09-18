package net.mrblindbandit.app.config

object AppConfig {
    const val APP_DISPLAY_NAME = "Mr. Blind Bandit"
    const val MARKETING_VERSION = "1.5"
    const val DEFAULT_LIVEKIT_ROOM = "mrblindbandit"

    /** Filled from BuildConfig fields generated from local.properties / defaults. */
    val clerkPublishableKey: String get() = net.mrblindbandit.app.BuildConfig.CLERK_PUBLISHABLE_KEY
    val liveKitUrl: String get() = net.mrblindbandit.app.BuildConfig.LIVEKIT_URL
    val liveKitScaffoldToken: String get() = net.mrblindbandit.app.BuildConfig.LIVEKIT_SCAFFOLD_TOKEN
    val googleOAuthClientId: String get() = net.mrblindbandit.app.BuildConfig.GOOGLE_OAUTH_CLIENT_ID

    val isClerkConfigured: Boolean get() = clerkPublishableKey.startsWith("pk_")
    val isLiveKitConfigured: Boolean get() = liveKitUrl.startsWith("wss://")
}

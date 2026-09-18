package net.mrblindbandit.app.config

object AppConfig {
    const val APP_DISPLAY_NAME = "Mr. Blind Bandit"
    const val MARKETING_VERSION = "1.5"
    const val DEFAULT_LIVEKIT_ROOM = "mrblindbandit"
    const val API_BASE_URL = "https://api.mrblindbandit.net"
    const val OAUTH_CALLBACK_SCHEME = "blindbandit"
    const val OAUTH_CALLBACK_HOST = "oauth-callback"

    /** Filled from BuildConfig fields generated from local.properties / defaults. */
    val clerkPublishableKey: String get() = net.mrblindbandit.app.BuildConfig.CLERK_PUBLISHABLE_KEY
    val liveKitUrl: String get() = net.mrblindbandit.app.BuildConfig.LIVEKIT_URL
    val liveKitScaffoldToken: String get() = net.mrblindbandit.app.BuildConfig.LIVEKIT_SCAFFOLD_TOKEN
    val googleOAuthClientId: String get() = net.mrblindbandit.app.BuildConfig.GOOGLE_OAUTH_CLIENT_ID

    val isClerkConfigured: Boolean get() = clerkPublishableKey.startsWith("pk_")
    val isLiveKitConfigured: Boolean get() = liveKitUrl.startsWith("wss://")
    val hasLiveKitScaffoldToken: Boolean get() = liveKitScaffoldToken.isNotBlank()

    /** Sign in with Apple — iOS App Store path; Android has no SIWA. Default off. */
    const val ENABLE_SIGN_IN_WITH_APPLE = false

    /** Phone OTP via Clerk — only if SMS is enabled on the Clerk plan. Default off (Pro-only). */
    const val ENABLE_PHONE_OTP = false
}

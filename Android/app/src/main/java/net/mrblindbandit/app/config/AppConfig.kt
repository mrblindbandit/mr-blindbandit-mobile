package net.mrblindbandit.app.config

object AppConfig {
    const val APP_DISPLAY_NAME = "Mr. Blind Bandit"
    const val MARKETING_VERSION = "1.6"
    const val API_BASE_URL = "https://api.mrblindbandit.net"
    const val OAUTH_CALLBACK_SCHEME = "blindbandit"
    const val OAUTH_CALLBACK_HOST = "oauth-callback"

    /** Client-safe public configuration generated into BuildConfig. */
    val clerkPublishableKey: String get() = net.mrblindbandit.app.BuildConfig.CLERK_PUBLISHABLE_KEY
    val liveKitUrl: String get() = net.mrblindbandit.app.BuildConfig.LIVEKIT_URL
    val googleOAuthClientId: String get() = net.mrblindbandit.app.BuildConfig.GOOGLE_OAUTH_CLIENT_ID

    val isClerkConfigured: Boolean get() = clerkPublishableKey.startsWith("pk_")
    val isLiveKitConfigured: Boolean get() = liveKitUrl.startsWith("wss://")

    /** Phone OTP stays off until SMS/OTP is enabled in the production Clerk instance. */
    const val ENABLE_PHONE_OTP = false
}

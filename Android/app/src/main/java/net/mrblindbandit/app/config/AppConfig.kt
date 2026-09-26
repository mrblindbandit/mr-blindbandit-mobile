package net.mrblindbandit.app.config

object AppConfig {
    const val APP_DISPLAY_NAME = "Mr. Blindbandit"
    const val MARKETING_VERSION = "1.7"
    const val API_BASE_URL = "https://api.mrblindbandit.net"

    const val PRIVACY_URL = "https://mrblindbandit.net/privacy/"
    const val TERMS_URL = "https://mrblindbandit.net/terms/"
    const val SUPPORT_URL = "https://mrblindbandit.net/support/"
    const val ACCESSIBILITY_URL = "https://mrblindbandit.net/accessibility/"
    const val ACCOUNT_DELETION_URL = "https://mrblindbandit.net/account/delete"
    const val SUPPORT_EMAIL = "business@mrblindbandit.net"

    /** Client-safe public configuration generated into BuildConfig. */
    val clerkPublishableKey: String get() = net.mrblindbandit.app.BuildConfig.CLERK_PUBLISHABLE_KEY
    val liveKitUrl: String get() = net.mrblindbandit.app.BuildConfig.LIVEKIT_URL
    val googleOAuthClientId: String get() = net.mrblindbandit.app.BuildConfig.GOOGLE_OAUTH_CLIENT_ID

    val isClerkConfigured: Boolean get() = clerkPublishableKey.startsWith("pk_")
    val isLiveKitConfigured: Boolean get() = liveKitUrl.startsWith("wss://")

    /** Phone OTP stays off until SMS/OTP is enabled in the production Clerk instance. */
    const val ENABLE_PHONE_OTP = false
}

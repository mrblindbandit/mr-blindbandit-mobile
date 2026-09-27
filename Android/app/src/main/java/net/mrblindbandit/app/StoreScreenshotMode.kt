package net.mrblindbandit.app

import android.content.Intent

/**
 * Debug-only mode used by `.github/workflows/store-screenshots.yml` to capture Google Play
 * screenshots of the signed-in screens on an emulator without a real account.
 * `BuildConfig.DEBUG` is false in release builds, so the shipping app can never skip sign-in.
 *
 * adb shell am start -n net.mrblindbandit.app/.MainActivity --ez store_screenshots true --es screen listen
 */
object StoreScreenshotMode {
    data class Request(val tab: AppTab, val settings: Boolean, val webPath: String? = null)

    fun from(intent: Intent?): Request? {
        if (!BuildConfig.DEBUG || intent?.getBooleanExtra("store_screenshots", false) != true) return null
        return when (intent.getStringExtra("screen")) {
            "create" -> Request(AppTab.CREATOR, false)
            "connect" -> Request(AppTab.CONNECT, false)
            "listen" -> Request(AppTab.LISTEN, false)
            "more" -> Request(AppTab.MORE, false)
            "settings", "accessibility" -> Request(AppTab.HOME, true)
            "music" -> Request(AppTab.HOME, false, "/music/")
            "community" -> Request(AppTab.HOME, false, "/mobile")
            "profile" -> Request(AppTab.HOME, false, "/mobile/u/mrblindbandit")
            "bites" -> Request(AppTab.HOME, false, "/mobile/bites")
            else -> Request(AppTab.HOME, false)
        }
    }

    /**
     * Pre-answers the website cookie banner (essential + embedded media, no ads or analytics) so web
     * screenshots show the page instead of the consent prompt. Null outside screenshot mode.
     */
    fun consentScript(intent: Intent?): String? {
        if (from(intent) == null) return null
        return "try { if (!localStorage.getItem('bb-consent-v4')) { localStorage.setItem('bb-consent-v4', " +
            "JSON.stringify({version: 4, savedAt: Date.now(), essential: true, analytics: false, ads: false, media: true})); } } catch (e) {}"
    }
}

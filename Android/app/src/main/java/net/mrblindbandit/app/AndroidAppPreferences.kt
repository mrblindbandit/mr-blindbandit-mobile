package net.mrblindbandit.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

class AndroidAppPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("blindbandit_app", Context.MODE_PRIVATE)

    var textZoom by mutableIntStateOf(prefs.getInt("textZoom", 100).coerceIn(75, 200))
        private set
    var reduceMotion by mutableStateOf(prefs.getBoolean("reduceMotion", false))
        private set
    var announcePageLoads by mutableStateOf(prefs.getBoolean("announcePageLoads", true))
        private set
    var pullToRefresh by mutableStateOf(prefs.getBoolean("pullToRefresh", true))
        private set
    var allowThirdPartyCookies by mutableStateOf(prefs.getBoolean("allowThirdPartyCookies", true))
        private set
    var mediaAutoplay by mutableStateOf(prefs.getBoolean("mediaAutoplay", true))
        private set
    var keepScreenAwake by mutableStateOf(prefs.getBoolean("keepScreenAwake", false))
        private set

    fun setTextZoom(value: Int) {
        textZoom = value.coerceIn(75, 200)
        prefs.edit().putInt("textZoom", textZoom).apply()
    }

    fun setReduceMotion(value: Boolean) {
        reduceMotion = value
        prefs.edit().putBoolean("reduceMotion", value).apply()
    }

    fun setAnnouncePageLoads(value: Boolean) {
        announcePageLoads = value
        prefs.edit().putBoolean("announcePageLoads", value).apply()
    }

    fun setPullToRefresh(value: Boolean) {
        pullToRefresh = value
        prefs.edit().putBoolean("pullToRefresh", value).apply()
    }

    fun setAllowThirdPartyCookies(value: Boolean) {
        allowThirdPartyCookies = value
        prefs.edit().putBoolean("allowThirdPartyCookies", value).apply()
    }

    fun setMediaAutoplay(value: Boolean) {
        mediaAutoplay = value
        prefs.edit().putBoolean("mediaAutoplay", value).apply()
    }

    fun setKeepScreenAwake(value: Boolean) {
        keepScreenAwake = value
        prefs.edit().putBoolean("keepScreenAwake", value).apply()
    }
}

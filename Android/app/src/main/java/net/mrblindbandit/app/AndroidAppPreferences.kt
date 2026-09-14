package net.mrblindbandit.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

class AndroidAppPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("blindbandit_app", Context.MODE_PRIVATE)

    private var _textZoom by mutableIntStateOf(prefs.getInt("textZoom", 100).coerceIn(75, 200))
    val textZoom: Int get() = _textZoom

    private var _reduceMotion by mutableStateOf(prefs.getBoolean("reduceMotion", false))
    val reduceMotion: Boolean get() = _reduceMotion

    private var _announcePageLoads by mutableStateOf(prefs.getBoolean("announcePageLoads", true))
    val announcePageLoads: Boolean get() = _announcePageLoads

    private var _pullToRefresh by mutableStateOf(prefs.getBoolean("pullToRefresh", true))
    val pullToRefresh: Boolean get() = _pullToRefresh

    private var _allowThirdPartyCookies by mutableStateOf(prefs.getBoolean("allowThirdPartyCookies", true))
    val allowThirdPartyCookies: Boolean get() = _allowThirdPartyCookies

    private var _mediaAutoplay by mutableStateOf(prefs.getBoolean("mediaAutoplay", true))
    val mediaAutoplay: Boolean get() = _mediaAutoplay

    private var _keepScreenAwake by mutableStateOf(prefs.getBoolean("keepScreenAwake", false))
    val keepScreenAwake: Boolean get() = _keepScreenAwake

    fun setTextZoom(value: Int) {
        _textZoom = value.coerceIn(75, 200)
        prefs.edit().putInt("textZoom", _textZoom).apply()
    }

    fun setReduceMotion(value: Boolean) {
        _reduceMotion = value
        prefs.edit().putBoolean("reduceMotion", value).apply()
    }

    fun setAnnouncePageLoads(value: Boolean) {
        _announcePageLoads = value
        prefs.edit().putBoolean("announcePageLoads", value).apply()
    }

    fun setPullToRefresh(value: Boolean) {
        _pullToRefresh = value
        prefs.edit().putBoolean("pullToRefresh", value).apply()
    }

    fun setAllowThirdPartyCookies(value: Boolean) {
        _allowThirdPartyCookies = value
        prefs.edit().putBoolean("allowThirdPartyCookies", value).apply()
    }

    fun setMediaAutoplay(value: Boolean) {
        _mediaAutoplay = value
        prefs.edit().putBoolean("mediaAutoplay", value).apply()
    }

    fun setKeepScreenAwake(value: Boolean) {
        _keepScreenAwake = value
        prefs.edit().putBoolean("keepScreenAwake", value).apply()
    }
}

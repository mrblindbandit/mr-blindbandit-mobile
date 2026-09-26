package net.mrblindbandit.app

import android.content.Context
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import net.mrblindbandit.app.ui.Appearance

/**
 * Every user-facing setting, persisted in SharedPreferences and exposed as Compose state so the
 * UI updates instantly. Defaults favour accessibility.
 */
class AndroidAppPreferences(context: Context) {
    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private fun bool(key: String, default: Boolean) = mutableStateOf(prefs.getBoolean(key, default))
    private fun putBool(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()

    // Browser
    private val textZoomState = mutableIntStateOf(prefs.getInt("textZoom", 100).coerceIn(75, 200))
    val textZoom get() = textZoomState.value
    private val pullToRefreshState = bool("pullToRefresh", true)
    val pullToRefresh get() = pullToRefreshState.value
    private val allowThirdPartyCookiesState = bool("allowThirdPartyCookies", true)
    val allowThirdPartyCookies get() = allowThirdPartyCookiesState.value
    private val mediaAutoplayState = bool("mediaAutoplay", false)
    val mediaAutoplay get() = mediaAutoplayState.value

    // Accessibility
    private val reduceMotionState = bool("reduceMotion", false)
    val reduceMotion get() = reduceMotionState.value
    private val announcePageLoadsState = bool("announcePageLoads", true)
    val announcePageLoads get() = announcePageLoadsState.value
    private val keepScreenAwakeState = bool("keepScreenAwake", false)
    val keepScreenAwake get() = keepScreenAwakeState.value
    private val hapticsEnabledState = bool("hapticsEnabled", true)
    val hapticsEnabled get() = hapticsEnabledState.value
    private val speechFeedbackState = bool("speechFeedback", true)
    val speechFeedback get() = speechFeedbackState.value
    private val highContrastState = bool("highContrast", false)
    val highContrast get() = highContrastState.value
    private val speechRateState = mutableFloatStateOf(prefs.getFloat("speechRate", 1.0f).coerceIn(0.5f, 2.0f))
    val speechRate get() = speechRateState.value

    // Appearance
    private val appearanceState = mutableStateOf(Appearance.fromKey(prefs.getString("appearance", null)))
    val appearance get() = appearanceState.value

    // Sounds & calls
    private val uiSoundsState = bool("uiSounds", true)
    val uiSounds get() = uiSoundsState.value
    private val startCallsWithCameraOffState = bool("startCallsWithCameraOff", false)
    val startCallsWithCameraOff get() = startCallsWithCameraOffState.value
    private val speakerphoneByDefaultState = bool("speakerphoneByDefault", false)
    val speakerphoneByDefault get() = speakerphoneByDefaultState.value
    private val echoCancellationState = bool("echoCancellation", true)
    val echoCancellation get() = echoCancellationState.value
    private val noiseSuppressionState = bool("noiseSuppression", true)
    val noiseSuppression get() = noiseSuppressionState.value

    // Notifications (in-app preferences; the system permission is separate)
    private val notifyMessagesState = bool("notifyMessages", true)
    val notifyMessages get() = notifyMessagesState.value
    private val notifyCallsState = bool("notifyCalls", true)
    val notifyCalls get() = notifyCallsState.value

    fun setTextZoom(value: Int) { textZoomState.value = value.coerceIn(75, 200); prefs.edit().putInt("textZoom", textZoom).apply() }
    fun setPullToRefresh(value: Boolean) { pullToRefreshState.value = value; putBool("pullToRefresh", value) }
    fun setAllowThirdPartyCookies(value: Boolean) { allowThirdPartyCookiesState.value = value; putBool("allowThirdPartyCookies", value) }
    fun setMediaAutoplay(value: Boolean) { mediaAutoplayState.value = value; putBool("mediaAutoplay", value) }
    fun setReduceMotion(value: Boolean) { reduceMotionState.value = value; putBool("reduceMotion", value) }
    fun setAnnouncePageLoads(value: Boolean) { announcePageLoadsState.value = value; putBool("announcePageLoads", value) }
    fun setKeepScreenAwake(value: Boolean) { keepScreenAwakeState.value = value; putBool("keepScreenAwake", value) }
    fun setHapticsEnabled(value: Boolean) { hapticsEnabledState.value = value; putBool("hapticsEnabled", value) }
    fun setSpeechFeedback(value: Boolean) { speechFeedbackState.value = value; putBool("speechFeedback", value) }
    fun setHighContrast(value: Boolean) { highContrastState.value = value; putBool("highContrast", value) }
    fun setSpeechRate(value: Float) { speechRateState.value = value.coerceIn(0.5f, 2.0f); prefs.edit().putFloat("speechRate", speechRate).apply() }
    fun setAppearance(value: Appearance) { appearanceState.value = value; prefs.edit().putString("appearance", value.storageKey).apply() }
    fun setUiSounds(value: Boolean) { uiSoundsState.value = value; putBool("uiSounds", value) }
    fun setStartCallsWithCameraOff(value: Boolean) { startCallsWithCameraOffState.value = value; putBool("startCallsWithCameraOff", value) }
    fun setSpeakerphoneByDefault(value: Boolean) { speakerphoneByDefaultState.value = value; putBool("speakerphoneByDefault", value) }
    fun setEchoCancellation(value: Boolean) { echoCancellationState.value = value; putBool("echoCancellation", value) }
    fun setNoiseSuppression(value: Boolean) { noiseSuppressionState.value = value; putBool("noiseSuppression", value) }
    fun setNotifyMessages(value: Boolean) { notifyMessagesState.value = value; putBool("notifyMessages", value) }
    fun setNotifyCalls(value: Boolean) { notifyCallsState.value = value; putBool("notifyCalls", value) }

    val listenFavorites: Set<String>
        get() = prefs.getStringSet("listenFavorites", emptySet())?.toSet() ?: emptySet()

    fun setListenFavorites(value: Set<String>) {
        prefs.edit().putStringSet("listenFavorites", value).apply()
    }

    /** Removes every locally stored preference (used after account deletion). */
    fun clearAll() {
        prefs.edit().clear().commit()
        textZoomState.value = prefs.getInt("textZoom", 100).coerceIn(75, 200)
        pullToRefreshState.value = prefs.getBoolean("pullToRefresh", true)
        allowThirdPartyCookiesState.value = prefs.getBoolean("allowThirdPartyCookies", true)
        mediaAutoplayState.value = prefs.getBoolean("mediaAutoplay", false)
        reduceMotionState.value = prefs.getBoolean("reduceMotion", false)
        announcePageLoadsState.value = prefs.getBoolean("announcePageLoads", true)
        keepScreenAwakeState.value = prefs.getBoolean("keepScreenAwake", false)
        hapticsEnabledState.value = prefs.getBoolean("hapticsEnabled", true)
        speechFeedbackState.value = prefs.getBoolean("speechFeedback", true)
        highContrastState.value = prefs.getBoolean("highContrast", false)
        speechRateState.value = prefs.getFloat("speechRate", 1.0f).coerceIn(0.5f, 2.0f)
        appearanceState.value = Appearance.fromKey(prefs.getString("appearance", null))
        uiSoundsState.value = prefs.getBoolean("uiSounds", true)
        startCallsWithCameraOffState.value = prefs.getBoolean("startCallsWithCameraOff", false)
        speakerphoneByDefaultState.value = prefs.getBoolean("speakerphoneByDefault", false)
        echoCancellationState.value = prefs.getBoolean("echoCancellation", true)
        noiseSuppressionState.value = prefs.getBoolean("noiseSuppression", true)
        notifyMessagesState.value = prefs.getBoolean("notifyMessages", true)
        notifyCallsState.value = prefs.getBoolean("notifyCalls", true)
    }

    companion object { const val FILE = "blindbandit_app" }
}

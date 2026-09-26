package net.mrblindbandit.app.ui

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.view.accessibility.AccessibilityManager
import java.util.Locale

/**
 * Haptic and spoken feedback that respects the user's settings. When TalkBack is running we do not
 * start a second voice; screens use live regions instead so TalkBack reads the update itself.
 */
class Feedback(context: Context) {
    private val appContext = context.applicationContext
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        (appContext.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun tap(enabled: Boolean) {
        if (!enabled || vibrator?.hasVibrator() != true) return
        vibrator.vibrate(VibrationEffect.createOneShot(18, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun success(enabled: Boolean) {
        if (!enabled || vibrator?.hasVibrator() != true) return
        vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 25, 60, 25), -1))
    }

    fun speak(text: String, enabled: Boolean, rate: Float) {
        if (!enabled || text.isBlank() || isScreenReaderOn()) return
        val engine = tts
        if (engine == null) {
            tts = TextToSpeech(appContext) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.language = Locale.getDefault()
                    tts?.setSpeechRate(rate)
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "bb-feedback")
                }
            }
            return
        }
        if (!ttsReady) return
        engine.setSpeechRate(rate)
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "bb-feedback")
    }

    fun isScreenReaderOn(): Boolean {
        val manager = appContext.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        return manager?.isTouchExplorationEnabled == true
    }

    fun shutdown() {
        tts?.shutdown()
        tts = null
        ttsReady = false
    }
}

package net.mrblindbandit.app.connect

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.view.HapticFeedbackConstants
import androidx.core.content.getSystemService

/** Call / DM haptic patterns. Honors Settings haptic toggle + system settings. */
object CallHaptics {
    @Volatile var enabled: Boolean = true

    private fun vibrator(context: Context): Vibrator? {
        return if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService<VibratorManager>()?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun pulse(context: Context, ms: Long, amplitude: Int = 96) {
        if (!enabled) return
        val v = vibrator(context) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            v.vibrate(VibrationEffect.createOneShot(ms, amplitude.coerceIn(1, 255)))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(ms)
        }
    }

    private fun pattern(context: Context, timings: LongArray, amplitudes: IntArray) {
        if (!enabled) return
        val v = vibrator(context) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            v.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(timings, -1)
        }
    }

    fun tick(view: View?) {
        if (!enabled) return
        view?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    fun outgoingStart(context: Context) = pulse(context, 25, 64)
    fun ringingPulse(context: Context) = pulse(context, 35, 80)
    fun connecting(context: Context) = pulse(context, 40, 120)
    fun connected(context: Context) = pattern(context, longArrayOf(0, 30, 40, 50), intArrayOf(0, 140, 0, 180))
    fun disconnected(context: Context) = pulse(context, 35, 90)
    fun busyOrFailed(context: Context) = pattern(context, longArrayOf(0, 40, 50, 40), intArrayOf(0, 200, 0, 160))
    fun messageSent(context: Context) = pulse(context, 18, 70)
    fun delivered(context: Context) = pulse(context, 12, 50)
    fun read(context: Context) = pulse(context, 12, 45)
    fun voiceNotePress(context: Context) = pulse(context, 30, 150)
    fun voiceNoteSent(context: Context) = connected(context)
    fun attachmentSent(context: Context) = pulse(context, 28, 110)
    fun inboundMessage(context: Context) = pulse(context, 22, 85)
}

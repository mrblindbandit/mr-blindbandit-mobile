package net.mrblindbandit.app.ai

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

/**
 * Device controls the AI can invoke. Only real Android APIs; honest about Play/OS limits.
 * No root, no silent Wi‑Fi/BT toggles on modern Android (settings panels only).
 */
object DeviceActions {
    data class IntentCmd(val action: String, val arg: String = "")

    fun parse(raw: String): IntentCmd? {
        val t = raw.lowercase().trim().trimEnd('.', '!', '?')
            .removePrefix("hey ai ").removePrefix("ai ").removePrefix("please ").trim()
        when {
            t in listOf("turn up the volume", "volume up", "louder", "turn volume up", "increase volume") ->
                return IntentCmd("volume_up")
            t in listOf("turn down the volume", "volume down", "quieter", "turn volume down", "decrease volume", "lower volume") ->
                return IntentCmd("volume_down")
            t in listOf("mute", "mute volume", "silence") && !t.contains("music") ->
                return IntentCmd("volume_mute")
            t in listOf("unmute", "unmute volume") -> return IntentCmd("volume_unmute")
            t.matches(Regex("set volume to \\d+%?")) || t.matches(Regex("volume \\d+%?")) -> {
                val n = Regex("\\d+").find(t)?.value?.toIntOrNull() ?: return null
                return IntentCmd("volume_set", n.coerceIn(0, 100).toString())
            }
            t in listOf("flashlight on", "turn on flashlight", "turn on the flashlight", "torch on", "light on") ->
                return IntentCmd("flashlight_on")
            t in listOf("flashlight off", "turn off flashlight", "turn off the flashlight", "torch off", "light off") ->
                return IntentCmd("flashlight_off")
            t in listOf("toggle flashlight", "flashlight", "torch") -> return IntentCmd("flashlight_toggle")
            t in listOf("brighter", "brightness up", "increase brightness", "turn up brightness") ->
                return IntentCmd("brightness_up")
            t in listOf("dimmer", "brightness down", "decrease brightness", "turn down brightness", "dim screen") ->
                return IntentCmd("brightness_down")
            t in listOf("open wifi settings", "wifi settings", "wi-fi settings", "open wi-fi") ->
                return IntentCmd("settings_wifi")
            t in listOf("open bluetooth settings", "bluetooth settings", "open bluetooth") ->
                return IntentCmd("settings_bt")
            t in listOf("open accessibility settings", "accessibility settings", "talkback settings") ->
                return IntentCmd("settings_a11y")
            t in listOf("open notification settings", "notification settings") ->
                return IntentCmd("settings_notif")
            t.startsWith("open ") -> {
                val name = t.removePrefix("open ").trim()
                if (name.isNotBlank() && name !in listOf("settings", "the settings")) return IntentCmd("open_app", name)
            }
        }
        return null
    }

    fun run(context: Context, cmd: IntentCmd): String = when (cmd.action) {
        "volume_up" -> adjustVolume(context, AudioManager.ADJUST_RAISE)
        "volume_down" -> adjustVolume(context, AudioManager.ADJUST_LOWER)
        "volume_mute" -> adjustVolume(context, AudioManager.ADJUST_MUTE)
        "volume_unmute" -> adjustVolume(context, AudioManager.ADJUST_UNMUTE)
        "volume_set" -> setVolumePercent(context, cmd.arg.toIntOrNull() ?: 50)
        "flashlight_on" -> setFlashlight(context, true)
        "flashlight_off" -> setFlashlight(context, false)
        "flashlight_toggle" -> toggleFlashlight(context)
        "brightness_up" -> nudgeBrightness(context, +32)
        "brightness_down" -> nudgeBrightness(context, -32)
        "settings_wifi" -> openSettings(context, Settings.Panel.ACTION_WIFI.takeIf { Build.VERSION.SDK_INT >= 29 }
            ?: Settings.ACTION_WIFI_SETTINGS)
        "settings_bt" -> openSettings(context, Settings.ACTION_BLUETOOTH_SETTINGS)
        "settings_a11y" -> openSettings(context, Settings.ACTION_ACCESSIBILITY_SETTINGS)
        "settings_notif" -> openSettings(context, Settings.ACTION_APP_NOTIFICATION_SETTINGS.also {
            // handled below with extras
        }.let { Settings.ACTION_APP_NOTIFICATION_SETTINGS })
        "open_app" -> openApp(context, cmd.arg)
        else -> "I don't know that device action."
    }.also {
        if (cmd.action == "settings_notif") {
            val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { context.startActivity(i) }
        }
    }

    private fun audio(context: Context) = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun adjustVolume(context: Context, direction: Int): String {
        val am = audio(context)
        am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        val pct = (cur * 100) / max
        return "Media volume is now $pct percent."
    }

    private fun setVolumePercent(context: Context, percent: Int): String {
        val am = audio(context)
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val target = ((percent.coerceIn(0, 100) / 100.0) * max).toInt()
        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, AudioManager.FLAG_SHOW_UI)
        return "Media volume set to $percent percent."
    }

    @Volatile private var torchOn = false
    @Volatile private var torchCameraId: String? = null

    private fun setFlashlight(context: Context, on: Boolean): String {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            return "Camera permission is needed for the flashlight. Allow Camera in app settings, then ask again."
        }
        val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = torchCameraId ?: cm.cameraIdList.firstOrNull { cam ->
            cm.getCameraCharacteristics(cam).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return "This device has no flashlight."
        return try {
            cm.setTorchMode(id, on)
            torchCameraId = id
            torchOn = on
            if (on) "Flashlight on." else "Flashlight off."
        } catch (e: Exception) {
            "Couldn't control the flashlight: ${e.localizedMessage ?: "error"}"
        }
    }

    private fun toggleFlashlight(context: Context): String = setFlashlight(context, !torchOn)

    private fun nudgeBrightness(context: Context, delta: Int): String {
        // WRITE_SETTINGS is restricted; open system brightness settings with guidance when we can't write.
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(context)) {
                val i = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(i)
                return "Android needs permission to change brightness. I opened the write-settings screen — turn it on for Mr. BlindBandit, then ask again."
            }
            val resolver = context.contentResolver
            val cur = Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS, 128)
            val next = (cur + delta).coerceIn(1, 255)
            Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, next)
            val pct = (next * 100) / 255
            "Brightness is now about $pct percent."
        } catch (e: Exception) {
            openSettings(context, Settings.ACTION_DISPLAY_SETTINGS)
            "Couldn't set brightness here. Opened display settings. ${e.localizedMessage ?: ""}".trim()
        }
    }

    private fun openSettings(context: Context, action: String): String {
        return try {
            context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            "Opened settings."
        } catch (e: Exception) {
            "Couldn't open settings: ${e.localizedMessage ?: "error"}"
        }
    }

    private fun openApp(context: Context, name: String): String {
        val pm = context.packageManager
        val needle = name.lowercase()
        val match = pm.getInstalledApplications(0).firstOrNull { app ->
            val label = pm.getApplicationLabel(app).toString().lowercase()
            label == needle || label.contains(needle) || app.packageName.contains(needle.replace(" ", ""))
        } ?: return "I couldn't find an installed app named $name."
        val launch = pm.getLaunchIntentForPackage(match.packageName)
            ?: return "I found ${pm.getApplicationLabel(match)} but it has no launch screen."
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launch)
        return "Opening ${pm.getApplicationLabel(match)}."
    }

    /** Limits Play-policy-sensitive actions; used in assistant help text. */
    val capabilitiesSummary: String =
        "I can change media volume, toggle the flashlight (needs Camera permission), nudge brightness if you allow modify-system-settings, " +
            "open Wi‑Fi / Bluetooth / accessibility / notification settings panels, and open installed apps by name. " +
            "Modern Android does not let apps silently flip Wi‑Fi or Bluetooth without a settings panel."
}

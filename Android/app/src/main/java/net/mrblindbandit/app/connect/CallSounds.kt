package net.mrblindbandit.app.connect

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool

/** UI / call SFX — full ambient ringtone + notification pack. */
class CallSounds(private val context: Context) {
    enum class Ringtone(val resName: String, val title: String) {
        DEFAULT("ringtone", "Default"),
        GOLD("ringtone_gold", "Gold"),
        PULSE("ringtone_pulse", "Pulse"),
        CHIME("ringtone_chime", "Chime"),
        AMBIENT_AURORA("ringtone_ambient_aurora", "Ambient · Aurora"),
        AMBIENT_BLOOM("ringtone_ambient_bloom", "Ambient · Bloom"),
        AMBIENT_GLASS("ringtone_ambient_glass", "Ambient · Glass"),
        AMBIENT_NIGHT("ringtone_ambient_night", "Ambient · Night"),
        AMBIENT_RAIN("ringtone_ambient_rain", "Ambient · Rain"),
        AMBIENT_SPACE("ringtone_ambient_space", "Ambient · Space")
    }

    enum class NotificationTone(val resName: String, val title: String) {
        MESSAGE("notif_message", "Message"),
        CALL("notif_call", "Call"),
        DELIVERED("notif_delivered", "Delivered"),
        READ("notif_read", "Read"),
        AMBIENT_SOFT("notif_ambient_soft", "Ambient · Soft"),
        AMBIENT_GLOW("notif_ambient_glow", "Ambient · Glow"),
        AMBIENT_DROP("notif_ambient_drop", "Ambient · Drop"),
        AMBIENT_PETAL("notif_ambient_petal", "Ambient · Petal"),
        AMBIENT_WIND("notif_ambient_wind", "Ambient · Wind")
    }

    var playUISounds: Boolean = true
    var selectedRingtone: Ringtone = Ringtone.DEFAULT
    var selectedNotificationTone: NotificationTone = NotificationTone.MESSAGE

    private val prefs = context.getSharedPreferences("blindbandit_sounds", Context.MODE_PRIVATE)
    private var pool: SoundPool? = null
    private val ids = mutableMapOf<String, Int>()
    private var ringbackPlayer: MediaPlayer? = null

    init {
        playUISounds = prefs.getBoolean("playUISounds", true)
        CallHaptics.enabled = prefs.getBoolean("hapticsEnabled", true)
        selectedRingtone = Ringtone.values().find { it.resName == prefs.getString("selectedRingtone", null) } ?: Ringtone.DEFAULT
        selectedNotificationTone = NotificationTone.values().find { it.resName == prefs.getString("selectedNotificationTone", null) }
            ?: NotificationTone.MESSAGE
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        pool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attrs).build()
        val names = buildList {
            addAll(Ringtone.values().map { it.resName })
            addAll(NotificationTone.values().map { it.resName })
            addAll(
                listOf(
                    "call_initiated", "call_connected", "hangup", "busy_tone",
                    "message_sent", "voicenote_sent", "attachment_sent",
                    "typing_ping", "ringback_outgoing"
                )
            )
        }.distinct()
        names.forEach { name ->
            val resId = context.resources.getIdentifier(name, "raw", context.packageName)
            if (resId != 0) pool?.load(context, resId, 1)?.let { ids[name] = it }
        }
    }

    fun persist() {
        prefs.edit()
            .putBoolean("playUISounds", playUISounds)
            .putBoolean("hapticsEnabled", CallHaptics.enabled)
            .putString("selectedRingtone", selectedRingtone.resName)
            .putString("selectedNotificationTone", selectedNotificationTone.resName)
            .apply()
    }

    private fun play(name: String, volume: Float = 0.7f) {
        if (!playUISounds) return
        val id = ids[name] ?: return
        pool?.play(id, volume, volume, 1, 0, 1f)
    }

    fun startRingback() {
        if (!playUISounds) return
        stopRingback()
        val resId = context.resources.getIdentifier("ringback_outgoing", "raw", context.packageName)
        if (resId == 0) return
        ringbackPlayer = MediaPlayer.create(context, resId)?.apply {
            isLooping = true
            setVolume(0.42f, 0.42f)
            start()
        }
        CallHaptics.outgoingStart(context)
    }

    fun stopRingback() {
        try { ringbackPlayer?.stop() } catch (_: Exception) {}
        ringbackPlayer?.release()
        ringbackPlayer = null
    }

    fun callInitiated() { startRingback(); play("call_initiated", 0.55f) }
    fun callConnecting() = CallHaptics.connecting(context)
    fun callConnected() {
        stopRingback()
        play("call_connected", 0.55f)
        CallHaptics.connected(context)
    }
    fun hangup() {
        stopRingback()
        play("hangup", 0.65f)
        CallHaptics.disconnected(context)
    }
    fun busyOrFailed() {
        stopRingback()
        play("busy_tone", 0.55f)
        CallHaptics.busyOrFailed(context)
    }
    fun messageSent() { play("message_sent", 0.55f); CallHaptics.messageSent(context) }
    fun attachmentSent() { play("attachment_sent", 0.55f); CallHaptics.attachmentSent(context) }
    fun voiceNoteSent() { play("voicenote_sent", 0.6f); CallHaptics.voiceNoteSent(context) }
    fun typingPing() = play("typing_ping", 0.3f)
    fun inboundNotification() {
        play(selectedNotificationTone.resName, 0.6f)
        CallHaptics.inboundMessage(context)
    }
    fun delivered() { play("notif_delivered", 0.4f); CallHaptics.delivered(context) }
    fun read() { play("notif_read", 0.35f); CallHaptics.read(context) }
    fun previewRingtone(tone: Ringtone) = play(tone.resName, 0.65f)
    fun previewNotification(tone: NotificationTone) = play(tone.resName, 0.6f)
}

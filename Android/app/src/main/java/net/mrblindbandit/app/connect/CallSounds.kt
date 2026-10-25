package net.mrblindbandit.app.connect

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool

/** UI / call SFX — full ambient ringtone + notification pack. */
class CallSounds(private val context: Context) {
    enum class Ringtone(val resName: String, val title: String) {
        DEFAULT("ringtone", "Default"),
        MR_BLINDBANDIT("ringtone_mrblindbandit", "Mr. BlindBandit"),
        MR_CLASSIC("ringtone_mrblindbandit_classic", "Classic"),
        MR_ALT("ringtone_mrblindbandit_alt", "Alternative"),
        MR_NIGHT("ringtone_mrblindbandit_night", "Night"),
        MR_PULSE("ringtone_mrblindbandit_pulse", "Mr. BlindBandit Pulse"),
        MR_HEAT("ringtone_mrblindbandit_heat", "Heat"),
        MR_RISE("ringtone_mrblindbandit_rise", "Rise"),
        GOLD("ringtone_gold", "Gold"),
        PULSE("ringtone_pulse", "Pulse"),
        CHIME("ringtone_chime", "Chime"),
        AMBIENT_AURORA("ringtone_ambient_aurora", "Ambient · Aurora"),
        AMBIENT_BLOOM("ringtone_ambient_bloom", "Ambient · Bloom"),
        AMBIENT_GLASS("ringtone_ambient_glass", "Ambient · Glass"),
        AMBIENT_NIGHT("ringtone_ambient_night", "Ambient · Night"),
        AMBIENT_RAIN("ringtone_ambient_rain", "Ambient · Rain"),
        AMBIENT_SPACE("ringtone_ambient_space", "Ambient · Space"),
        AMBIENT_DAWN("ringtone_ambient_dawn", "Ambient · Dawn"),
        AMBIENT_LAGOON("ringtone_ambient_lagoon", "Ambient · Lagoon"),
        AMBIENT_EMBER("ringtone_ambient_ember", "Ambient · Ember"),
        AMBIENT_HORIZON("ringtone_ambient_horizon", "Ambient · Horizon"),
        AMBIENT_VELVET("ringtone_ambient_velvet", "Ambient · Velvet"),
        AMBIENT_CROWN("ringtone_ambient_crown", "Ambient · Crown")
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
        AMBIENT_WIND("notif_ambient_wind", "Ambient · Wind"),
        AMBIENT_HALO("notif_ambient_halo", "Ambient · Halo"),
        AMBIENT_RIPPLE("notif_ambient_ripple", "Ambient · Ripple"),
        AMBIENT_SPARK("notif_ambient_spark", "Ambient · Spark"),
        AMBIENT_MOSS("notif_ambient_moss", "Ambient · Moss"),
        AMBIENT_LANTERN("notif_ambient_lantern", "Ambient · Lantern"),
        AMBIENT_TIDE("notif_ambient_tide", "Ambient · Tide"),
        AMBIENT_BELL("notif_ambient_bell", "Ambient · Bell"),
        AMBIENT_MIST("notif_ambient_mist", "Ambient · Mist")
    }

    var playUISounds: Boolean = true
    var selectedRingtone: Ringtone = Ringtone.DEFAULT
    var selectedNotificationTone: NotificationTone = NotificationTone.MESSAGE

    private val prefs = context.getSharedPreferences("blindbandit_sounds", Context.MODE_PRIVATE)
    private var pool: SoundPool? = null
    private val ids = mutableMapOf<String, Int>()
    private var ringbackPlayer: MediaPlayer? = null
    private var previewPlayer: MediaPlayer? = null

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
            addAll(NotificationTone.values().map { it.resName })
            addAll(
                listOf(
                    "call_initiated", "call_connected", "hangup", "busy_tone",
                    "message_sent", "voicenote_sent", "attachment_sent",
                    "typing_ping"
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

    private enum class OutgoingProgress { Idle, DialTone, Ringback }
    private var outgoingProgress = OutgoingProgress.Idle

    val isOutgoingProgressActive: Boolean
        get() = outgoingProgress != OutgoingProgress.Idle

    /** Voice-call session attrs so LiveKit mic publish never kills dial/ringback. */
    private fun voiceCallAttrs(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private fun playLoopRaw(resName: String, volume: Float = 0.42f): MediaPlayer? {
        val resId = context.resources.getIdentifier(resName, "raw", context.packageName)
        if (resId == 0) return null
        return try {
            MediaPlayer().apply {
                setAudioAttributes(voiceCallAttrs())
                setDataSource(context, android.net.Uri.parse("android.resource://${context.packageName}/$resId"))
                isLooping = true
                setVolume(volume, volume)
                prepare()
                start()
            }
        } catch (_: Exception) {
            // Fallback to create() if setDataSource path fails on some OEMs.
            MediaPlayer.create(context, resId)?.apply {
                isLooping = true
                setVolume(volume, volume)
                start()
            }
        }
    }

    /** Phase 1 — dialing / connecting: continuous US dial tone (350 + 440 Hz). */
    fun startDialTone() {
        if (!playUISounds) return
        if (outgoingProgress == OutgoingProgress.DialTone && ringbackPlayer?.isPlaying == true) return
        stopRingback()
        ringbackPlayer = playLoopRaw("ringback_us_dialtone")
        outgoingProgress = OutgoingProgress.DialTone
        CallHaptics.outgoingStart(context)
    }

    /** Phase 2 — remote ringing: US ringback (440 + 480 Hz, 2s on / 4s off). */
    fun startRingback() {
        if (!playUISounds) return
        if (outgoingProgress == OutgoingProgress.Ringback && ringbackPlayer?.isPlaying == true) return
        stopRingback()
        ringbackPlayer = playLoopRaw("ringback_us_ringback") ?: playLoopRaw("ringback_us_dialtone")
        outgoingProgress = OutgoingProgress.Ringback
    }

    /** After LiveKit mic enable / audio mode change, restart dial/ringback if it died. */
    fun resumeOutgoingProgressIfNeeded() {
        if (outgoingProgress == OutgoingProgress.Idle) return
        val playing = try { ringbackPlayer?.isPlaying == true } catch (_: Exception) { false }
        if (playing) return
        when (outgoingProgress) {
            OutgoingProgress.DialTone -> {
                outgoingProgress = OutgoingProgress.Idle
                startDialTone()
            }
            OutgoingProgress.Ringback -> {
                outgoingProgress = OutgoingProgress.Idle
                startRingback()
            }
            else -> {}
        }
    }

    /** Dialer open → continuous US dial tone until a digit or Call/End. */
    fun openDialerIdleTone() = startDialTone()

    /** Leave Dialer / End — stop dial, ringback. */
    fun closeDialer() = stopRingback()

    /** First digit kills idle dial tone; every key plays classic ITU DTMF. */
    fun dialerKeyPress(key: String) {
        if (outgoingProgress == OutgoingProgress.DialTone) stopRingback()
        playDTMF(key)
    }

    fun stopRingback() {
        try { ringbackPlayer?.stop() } catch (_: Exception) {}
        ringbackPlayer?.release()
        ringbackPlayer = null
        outgoingProgress = OutgoingProgress.Idle
    }

    fun stopOutgoingProgress() = stopRingback()

    /** Classic telephone DTMF (ITU) for in-call keypad. */
    fun playDTMF(key: String) {
        if (!playUISounds) return
        val tone = when (key) {
            "0" -> android.media.ToneGenerator.TONE_DTMF_0
            "1" -> android.media.ToneGenerator.TONE_DTMF_1
            "2" -> android.media.ToneGenerator.TONE_DTMF_2
            "3" -> android.media.ToneGenerator.TONE_DTMF_3
            "4" -> android.media.ToneGenerator.TONE_DTMF_4
            "5" -> android.media.ToneGenerator.TONE_DTMF_5
            "6" -> android.media.ToneGenerator.TONE_DTMF_6
            "7" -> android.media.ToneGenerator.TONE_DTMF_7
            "8" -> android.media.ToneGenerator.TONE_DTMF_8
            "9" -> android.media.ToneGenerator.TONE_DTMF_9
            "*" -> android.media.ToneGenerator.TONE_DTMF_S
            "#" -> android.media.ToneGenerator.TONE_DTMF_P
            else -> return
        }
        try {
            val stream = if (isOutgoingProgressActive || outgoingProgress != OutgoingProgress.Idle)
                android.media.AudioManager.STREAM_VOICE_CALL
            else
                android.media.AudioManager.STREAM_MUSIC
            val tg = android.media.ToneGenerator(stream, 80)
            tg.startTone(tone, 140)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ tg.release() }, 200)
        } catch (_: Exception) {
            try {
                val tg = android.media.ToneGenerator(android.media.AudioManager.STREAM_MUSIC, 80)
                tg.startTone(tone, 140)
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ tg.release() }, 200)
            } catch (_: Exception) {}
        }
    }

    fun callInitiated() { startDialTone() /* dial tone only — no legacy call_initiated oneshot */ }
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
    fun stopPreview() { previewPlayer?.release(); previewPlayer = null }
    fun release() { stopPreview(); stopRingback(); pool?.release(); pool = null }
    fun previewRingtone(tone: Ringtone) {
        stopPreview()
        val id = context.resources.getIdentifier(tone.resName, "raw", context.packageName)
        if (id == 0) return
        previewPlayer = MediaPlayer.create(context, id)?.apply {
            setVolume(0.65f, 0.65f)
            setOnCompletionListener { stopPreview() }
            setOnErrorListener { _, _, _ -> stopPreview(); true }
            start()
        }
    }
    fun previewNotification(tone: NotificationTone) = play(tone.resName, 0.6f)
}

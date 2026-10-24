package net.mrblindbandit.app.connect

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.Collections
import java.util.concurrent.CopyOnWriteArrayList

/**
 * One shared voice-note player for every bubble (iOS VoicePlayback parity).
 * Writes decrypted AAC to a temp .m4a before play — MediaPlayer+MediaDataSource fails on many devices for m4a.
 */
object VoicePlayback {
    data class Item(val id: String, val media: JSONObject, val from: String, val mine: Boolean, val listenOnce: Boolean = false)

    @Volatile var currentId: String? = null; private set
    @Volatile var playing: Boolean = false; private set
    @Volatile var loadingId: String? = null; private set
    @Volatile var elapsedMs: Long = 0; private set
    @Volatile var rate: Float = 1f; private set
    private val played = Collections.synchronizedSet(mutableSetOf<String>())
    private val order = CopyOnWriteArrayList<Item>()
    private var player: MediaPlayer? = null
    private var tempFile: File? = null
    private var focusRequest: AudioFocusRequest? = null
    private val main: Handler by lazy { Handler(Looper.getMainLooper()) }
    private val listeners = CopyOnWriteArrayList<() -> Unit>()
    private val tick = object : Runnable {
        override fun run() {
            val p = player
            if (p != null && playing) {
                elapsedMs = p.currentPosition.toLong()
                notifyListeners()
                main.postDelayed(this, 250)
            }
        }
    }

    fun addListener(l: () -> Unit) { listeners += l }
    fun removeListener(l: () -> Unit) { listeners -= l }
    private fun notifyListeners() { listeners.forEach { runCatching { it() } } }

    fun register(item: Item) {
        val i = order.indexOfFirst { it.id == item.id }
        if (i >= 0) order[i] = item else order += item
    }

    fun isCurrent(id: String) = currentId == id
    fun wasPlayed(id: String) = id in played
    fun rateLabel(r: Float = rate) = when {
        r >= 1.75f -> "2x"
        r >= 1.25f -> "1.5x"
        else -> "1x"
    }

    fun loadPlayed(context: Context) {
        val prefs = context.getSharedPreferences("blindbandit_comms", Context.MODE_PRIVATE)
        played.clear()
        played.addAll(prefs.getStringSet("voice.played", emptySet()) ?: emptySet())
        val stored = prefs.getFloat("voice.rate", 1f)
        rate = validRate(stored)
    }

    fun setRate(context: Context, r: Float) {
        rate = validRate(r)
        context.getSharedPreferences("blindbandit_comms", Context.MODE_PRIVATE).edit().putFloat("voice.rate", rate).apply()
        // MediaPlayer has no reliable rate API before API 23 PlaybackParams; apply when available.
        if (Build.VERSION.SDK_INT >= 23) {
            runCatching {
                player?.playbackParams = player!!.playbackParams.setSpeed(rate)
            }
        }
        Announcer.announce(context, "Speed ${rateLabel()}")
        notifyListeners()
    }

    fun cycleRate(context: Context) {
        setRate(context, when {
            rate < 1.25f -> 1.5f
            rate < 1.75f -> 2f
            else -> 1f
        })
    }

    suspend fun toggle(context: Context, item: Item, download: suspend (JSONObject) -> ByteArray) {
        if (currentId == item.id && player != null) {
            if (playing) pause(context) else resume(context)
            return
        }
        play(context, item, download)
    }

    fun pause(context: Context) {
        runCatching { player?.pause() }
        playing = false
        main.removeCallbacks(tick)
        Announcer.announce(context, "Paused")
        notifyListeners()
    }

    private fun resume(context: Context) {
        requestFocus(context)
        val ok = runCatching { player?.start(); true }.getOrDefault(false)
        playing = ok == true && player?.isPlaying == true
        if (playing) {
            main.post(tick)
            Announcer.announce(context, "Playing")
        } else Announcer.announce(context, "Couldn't resume")
        notifyListeners()
    }

    suspend fun play(context: Context, item: Item, download: suspend (JSONObject) -> ByteArray) {
        stop(context, deactivate = false)
        register(item)
        loadingId = item.id
        notifyListeners()
        val plain = try {
            withContext(Dispatchers.IO) {
                cached(context, item.media) ?: download(item.media).also { cache(context, item.media, it) }
            }
        } catch (e: Exception) {
            loadingId = null
            Announcer.announce(context, "Couldn't play this voice message")
            notifyListeners()
            return
        }
        loadingId = null
        val file = withContext(Dispatchers.IO) {
            File(context.cacheDir, "voice-play-${item.id.take(40)}.m4a").also { it.writeBytes(plain) }
        }
        tempFile = file
        requestFocus(context)
        val p = MediaPlayer()
        try {
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            p.setDataSource(file.absolutePath)
            p.setOnCompletionListener { finished(context, item) }
            p.setOnErrorListener { _, _, _ ->
                playing = false
                Announcer.announce(context, "Audio playback failed")
                notifyListeners()
                true
            }
            p.prepare()
            if (Build.VERSION.SDK_INT >= 23) {
                runCatching { p.playbackParams = p.playbackParams.setSpeed(rate) }
            }
            player = p
            currentId = item.id
            elapsedMs = 0
            p.start()
            playing = p.isPlaying
            if (playing) {
                main.post(tick)
                Announcer.announce(context, "Playing")
                markPlayed(context, item)
            } else Announcer.announce(context, "Couldn't play this voice message")
        } catch (e: Exception) {
            runCatching { p.release() }
            player = null
            Announcer.announce(context, "Couldn't play this voice message")
        }
        notifyListeners()
    }

    fun skip(context: Context, seconds: Int) {
        val p = player ?: return
        val target = (p.currentPosition + seconds * 1000).coerceIn(0, (p.duration - 100).coerceAtLeast(0))
        p.seekTo(target)
        elapsedMs = target.toLong()
        Announcer.announce(context, clock(elapsedMs / 1000.0))
        notifyListeners()
    }

    fun stop(context: Context, deactivate: Boolean = true) {
        main.removeCallbacks(tick)
        runCatching { player?.stop() }
        runCatching { player?.release() }
        player = null
        playing = false
        currentId = null
        elapsedMs = 0
        tempFile?.delete()
        tempFile = null
        if (deactivate) abandonFocus(context)
        notifyListeners()
    }

    private fun finished(context: Context, item: Item) {
        playing = false
        main.removeCallbacks(tick)
        if (item.listenOnce) {
            clearCache(context, item.media)
            Announcer.announce(context, "Listen-once voice message finished")
        }
        val idx = order.indexOfFirst { it.id == item.id }
        val next = if (idx >= 0) order.drop(idx + 1).firstOrNull { !it.mine && it.id !in played && !it.listenOnce } else null
        if (next != null) {
            Announcer.announce(context, "Next voice message from ${next.from}")
            // Caller must re-invoke play with download; UI listens and may auto-continue.
            currentId = null
            notifyListeners()
        } else {
            stop(context)
        }
    }

    private fun markPlayed(context: Context, item: Item) {
        if (item.mine) return
        played += item.id
        val prefs = context.getSharedPreferences("blindbandit_comms", Context.MODE_PRIVATE)
        prefs.edit().putStringSet("voice.played", played.toList().takeLast(2000).toSet()).apply()
    }

    private fun cacheDir(context: Context) = File(context.cacheDir, "voice").also { it.mkdirs() }
    private fun cacheFile(context: Context, media: JSONObject): File? {
        val id = media.optString("attachment_id").ifBlank { return null }
        return File(cacheDir(context), "$id.m4a")
    }
    private fun cached(context: Context, media: JSONObject): ByteArray? {
        val f = cacheFile(context, media) ?: return null
        return if (f.exists() && f.length() > 0) f.readBytes() else null
    }
    private fun cache(context: Context, media: JSONObject, bytes: ByteArray) {
        if (media.optBoolean("view_once") || media.optBoolean("listen_once")) return
        cacheFile(context, media)?.writeBytes(bytes)
    }
    private fun clearCache(context: Context, media: JSONObject) {
        cacheFile(context, media)?.delete()
    }

    private fun requestFocus(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setOnAudioFocusChangeListener { }
                .build()
            focusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }

    private fun abandonFocus(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    fun validRate(r: Float) = if (r in 0.5f..2f) r else 1f
    fun clock(seconds: Double): String {
        val s = maxOf(0, seconds.toInt())
        return "%d:%02d".format(s / 60, s % 60)
    }

    fun isVoiceMedia(media: JSONObject?): Boolean {
        if (media == null) return false
        val mime = media.optString("mime")
        if (mime.startsWith("audio/")) return true
        val name = media.optString("filename").lowercase()
        return name.endsWith(".m4a") || name.endsWith(".aac") || name.endsWith(".mp3") || name == "voice.m4a"
    }
}

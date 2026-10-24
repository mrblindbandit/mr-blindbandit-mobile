package net.mrblindbandit.app.ai

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.net.Uri
import android.view.KeyEvent

/**
 * Android music control via YouTube Music (no MusicKit). Uses MEDIA_BUTTON + MediaSession when
 * a session is active, otherwise deep-links / market intents. TalkBack-friendly spoken status strings.
 */
object YouTubeMusicController {
    private const val YTM = "com.google.android.apps.youtube.music"
    private const val YT = "com.google.android.youtube"

    fun installed(context: Context): Boolean =
        runCatching { context.packageManager.getPackageInfo(YTM, 0); true }.getOrDefault(false)

    suspend fun run(context: Context, intent: MusicIntent): String = when (intent.action) {
        "pause" -> mediaKey(context, KeyEvent.KEYCODE_MEDIA_PAUSE) ?: "Paused."
        "resume" -> mediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY) ?: "Playing."
        "next" -> mediaKey(context, KeyEvent.KEYCODE_MEDIA_NEXT) ?: "Skipped to next."
        "previous" -> mediaKey(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS) ?: "Went to previous."
        "nowplaying" -> nowPlaying(context)
        "library" -> openSearch(context, "") + " Opened YouTube Music library."
        "search" -> search(context, intent.query)
        "queue", "play" -> play(context, intent.query, intent.kind)
        else -> "I don't know that music action."
    }

    private fun play(context: Context, query: String, kind: String): String {
        if (query.isBlank()) return mediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY) ?: "Playing."
        val q = when (kind) {
            "playlist" -> "$query playlist"
            "album" -> "$query album"
            "artist" -> "$query artist"
            else -> query
        }
        openSearch(context, q)
        // Also fire play after a short delay via media session if YTM already playing.
        mediaKey(context, KeyEvent.KEYCODE_MEDIA_PLAY)
        return "Searching YouTube Music for $q."
    }

    private fun search(context: Context, query: String): String {
        if (query.isBlank()) return "Say what to search for."
        openSearch(context, query)
        return "Opened YouTube Music search for $query."
    }

    private fun openSearch(context: Context, query: String): String {
        val encoded = Uri.encode(query)
        val intents = buildList {
            if (installed(context)) {
                add(Intent(Intent.ACTION_VIEW, Uri.parse("https://music.youtube.com/search?q=$encoded")).setPackage(YTM))
                add(Intent(Intent.ACTION_SEARCH).setPackage(YTM).putExtra("query", query))
            }
            add(Intent(Intent.ACTION_VIEW, Uri.parse("https://music.youtube.com/search?q=$encoded")))
            add(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$YTM")))
        }
        for (i in intents) {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (runCatching { context.startActivity(i); true }.getOrDefault(false)) {
                return if (installed(context)) "ok" else "YouTube Music is not installed. Opened the Play Store listing."
            }
        }
        return "Couldn't open YouTube Music."
    }

    private fun mediaKey(context: Context, keyCode: Int): String? {
        // Prefer an active MediaSession controller (TalkBack/MediaSession path).
        val msm = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        val controllers = runCatching {
            msm?.getActiveSessions(ComponentName(context, net.mrblindbandit.app.androidonly.BlindbanditNotificationListener::class.java))
        }.getOrNull().orEmpty().ifEmpty {
            // Without notification listener access, still try AUDIOSERVICE media keys.
            emptyList()
        }
        val ytm = controllers.firstOrNull { it.packageName == YTM || it.packageName == YT }
        if (ytm != null) {
            when (keyCode) {
                KeyEvent.KEYCODE_MEDIA_PLAY -> ytm.transportControls.play()
                KeyEvent.KEYCODE_MEDIA_PAUSE -> ytm.transportControls.pause()
                KeyEvent.KEYCODE_MEDIA_NEXT -> ytm.transportControls.skipToNext()
                KeyEvent.KEYCODE_MEDIA_PREVIOUS -> ytm.transportControls.skipToPrevious()
                else -> ytm.dispatchMediaButtonEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            return when (keyCode) {
                KeyEvent.KEYCODE_MEDIA_PAUSE -> "Paused."
                KeyEvent.KEYCODE_MEDIA_PLAY -> "Playing."
                KeyEvent.KEYCODE_MEDIA_NEXT -> "Skipped to next."
                KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "Went to previous."
                else -> "Done."
            }
        }
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        return null
    }

    private fun nowPlaying(context: Context): String {
        val msm = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        val controllers = runCatching {
            msm?.getActiveSessions(ComponentName(context, net.mrblindbandit.app.androidonly.BlindbanditNotificationListener::class.java))
        }.getOrNull().orEmpty()
        val c = controllers.firstOrNull { it.packageName == YTM || it.packageName == YT } ?: controllers.firstOrNull()
        val meta = c?.metadata
        val title = meta?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
        val artist = meta?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
        return when {
            !title.isNullOrBlank() && !artist.isNullOrBlank() -> "Now playing $title by $artist."
            !title.isNullOrBlank() -> "Now playing $title."
            else -> "Nothing is reporting as playing. Open YouTube Music and play something, or allow notification access so I can read the MediaSession."
        }
    }
}

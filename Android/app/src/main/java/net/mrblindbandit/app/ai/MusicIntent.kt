package net.mrblindbandit.app.ai

/**
 * Deterministic music command parser (iOS MusicIntent parity).
 * "play X" never depends on the language model deciding to call a tool.
 */
data class MusicIntent(
    val action: String, // play, pause, resume, next, previous, queue, library, nowplaying, search
    val query: String = "",
    val kind: String = "any",
) {
    companion object {
        fun parse(raw: String): MusicIntent? {
            var t = raw.lowercase().trim().trimEnd('.', '!', '?')
            for (p in listOf("hey ai ", "ai ", "yo ", "please ", "can you ", "could you ", "will you ", "bro ", "twin ")) {
                if (t.startsWith(p)) t = t.removePrefix(p)
            }
            if (t.endsWith(" please")) t = t.removeSuffix(" please")
            var mentionsMusic = false
            for (s in listOf(
                " on youtube music", " in youtube music", " from youtube music", " on yt music", " on youtube",
                " on apple music", " in apple music", " from apple music", " on music",
            )) {
                if (t.contains(s)) {
                    t = t.replace(s, "")
                    mentionsMusic = true
                }
            }
            t = t.trim()
            when (t) {
                "pause", "pause music", "pause the music", "stop", "stop music", "stop the music", "pause it", "stop playing" ->
                    return MusicIntent("pause")
                "resume", "resume music", "unpause", "continue playing", "keep playing", "play", "play music", "resume the music" ->
                    return MusicIntent("resume")
                "next", "skip", "skip song", "skip this", "skip this song", "next song", "next track", "skip it" ->
                    return MusicIntent("next")
                "previous", "previous song", "go back", "last song", "previous track", "back" ->
                    return MusicIntent("previous")
                "what's playing", "whats playing", "what is playing", "what song is this", "what's this song", "now playing" ->
                    return MusicIntent("nowplaying")
            }
            if (t.startsWith("play my library") || t.startsWith("shuffle my library") || t == "play my music" || t == "shuffle my music") {
                return MusicIntent("library", kind = if (t.contains("shuffle")) "shuffle" else "any")
            }
            for ((prefix, action) in listOf(
                "queue up " to "queue", "queue " to "queue", "add to queue " to "queue", "play next " to "queue",
                "put on " to "play", "play " to "play", "shuffle " to "play", "search " to "search", "find " to "search",
            )) {
                if (!t.startsWith(prefix)) continue
                var q = t.removePrefix(prefix).trim()
                val blocked = listOf("a game", "game", "the voice note", "this voice note", "voice note", "the video", "this video", "that video")
                if (blocked.any { q.startsWith(it) } && !mentionsMusic) return null
                var kind = "any"
                for ((k, words) in listOf(
                    "album" to listOf("the album ", "album "),
                    "playlist" to listOf("the playlist ", "playlist "),
                    "artist" to listOf("the artist ", "artist ", "songs by ", "music by "),
                    "song" to listOf("the song ", "song "),
                )) {
                    val w = words.firstOrNull { q.startsWith(it) } ?: continue
                    q = q.removePrefix(w); kind = k; break
                }
                if (q.endsWith(" playlist")) { q = q.removeSuffix(" playlist"); kind = "playlist" }
                if (q.endsWith(" album")) { q = q.removeSuffix(" album"); kind = "album" }
                if (kind == "any" && q.contains(" by ")) kind = "song"
                q = q.replace(" by ", " ").trim()
                if (q.isEmpty()) return MusicIntent("resume")
                return MusicIntent(action, q, kind)
            }
            return null
        }
    }
}

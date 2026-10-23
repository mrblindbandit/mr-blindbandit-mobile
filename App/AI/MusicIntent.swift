import Foundation
import os

/// Deterministic music command parser, so "play X" never depends on the language model deciding to call a tool.
struct MusicIntent: Equatable {
    var action: String   // play, pause, resume, next, previous, queue, library, nowplaying
    var query: String = ""
    var kind: String = "any"

    static func parse(_ raw: String) -> MusicIntent? {
        var t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        for p in ["hey ai ", "ai ", "yo ", "please ", "can you ", "could you ", "will you ", "bro ", "twin "] where t.hasPrefix(p) { t.removeFirst(p.count) }
        if t.hasSuffix(" please") { t.removeLast(7) }
        let onAM = [" on apple music", " in apple music", " from apple music", " on music"]
        var mentionsMusic = false
        for s in onAM where t.contains(s) { t = t.replacingOccurrences(of: s, with: ""); mentionsMusic = true }
        t = t.trimmingCharacters(in: .whitespaces)

        switch t {
        case "pause", "pause music", "pause the music", "stop", "stop music", "stop the music", "pause it", "stop playing": return .init(action: "pause")
        case "resume", "resume music", "unpause", "continue playing", "keep playing", "play", "play music", "resume the music": return .init(action: "resume")
        case "next", "skip", "skip song", "skip this", "skip this song", "next song", "next track", "skip it": return .init(action: "next")
        case "previous", "previous song", "go back", "last song", "previous track", "back": return .init(action: "previous")
        case "what's playing", "whats playing", "what is playing", "what song is this", "what's this song", "now playing": return .init(action: "nowplaying")
        default: break
        }
        if t.hasPrefix("play my library") || t.hasPrefix("shuffle my library") || t == "play my music" || t == "shuffle my music" {
            return .init(action: "library", kind: t.contains("shuffle") ? "shuffle" : "any")
        }
        for (prefix, action) in [("queue up ", "queue"), ("queue ", "queue"), ("add to queue ", "queue"), ("play next ", "queue"), ("put on ", "play"), ("play ", "play"), ("shuffle ", "play")] where t.hasPrefix(prefix) {
            var q = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            // Avoid hijacking non-music requests ("play a game", "play this voice note").
            let blocked = ["a game", "game", "the voice note", "this voice note", "voice note", "the video", "this video", "that video"]
            if blocked.contains(where: { q.hasPrefix($0) }) && !mentionsMusic { return nil }
            var kind = "any"
            for (k, words) in [("album", ["the album ", "album "]), ("playlist", ["the playlist ", "playlist "]), ("artist", ["the artist ", "artist ", "songs by ", "music by "]), ("song", ["the song ", "song "])] {
                if let w = words.first(where: { q.hasPrefix($0) }) { q.removeFirst(w.count); kind = k; break }
            }
            if q.hasSuffix(" playlist") { q.removeLast(9); kind = "playlist" }
            if q.hasSuffix(" album") { q.removeLast(6); kind = "album" }
            if kind == "any", q.contains(" by ") { kind = "song" }
            q = q.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return .init(action: "resume") }
            return .init(action: action, query: q.replacingOccurrences(of: " by ", with: " "), kind: kind)
        }
        return nil
    }
}

enum MusicLog {
    static let log = Logger(subsystem: "net.mrblindbandit.app", category: "music")
    /// Last real error, readable from Settings > AI (debug) and included in failure replies.
    nonisolated(unsafe) static var lastError = ""
    static func record(_ where_: String, _ error: Error) -> String {
        let text = "\(where_): \(error.localizedDescription) [\(String(describing: error))]"
        log.error("\(text, privacy: .public)")
        lastError = text
        return text
    }
}

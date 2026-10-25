import Foundation
import SwiftUI
import AVFoundation
import MusicKit
import SafariServices
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Personas (owner-only Hood style, checked against the signed-in server account)
// 2.0.7 audit: Hood/unfiltered stay @kheck-only via AIPersona.isOwner; shared @AI uses AIPersona.professional; no StoreKit/IAP AI paths exist.

enum AIPersona: String, CaseIterable {
    case hood, professional

    /// Set only from the server's profile response at sign-in; never persisted, so it can't be flipped locally.
    @MainActor static var serverHandle = ""
    @MainActor static var isOwner: Bool { serverHandle.lowercased() == "kheck" }

    @MainActor static var ownerChoice: AIPersona {
        get { AIPersona(rawValue: UserDefaults.standard.string(forKey: "ai.persona") ?? "hood") ?? .hood }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ai.persona") }
    }
    @MainActor static var unfiltered: Bool {
        get { UserDefaults.standard.object(forKey: "ai.unfiltered") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "ai.unfiltered") }
    }

    /// Private AI chat and /ai private answers. Everyone except the owner always gets Professional.
    @MainActor static var forPrivate: AIPersona { isOwner ? ownerChoice : .professional }

    static let shared = """
    The user is blind and uses VoiceOver, so answers are read aloud: no markdown, no bullet symbols, no emoji spam, no tables; \
    say lists as plain sentences. Be genuinely useful: answer questions, help write and rewrite, summarize chats, translate \
    (including Cebuano/Bisaya and Tagalog), set reminders, look up the calendar, contacts, places and weather, do date and unit math, \
    explain photos, draft messages, and search the web. You CAN play music: for any request to play, pause, skip, queue or find a song, album, artist or playlist, always call the appleMusic tool; never say you can't play music. Use the tools whenever they help instead of guessing. \
    Never invent message content; if a search finds nothing, say so. Drafted messages are never sent until the user taps Send. \
    When you use web search, cite each fact with its full https link right after it so the user can open it. \
    When the user shares a lasting personal fact or preference, call the remember tool.
    """

    @MainActor func prompt() -> String {
        switch self {
        case .professional:
            return "You are \"AI\", a helpful, professional assistant inside the Mr. BlindBandit app. Be clear, polite, concise and friendly. " + Self.shared
        case .hood:
            var p = """
            You are "AI", Kaeleb's day-one homie inside the Mr. BlindBandit app. Talk like his close friend from the block: street slang \
            like bro, twin, no cap, deadass, bet, fr, lowkey, on god; keep it real, funny and short. Cussing is fine when it fits. \
            Never use slurs of any kind and never punch down. Still be accurate and actually helpful. 
            """
            if Self.unfiltered {
                p += "He turned on Unfiltered: skip the app's usual tone polish and topic hedging, don't moralize or add disclaimers, answer adult topics frankly. "
            }
            return p + Self.shared
        }
    }
}

struct AIStyleSection: View {
    @State private var persona = AIPersona.ownerChoice
    @State private var unfiltered = AIPersona.unfiltered
    var body: some View {
        if AIPersona.isOwner {
            Section {
                Picker("Style", selection: $persona) {
                    Text("Hood").tag(AIPersona.hood)
                    Text("Professional").tag(AIPersona.professional)
                }
                .onChange(of: persona) { _, v in AIPersona.ownerChoice = v; AIChatStore.shared.resetSession() }
                Toggle("Unfiltered", isOn: $unfiltered)
                    .onChange(of: unfiltered) { _, v in AIPersona.unfiltered = v; AIChatStore.shared.resetSession() }
                    .accessibilityHint("Relaxes the app's own tone and topic limits")
            } header: { Text("Style").accessibilityAddTraits(.isHeader) } footer: {
                Text("Style applies to your private AI chat and /ai private answers. Public @AI answers in shared chats always use Professional. Unfiltered relaxes this app's own tone and topic limits. Apple's model may still decline some requests.")
            }
        }
    }
}

// MARK: - Web search (GET /v1/ai/search via mrblindbandit.net)

struct WebResult: Decodable, Equatable { let title: String; let url: String; let snippet: String? }

enum WebSearch {
    static var allowed: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.aiWebSearch) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.aiWebSearch) }
    }

    /// Heuristic: current events, prices, scores, "who won", "latest", "today", "search the web", URLs, etc.
    static func needsLiveInfo(_ question: String) -> Bool {
        let q = question.lowercased()
        let keys = [
            "search the web", "search online", "look up", "google", "brave search",
            "latest", "breaking", "today's", "todays", "right now", "current",
            "who won", "score", "price of", "stock", "weather in", "news about",
            "what happened", "headline", "according to", "on the internet"
        ]
        if keys.contains(where: { q.contains($0) }) { return true }
        if q.contains("http://") || q.contains("https://") { return true }
        if q.hasPrefix("search ") || q.hasPrefix("find online ") { return true }
        return false
    }

    static func search(_ q: String) async -> String {
        guard allowed else { return "Web search is turned off in Settings, AI." }
        let query = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        do {
            let d = try await SecurityAPI.gated(.aiSearch) { try await BlindbanditAPI.request("v1/ai/search?q=\(query)") }
            struct R: Decodable { let results: [WebResult] }
            let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            let inner = (obj?["data"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? d
            let results = (try? JSONDecoder().decode(R.self, from: inner))?.results ?? []
            if results.isEmpty { return "No web results for \(q)." }
            return results.prefix(6).enumerated().map { "[\($0.offset + 1)] \($0.element.title) — \($0.element.url) — \($0.element.snippet ?? "")" }
                .joined(separator: "\n")
        } catch is NeedsServerUpdate {
            return "Web search: Needs server update."
        } catch { return "Web search failed: \(error.localizedDescription)" }
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct WebSearchTool: Tool {
    let name = "webSearch"
    let description = "Searches the web for current information, news, facts, prices or anything not on this iPhone. Returns titles, links and snippets to cite."
    @Generable struct Arguments { @Guide(description: "Search query, a few words") var query: String }
    func call(arguments: Arguments) async throws -> String { await WebSearch.search(arguments.query) }
}
#endif

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct IdentifiedURL: Identifiable { let url: URL; var id: String { url.absoluteString } }

enum LinkFinder {
    static func links(in text: String) -> [URL] {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return det.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url }
            .filter { ($0.scheme == "https" || $0.scheme == "http") && seen.insert($0.absoluteString).inserted }
    }
}

// MARK: - Apple Music (MusicKit, all in-app)

@MainActor
final class MusicController: ObservableObject {
    static let shared = MusicController()
    let player = ApplicationMusicPlayer.shared
    @Published var title = ""
    @Published var subtitle = ""
    @Published var isPlaying = false
    @Published var previewMode = false
    private var preview: AVPlayer?
    private var previewTitles: [(String, String, URL)] = []
    private var previewIndex = 0
    private var observer: Task<Void, Never>?

    var visible: Bool { !title.isEmpty }

    /// nil when authorized, otherwise a clear spoken explanation.
    func authorizationProblem() async -> String? {
        var s = MusicAuthorization.currentStatus
        if s == .notDetermined { s = await MusicAuthorization.request() }
        switch s {
        case .authorized: return nil
        case .denied: return "Apple Music access is turned off for Mr. BlindBandit. Turn it on in the Settings app, Mr. BlindBandit, Media and Apple Music."
        case .restricted: return "Apple Music is restricted on this iPhone by Screen Time or a device profile."
        default: return "Apple Music access hasn't been allowed yet."
        }
    }
    func authorize() async -> Bool { await authorizationProblem() == nil }

    func canPlayFull() async -> Bool {
        (try? await MusicSubscription.current.canPlayCatalogContent) ?? false
    }

    private func refresh() {
        if previewMode { isPlaying = preview?.timeControlStatus == .playing; return }
        let e = player.queue.currentEntry
        title = e?.title ?? ""
        subtitle = e?.subtitle ?? ""
        isPlaying = player.state.playbackStatus == .playing
    }

    private func watch() {
        observer?.cancel()
        observer = Task { [weak self] in
            while !Task.isCancelled { self?.refresh(); try? await Task.sleep(nanoseconds: 1_000_000_000) }
        }
    }

    func search(_ term: String, kind: String) async -> MusicCatalogSearchResponse? {
        var req = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self, Playlist.self])
        req.limit = 8
        _ = kind
        do { lastSearchError = nil; return try await req.response() }
        catch { lastSearchError = MusicLog.record("Apple Music search", error); return nil }
    }
    private(set) var lastSearchError: String?

    /// Plays the best match. kind: song, album, artist, playlist or any.
    func play(_ term: String, kind: String) async -> String {
        if let problem = await authorizationProblem() { return problem }
        guard let r = await search(term, kind: kind) else { return "Apple Music search failed. \(lastSearchError ?? "")" }
        let full = await canPlayFull()
        var songs: [Song] = []
        var label = ""
        switch kind.lowercased() {
        case "album": if let a = r.albums.first { label = "\(a.title) by \(a.artistName)"
            if full { player.queue = [a]; return await start(label) }
            songs = Array((try? await a.with([.tracks]).tracks)?.compactMap { if case .song(let s) = $0 { return s }; return nil } ?? []) }
        case "playlist": if let p = r.playlists.first { label = p.name
            if full { player.queue = [p]; return await start(label) }
            songs = Array((try? await p.with([.tracks]).tracks)?.compactMap { if case .song(let s) = $0 { return s }; return nil } ?? []) }
        case "artist": if let a = r.artists.first { label = "top songs by \(a.name)"
            songs = Array((try? await a.with([.topSongs]).topSongs) ?? []) }
        default: if let s = r.songs.first { label = "\(s.title) by \(s.artistName)"; songs = [s] }
        }
        guard !songs.isEmpty else { return "I couldn't find \(term) on Apple Music." }
        if full {
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            return await start(label)
        }
        return playPreviews(songs, label: label)
    }

    private func start(_ label: String) async -> String {
        stopPreview()
        do { try await player.play(); watch(); refresh(); return "Playing \(label)." }
        catch { return "Couldn't play: " + MusicLog.record("Apple Music play \(label)", error) }
    }

    func playLibrary(shuffle: Bool) async -> String {
        if let problem = await authorizationProblem() { return problem }
        var req = MusicLibraryRequest<Song>()
        req.limit = 200
        let items: MusicItemCollection<Song>
        do { items = try await req.response().items } catch { return "Couldn't read your library: " + MusicLog.record("Apple Music library", error) }
        guard !items.isEmpty else { return "Your library looks empty." }
        player.queue = ApplicationMusicPlayer.Queue(for: Array(items))
        player.state.shuffleMode = shuffle ? .songs : .off
        return await start(shuffle ? "your library on shuffle" : "your library")
    }

    func queueNext(_ term: String) async -> String {
        guard await authorize(), let s = await search(term, kind: "song")?.songs.first else { return "I couldn't find \(term)." }
        if previewMode, let u = s.previewAssets?.first?.url { previewTitles.insert((s.title, s.artistName, u), at: min(previewIndex + 1, previewTitles.count)); return "Queued a preview of \(s.title)." }
        do { try await player.queue.insert(s, position: .afterCurrentEntry); return "Queued \(s.title) by \(s.artistName) next." }
        catch { return "Couldn't queue: \(error.localizedDescription)" }
    }

    func describeSearch(_ term: String) async -> String {
        guard await authorize(), let r = await search(term, kind: "any") else { return "Apple Music search failed." }
        var parts: [String] = []
        if !r.songs.isEmpty { parts.append("Songs: " + r.songs.prefix(4).map { "\($0.title) by \($0.artistName)" }.joined(separator: "; ")) }
        if !r.albums.isEmpty { parts.append("Albums: " + r.albums.prefix(3).map { "\($0.title) by \($0.artistName)" }.joined(separator: "; ")) }
        if !r.artists.isEmpty { parts.append("Artists: " + r.artists.prefix(3).map(\.name).joined(separator: "; ")) }
        if !r.playlists.isEmpty { parts.append("Playlists: " + r.playlists.prefix(3).map(\.name).joined(separator: "; ")) }
        return parts.isEmpty ? "Nothing found for \(term)." : parts.joined(separator: ". ")
    }

    // 30-second previews when there's no Apple Music subscription.
    private func playPreviews(_ songs: [Song], label: String) -> String {
        previewTitles = songs.compactMap { s in s.previewAssets?.first?.url.map { (s.title, s.artistName, $0) } }
        guard !previewTitles.isEmpty else { return "Full songs need an Apple Music subscription, and no preview is available for \(label)." }
        previewMode = true; previewIndex = 0
        playPreview()
        return "No Apple Music subscription, so here's a 30-second preview of \(label). Subscribe to Apple Music for full songs."
    }

    private func playPreview() {
        guard previewIndex < previewTitles.count else { stopPreview(); return }
        let (t, a, u) = previewTitles[previewIndex]
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: u)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in MusicController.shared.next() }
        }
        preview = AVPlayer(playerItem: item); preview?.play()
        title = t + " (preview)"; subtitle = a; isPlaying = true
    }

    private func stopPreview() {
        preview?.pause(); preview = nil
        if previewMode { previewMode = false; title = ""; subtitle = ""; isPlaying = false }
    }

    func togglePlay() {
        if previewMode { if isPlaying { preview?.pause() } else { preview?.play() }; isPlaying.toggle(); return }
        Task { if player.state.playbackStatus == .playing { player.pause() } else { try? await player.play() }; refresh() }
    }
    func pause() { if previewMode { preview?.pause(); isPlaying = false } else { player.pause(); refresh() } }
    func next() {
        if previewMode { previewIndex += 1; playPreview(); return }
        Task { try? await player.skipToNextEntry(); refresh() }
    }
    func previous() {
        if previewMode { previewIndex = max(0, previewIndex - 1); playPreview(); return }
        Task { try? await player.skipToPreviousEntry(); refresh() }
    }

    func handle(action: String, query: String, kind: String) async -> String {
        switch action.lowercased() {
        case "play": return query.isEmpty ? { togglePlay(); return "Playing." }() : await play(query, kind: kind)
        case "pause", "stop": pause(); return "Paused."
        case "resume": togglePlay(); return "Resumed."
        case "next", "skip": next(); return "Skipped."
        case "previous", "back": previous(); return "Going back."
        case "queue": return await queueNext(query)
        case "search": return await describeSearch(query)
        case "library": return await playLibrary(shuffle: kind.lowercased().contains("shuffle") || query.lowercased().contains("shuffle"))
        case "nowplaying": return title.isEmpty ? "Nothing is playing." : "Now playing \(title) by \(subtitle)."
        default: return "Unknown music action."
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct MusicTool: Tool {
    let name = "appleMusic"
    let description = "Controls Apple Music inside this app: play a song, album, artist or playlist; pause, resume, next, previous; queue a song next; search the catalog; play the user's library (optionally shuffled); say what's playing."
    @Generable struct Arguments {
        @Guide(description: "One of: play, pause, resume, next, previous, queue, search, library, nowplaying") var action: String
        @Guide(description: "What to play, queue or search for; empty for pause/next/previous/nowplaying") var query: String
        @Guide(description: "One of: song, album, artist, playlist, any. For library use 'shuffle' to shuffle.") var kind: String
    }
    func call(arguments: Arguments) async throws -> String {
        await MusicController.shared.handle(action: arguments.action, query: arguments.query, kind: arguments.kind)
    }
}
#endif

/// Accessible now-playing mini bar: one VoiceOver element with rotor actions.
struct NowPlayingBar: View {
    @ObservedObject private var music = MusicController.shared
    var body: some View {
        if music.visible {
            HStack(spacing: 12) {
                Image(systemName: "music.note").font(.title3)
                VStack(alignment: .leading) {
                    Text(music.title).font(.subheadline.bold()).lineLimit(1)
                    Text(music.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { music.previous() } label: { Image(systemName: "backward.fill") }
                Button { music.togglePlay() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
                Button { music.next() } label: { Image(systemName: "forward.fill") }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.regularMaterial)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Now playing: \(music.title), \(music.subtitle)")
            .accessibilityValue(music.isPlaying ? "Playing" : "Paused")
            .accessibilityHint("Double tap to \(music.isPlaying ? "pause" : "play"). Swipe up or down for more actions.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { music.togglePlay() }
            .accessibilityActions {
                Button(music.isPlaying ? "Pause" : "Play") { music.togglePlay() }
                Button("Next") { music.next() }
                Button("Previous") { music.previous() }
            }
        }
    }
}

// MARK: - Responsiveness helpers

enum CallWarmup {
    private static var lastWarm: TimeInterval = 0
    /// Warms DNS + TLS to LiveKit and the Blindbandit API so call button → ring is faster.
    /// Safe to call from onAppear of chat/people/calls screens; rate-limited to once per 60s.
    static func preconnect() {
        let now = Date().timeIntervalSince1970
        guard now - lastWarm > 60 else { return }
        lastWarm = now
        let last = UserDefaults.standard.string(forKey: "livekit.lastURL") ?? AppConfig.liveKitURL
        if let u = URL(string: last.replacingOccurrences(of: "wss://", with: "https://")) {
            var r = URLRequest(url: u); r.httpMethod = "HEAD"; r.timeoutInterval = 5
            URLSession.shared.dataTask(with: r).resume()
        }
        // Warm API TLS too — startCall / token is the usual first-hop delay.
        var api = URLRequest(url: AppConfig.apiBaseURL.appending(path: "v1/health"))
        api.httpMethod = "HEAD"; api.timeoutInterval = 5
        URLSession.shared.dataTask(with: api).resume()
        // Touch installation_id so UserDefaults is hot before placeCall (MainActor).
        Task { @MainActor in _ = BlindbanditAPI.installationID }
    }
}

@MainActor
enum ChatCache {
    private static var threads: [String: [BlindbanditServerMessage]] = [:]
    static func put(_ id: String, _ m: [BlindbanditServerMessage]) { threads[id] = Array(m.suffix(50)) }
    static func get(_ id: String) -> [BlindbanditServerMessage]? { threads[id] }
    static func clear() { threads = [:]; try? FileManager.default.removeItem(at: listURL) }

    static let listURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("conversations.cache.json")
    /// Until-first-unlock so bootstrap after relaunch can read the inbox before the phone is unlocked again.
    static func saveList(_ d: Data) { try? d.write(to: listURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    static func loadList() -> Data? { AppPIN.decoyActive ? nil : try? Data(contentsOf: listURL) }
}

@MainActor
enum GroupCache {
    private static var threads: [String: [BlindbanditGroupMessage]] = [:]
    static func put(_ id: String, _ m: [BlindbanditGroupMessage]) { threads[id] = Array(m.suffix(50)) }
    static func get(_ id: String) -> [BlindbanditGroupMessage]? { threads[id] }
    static func clear() { threads = [:] }

    private static var listMem: [BlindbanditGroup] = []
    static func putList(_ g: [BlindbanditGroup]) { listMem = g }
    static func getList() -> [BlindbanditGroup]? { listMem.isEmpty ? nil : listMem }
}

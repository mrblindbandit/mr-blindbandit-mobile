import Foundation

// MARK: - Disk cache (instant open, no spinner when warm)

enum BitesCache {
    private static var dir: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bites", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private static func url(_ key: String) -> URL {
        dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    static func save(_ data: Data, key: String) {
        try? data.write(to: url(key), options: [.atomic, .completeFileProtection])
    }

    static func load(_ key: String) -> Data? {
        try? Data(contentsOf: url(key))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - API

enum BitesAPI {
    /// Newsfeed (text posts) — primary Bites tab content while video BanditBites fill in.
    static func newsfeed(limit: Int = 40, offset: Int = 0, useCache: Bool = true) async throws -> [BiteItem] {
        let path = "v1/social/newsfeed?limit=\(limit)&offset=\(offset)"
        let cacheKey = "newsfeed-\(offset)"
        if useCache, offset == 0, let cached = BitesCache.load(cacheKey),
           let page = try? BlindbanditAPI.decode(SocialFeedPage.self, from: cached) {
            // Return cached immediately via caller; still refresh below when forced.
            _ = page
        }
        let data = try await BlindbanditAPI.request(path)
        if offset == 0 { BitesCache.save(data, key: cacheKey) }
        return try BlindbanditAPI.decode(SocialFeedPage.self, from: data).items
    }

    static func cachedNewsfeed() -> [BiteItem] {
        guard let cached = BitesCache.load("newsfeed-0"),
              let page = try? BlindbanditAPI.decode(SocialFeedPage.self, from: cached) else { return [] }
        return page.items
    }

    static func videoBites(limit: Int = 25, offset: Int = 0) async throws -> [BiteItem] {
        let data = try await BlindbanditAPI.request("v1/social/bites?limit=\(limit)&offset=\(offset)")
        if offset == 0 { BitesCache.save(data, key: "bites-0") }
        return try BlindbanditAPI.decode(SocialFeedPage.self, from: data).items
    }

    static func publishPost(body: String, media: [String] = []) async throws -> BiteItem {
        var fields: [String: Any] = ["body": String(body.prefix(4000))]
        if !media.isEmpty { fields["media"] = media }
        let data = try await BlindbanditAPI.request("v1/social/posts", method: "POST", body: fields)
        // Response may be the post itself or wrapped; try flexible decode
        if let item = try? BlindbanditAPI.decode(BiteItem.self, from: data) { return item }
        // Fallback optimistic shell
        return BiteItem(
            id: "local-\(UUID().uuidString)",
            body: body,
            caption: nil,
            media: media,
            video_url: nil,
            poster_url: nil,
            created_at: Date().timeIntervalSince1970 * 1000,
            author: BiteAuthor(handle: "me"),
            likes: 0,
            comments: 0,
            liked_by_me: false,
            my_reaction: nil,
            kind: .post
        )
    }

    /// Manual memberwise for optimistic UI (BiteItem is Decodable-only otherwise).
    static func makeLocalPost(body: String, handle: String, displayName: String, avatar: String?, verified: Bool) -> BiteItem {
        BiteItem(
            id: "local-\(UUID().uuidString)",
            body: body,
            caption: nil,
            media: [],
            video_url: nil,
            poster_url: nil,
            created_at: Date().timeIntervalSince1970 * 1000,
            author: BiteAuthor(handle: handle, display_name: displayName, avatar_url: avatar, verified: verified),
            likes: 0,
            comments: 0,
            liked_by_me: false,
            my_reaction: nil,
            kind: .post
        )
    }

    static func like(postID: String) async throws {
        _ = try await BlindbanditAPI.request("v1/social/posts/\(BlindbanditAPI.escape(postID))/like", method: "POST", body: [:])
    }

    static func unlike(postID: String) async throws {
        _ = try await BlindbanditAPI.request("v1/social/posts/\(BlindbanditAPI.escape(postID))/like", method: "DELETE")
    }

    static func react(postID: String, reaction: String = "like") async throws {
        _ = try await BlindbanditAPI.request(
            "v1/social/posts/\(BlindbanditAPI.escape(postID))/react",
            method: "POST",
            body: ["reaction": reaction]
        )
    }

    static func comments(postID: String, limit: Int = 50) async throws -> [BiteComment] {
        let data = try await BlindbanditAPI.request("v1/social/posts/\(BlindbanditAPI.escape(postID))/comments?limit=\(limit)")
        struct Page: Decodable { let items: [BiteComment] }
        return try BlindbanditAPI.decode(Page.self, from: data).items
    }

    static func addComment(postID: String, body: String) async throws {
        _ = try await BlindbanditAPI.request(
            "v1/social/posts/\(BlindbanditAPI.escape(postID))/comments",
            method: "POST",
            body: ["body": String(body.prefix(2000))]
        )
    }

    static func deletePost(id: String) async throws {
        _ = try await BlindbanditAPI.request("v1/social/posts/\(BlindbanditAPI.escape(id))", method: "DELETE")
    }

    static func report(targetType: String, targetID: String, reason: String, details: String = "") async throws {
        var body: [String: Any] = [
            "target_type": targetType,
            "target_id": targetID,
            "reason": String(reason.prefix(200))
        ]
        if !details.isEmpty { body["details"] = String(details.prefix(2000)) }
        _ = try await BlindbanditAPI.request("v1/social/reports", method: "POST", body: body)
    }

    // MARK: Profiles

    static func profileFull(handle: String) async throws -> SocialProfileFull {
        let h = BlindbanditAPI.escape(handle.lowercased())
        let data = try await BlindbanditAPI.request("v1/social/profiles/\(h)/full")
        BitesCache.save(data, key: "profile-\(h)")
        return try BlindbanditAPI.decode(SocialProfileFull.self, from: data)
    }

    static func cachedProfile(handle: String) -> SocialProfileFull? {
        let h = handle.lowercased()
        guard let data = BitesCache.load("profile-\(h)") else { return nil }
        return try? BlindbanditAPI.decode(SocialProfileFull.self, from: data)
    }

    static func prefetchProfile(handle: String) {
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        Task { _ = try? await profileFull(handle: h) }
    }

    static func follow(handle: String) async throws {
        _ = try await BlindbanditAPI.request(
            "v1/social/profiles/\(BlindbanditAPI.escape(handle))/follow",
            method: "POST",
            body: [:]
        )
    }

    static func unfollow(handle: String) async throws {
        _ = try await BlindbanditAPI.request(
            "v1/social/profiles/\(BlindbanditAPI.escape(handle))/follow",
            method: "DELETE"
        )
    }

    static func followers(handle: String, limit: Int = 50, offset: Int = 0) async throws -> [BiteAuthor] {
        let data = try await BlindbanditAPI.request(
            "v1/social/profiles/\(BlindbanditAPI.escape(handle))/followers?limit=\(limit)&offset=\(offset)"
        )
        return try BlindbanditAPI.decode(SocialListPage.self, from: data).items
    }

    static func following(handle: String, limit: Int = 50, offset: Int = 0) async throws -> [BiteAuthor] {
        let data = try await BlindbanditAPI.request(
            "v1/social/profiles/\(BlindbanditAPI.escape(handle))/following?limit=\(limit)&offset=\(offset)"
        )
        return try BlindbanditAPI.decode(SocialListPage.self, from: data).items
    }

    static func profilePosts(handle: String, limit: Int = 40) async throws -> [BiteItem] {
        let data = try await BlindbanditAPI.request(
            "v1/social/profiles/\(BlindbanditAPI.escape(handle))/posts?limit=\(limit)"
        )
        return try BlindbanditAPI.decode(SocialFeedPage.self, from: data).items
    }
}

// Memberwise init for BiteItem (Decodable synthesis removed default memberwise)
extension BiteItem {
    init(id: String, body: String, caption: String?, media: [String], video_url: String?, poster_url: String?,
         created_at: Double, author: BiteAuthor, likes: Int, comments: Int, liked_by_me: Bool,
         my_reaction: String?, kind: Kind) {
        self.id = id; self.body = body; self.caption = caption; self.media = media
        self.video_url = video_url; self.poster_url = poster_url; self.created_at = created_at
        self.author = author; self.likes = likes; self.comments = comments
        self.liked_by_me = liked_by_me; self.my_reaction = my_reaction; self.kind = kind
    }
}

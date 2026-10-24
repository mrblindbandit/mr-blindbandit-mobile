import Foundation

// MARK: - Bandit Bites / social feed models (flexible decode for live API)

struct BiteAuthor: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var handle: String
    var display_name: String
    var avatar_url: String?
    var verified: Bool

    init(id: String = "", handle: String, display_name: String? = nil, avatar_url: String? = nil, verified: Bool = false) {
        self.handle = handle
        self.id = id.isEmpty ? handle : id
        self.display_name = (display_name?.isEmpty == false ? display_name! : handle)
        self.avatar_url = avatar_url
        self.verified = verified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
        id = (try? c.decode(String.self, forKey: .id)) ?? handle
        let name = try? c.decodeIfPresent(String.self, forKey: .display_name)
        display_name = (name?.isEmpty == false ? name! : handle)
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
        verified = FlexibleBool.decode(c, .verified) ?? false
    }

    enum CodingKeys: String, CodingKey { case id, handle, display_name, avatar_url, verified }
}

struct BiteReactions: Codable, Equatable {
    var like: Int = 0
    var love: Int = 0
    var fire: Int = 0
    var laugh: Int = 0
    var wow: Int = 0
    var sad: Int = 0
    var total: Int = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        like = (try? c.decode(Int.self, forKey: .like)) ?? 0
        love = (try? c.decode(Int.self, forKey: .love)) ?? 0
        fire = (try? c.decode(Int.self, forKey: .fire)) ?? 0
        laugh = (try? c.decode(Int.self, forKey: .laugh)) ?? 0
        wow = (try? c.decode(Int.self, forKey: .wow)) ?? 0
        sad = (try? c.decode(Int.self, forKey: .sad)) ?? 0
        total = (try? c.decode(Int.self, forKey: .total)) ?? (like + love + fire + laugh + wow + sad)
    }

    enum CodingKeys: String, CodingKey { case like, love, fire, laugh, wow, sad, total }
}

/// One feed item: text post from newsfeed/feed, or short video from BanditBites.
struct BiteItem: Identifiable, Equatable, Decodable {
    let id: String
    var body: String
    var caption: String?
    var media: [String]
    var video_url: String?
    var poster_url: String?
    var created_at: Double
    var author: BiteAuthor
    var likes: Int
    var comments: Int
    var liked_by_me: Bool
    var my_reaction: String?
    var kind: Kind

    enum Kind: String { case post, bite }

    init(id: String, body: String, caption: String?, media: [String], video_url: String?, poster_url: String?,
         created_at: Double, author: BiteAuthor, likes: Int, comments: Int, liked_by_me: Bool,
         my_reaction: String?, kind: Kind) {
        self.id = id; self.body = body; self.caption = caption; self.media = media
        self.video_url = video_url; self.poster_url = poster_url; self.created_at = created_at
        self.author = author; self.likes = likes; self.comments = comments
        self.liked_by_me = liked_by_me; self.my_reaction = my_reaction; self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        caption = try? c.decodeIfPresent(String.self, forKey: .caption)
        media = (try? c.decode([String].self, forKey: .media)) ?? []
        video_url = try? c.decodeIfPresent(String.self, forKey: .video_url)
        poster_url = try? c.decodeIfPresent(String.self, forKey: .poster_url)
        if let d = try? c.decode(Double.self, forKey: .created_at) {
            created_at = d
        } else if let i = try? c.decode(Int.self, forKey: .created_at) {
            created_at = Double(i)
        } else {
            created_at = 0
        }
        author = (try? c.decode(BiteAuthor.self, forKey: .author))
            ?? BiteAuthor(handle: (try? c.decode(String.self, forKey: .handle)) ?? "unknown")
        likes = (try? c.decode(Int.self, forKey: .likes)) ?? 0
        if let reactions = try? c.decode(BiteReactions.self, forKey: .reactions), likes == 0 {
            likes = reactions.total > 0 ? reactions.total : reactions.like
        }
        comments = (try? c.decode(Int.self, forKey: .comments)) ?? 0
        liked_by_me = FlexibleBool.decode(c, .liked_by_me) ?? false
        my_reaction = try? c.decodeIfPresent(String.self, forKey: .my_reaction)
        if video_url != nil || (try? c.decodeIfPresent(String.self, forKey: .product)) == "BanditBites" {
            kind = .bite
        } else {
            kind = .post
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, body, caption, media, video_url, poster_url, created_at, author, likes, comments
        case liked_by_me, my_reaction, reactions, handle, product
    }

    var displayText: String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var accessibilitySummary: String {
        var parts = ["\(author.display_name)"]
        if author.verified { parts.append("Verified") }
        parts.append("@\(author.handle)")
        let text = displayText
        if !text.isEmpty { parts.append(text) }
        if likes > 0 { parts.append("\(likes) likes") }
        if comments > 0 { parts.append("\(comments) comments") }
        if liked_by_me { parts.append("Liked by you") }
        return parts.joined(separator: ", ")
    }
}

struct BiteComment: Identifiable, Decodable, Equatable {
    let id: String
    var body: String
    var created_at: Double
    var author: BiteAuthor

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        if let d = try? c.decode(Double.self, forKey: .created_at) {
            created_at = d
        } else if let i = try? c.decode(Int.self, forKey: .created_at) {
            created_at = Double(i)
        } else {
            created_at = 0
        }
        author = (try? c.decode(BiteAuthor.self, forKey: .author))
            ?? BiteAuthor(handle: (try? c.decode(String.self, forKey: .handle)) ?? "unknown")
    }

    enum CodingKeys: String, CodingKey { case id, body, created_at, author, handle }
}

/// Full public profile from GET /v1/social/profiles/{handle}/full
struct SocialProfileFull: Identifiable, Decodable, Equatable {
    let id: String
    var handle: String
    var display_name: String
    var bio: String?
    var avatar_url: String?
    var cover_url: String?
    var location: String?
    var website: String?
    var verified: Bool
    var is_artist: Bool
    var followers: Int
    var following: Int
    var posts: Int
    var bites: Int
    var is_following: Bool
    var role: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
        id = (try? c.decode(String.self, forKey: .id)) ?? handle
        let name = try? c.decodeIfPresent(String.self, forKey: .display_name)
        display_name = (name?.isEmpty == false ? name! : handle)
        bio = try? c.decodeIfPresent(String.self, forKey: .bio)
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
        cover_url = try? c.decodeIfPresent(String.self, forKey: .cover_url)
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        website = try? c.decodeIfPresent(String.self, forKey: .website)
        verified = FlexibleBool.decode(c, .verified) ?? false
        is_artist = FlexibleBool.decode(c, .is_artist) ?? false
        followers = (try? c.decode(Int.self, forKey: .followers)) ?? 0
        following = (try? c.decode(Int.self, forKey: .following)) ?? 0
        posts = (try? c.decode(Int.self, forKey: .posts)) ?? 0
        bites = (try? c.decode(Int.self, forKey: .bites)) ?? 0
        is_following = FlexibleBool.decode(c, .is_following) ?? false
        role = try? c.decodeIfPresent(String.self, forKey: .role)
    }

    enum CodingKeys: String, CodingKey {
        case id, handle, display_name, bio, avatar_url, cover_url, location, website
        case verified, is_artist, followers, following, posts, bites, is_following, role
    }

    var accessibilitySummary: String {
        var parts = [display_name]
        if verified { parts.append("Verified") }
        parts.append("@\(handle)")
        if let bio, !bio.isEmpty { parts.append(bio) }
        parts.append("\(bites) Bites")
        parts.append("\(followers) followers")
        parts.append("\(following) following")
        if is_following { parts.append("Following") }
        return parts.joined(separator: ", ")
    }
}

struct SocialFeedPage: Decodable {
    var items: [BiteItem]
    var limit: Int?
    var offset: Int?
    var product: String?
}

struct SocialListPage: Decodable {
    var items: [BiteAuthor]
    var limit: Int?
    var offset: Int?
}

struct AdminOverview: Decodable {
    var users: Int?
    var posts: Int?
    var bites: Int?
    var reports_open: Int?
    var reports: Int?
    var verified: Int?
    // Tolerate nested shapes
    var stats: Stats?

    struct Stats: Decodable {
        var users: Int?
        var posts: Int?
        var bites: Int?
        var reports_open: Int?
        var open_reports: Int?
    }

    var usersCount: Int { users ?? stats?.users ?? 0 }
    var postsCount: Int { posts ?? stats?.posts ?? 0 }
    var openReportsCount: Int { reports_open ?? stats?.reports_open ?? stats?.open_reports ?? reports ?? 0 }
}

struct AdminReport: Identifiable, Decodable, Equatable {
    let id: String
    var target_type: String?
    var target_id: String?
    var reason: String?
    var details: String?
    var status: String?
    var created_at: Double?
    var reporter_handle: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        target_type = try? c.decodeIfPresent(String.self, forKey: .target_type)
        target_id = try? c.decodeIfPresent(String.self, forKey: .target_id)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        details = try? c.decodeIfPresent(String.self, forKey: .details)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        if let d = try? c.decode(Double.self, forKey: .created_at) { created_at = d }
        else if let i = try? c.decode(Int.self, forKey: .created_at) { created_at = Double(i) }
        reporter_handle = try? c.decodeIfPresent(String.self, forKey: .reporter_handle)
    }

    enum CodingKeys: String, CodingKey {
        case id, target_type, target_id, reason, details, status, created_at, reporter_handle
    }
}

struct AdminUserRow: Identifiable, Decodable, Equatable {
    let id: String
    var handle: String
    var display_name: String
    var verified: Bool
    var avatar_url: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
        id = (try? c.decode(String.self, forKey: .id)) ?? handle
        let name = try? c.decodeIfPresent(String.self, forKey: .display_name)
        display_name = (name?.isEmpty == false ? name! : handle)
        verified = FlexibleBool.decode(c, .verified) ?? false
        avatar_url = try? c.decodeIfPresent(String.self, forKey: .avatar_url)
    }

    enum CodingKeys: String, CodingKey { case id, handle, display_name, verified, avatar_url }
}

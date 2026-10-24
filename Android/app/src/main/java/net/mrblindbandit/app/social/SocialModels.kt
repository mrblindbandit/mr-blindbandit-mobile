package net.mrblindbandit.app.social

import net.mrblindbandit.app.connect.lBool
import net.mrblindbandit.app.connect.lLong
import net.mrblindbandit.app.connect.lString
import net.mrblindbandit.app.connect.lTime
import org.json.JSONObject

data class SocialAuthor(
    val id: String,
    val handle: String,
    val displayName: String,
    val avatarUrl: String,
    val verified: Boolean,
) {
    companion object {
        fun parse(row: JSONObject?) = SocialAuthor(
            id = row?.lString("id").orEmpty(),
            handle = row?.lString("handle").orEmpty(),
            displayName = row?.lString("display_name", "name").orEmpty().ifBlank { "@${row?.lString("handle").orEmpty()}" },
            avatarUrl = absoluteMediaUrl(row?.lString("avatar_url").orEmpty()),
            verified = row?.lBool("verified") == true,
        )
    }
}

data class BanditBite(
    val id: String,
    val caption: String,
    val videoUrl: String,
    val posterUrl: String,
    val viewCount: Long,
    val createdAt: Long?,
    val author: SocialAuthor,
    val myReaction: String?,
    val reactionTotal: Long,
) {
    companion object {
        fun parse(row: JSONObject): BanditBite? {
            val id = row.lString("id")
            if (id.isBlank()) return null
            val reactions = row.optJSONObject("reactions")
            return BanditBite(
                id = id,
                caption = row.lString("caption", "body"),
                videoUrl = absoluteMediaUrl(row.lString("video_url")),
                posterUrl = absoluteMediaUrl(row.lString("poster_url")),
                viewCount = row.lLong("view_count") ?: 0L,
                createdAt = row.lTime("created_at"),
                author = SocialAuthor.parse(row.optJSONObject("author")),
                myReaction = row.lString("my_reaction").ifBlank { null },
                reactionTotal = reactions?.lLong("total") ?: row.lLong("likes") ?: 0L,
            )
        }
    }
}

data class SocialPost(
    val id: String,
    val body: String,
    val createdAt: Long?,
    val author: SocialAuthor,
    val myReaction: String?,
    val likes: Long,
    val comments: Long,
    val mediaUrls: List<String>,
) {
    companion object {
        fun parse(row: JSONObject): SocialPost? {
            val id = row.lString("id")
            if (id.isBlank()) return null
            val media = row.optJSONArray("media")
            val urls = buildList {
                if (media != null) for (i in 0 until media.length()) {
                    val item = media.opt(i)
                    when (item) {
                        is String -> add(absoluteMediaUrl(item))
                        is JSONObject -> add(absoluteMediaUrl(item.lString("url", "src")))
                    }
                }
            }.filter { it.isNotBlank() }
            return SocialPost(
                id = id,
                body = row.lString("body", "text"),
                createdAt = row.lTime("created_at"),
                author = SocialAuthor.parse(row.optJSONObject("author")),
                myReaction = row.lString("my_reaction").ifBlank { null },
                likes = row.lLong("likes") ?: row.optJSONObject("reactions")?.lLong("total") ?: 0L,
                comments = row.lLong("comments") ?: 0L,
                mediaUrls = urls,
            )
        }
    }
}

data class PublicProfile(
    val id: String,
    val handle: String,
    val displayName: String,
    val bio: String,
    val avatarUrl: String,
    val coverUrl: String,
    val location: String,
    val website: String,
    val verified: Boolean,
    val isArtist: Boolean,
    val followers: Long,
    val following: Long,
    val posts: Long,
    val bites: Long,
    val isFollowing: Boolean,
) {
    companion object {
        fun parse(row: JSONObject): PublicProfile? {
            val handle = row.lString("handle")
            if (handle.isBlank()) return null
            return PublicProfile(
                id = row.lString("id"),
                handle = handle,
                displayName = row.lString("display_name").ifBlank { "@$handle" },
                bio = row.lString("bio"),
                avatarUrl = absoluteMediaUrl(row.lString("avatar_url")),
                coverUrl = absoluteMediaUrl(row.lString("cover_url")),
                location = row.lString("location"),
                website = row.lString("website"),
                verified = row.lBool("verified"),
                isArtist = row.lBool("is_artist"),
                followers = row.lLong("followers") ?: 0L,
                following = row.lLong("following") ?: 0L,
                posts = row.lLong("posts") ?: 0L,
                bites = row.lLong("bites") ?: 0L,
                isFollowing = row.lBool("is_following"),
            )
        }
    }
}

/** Resolve relative CDN paths from the API to absolute https URLs. */
fun absoluteMediaUrl(raw: String): String {
    val u = raw.trim()
    if (u.isEmpty()) return ""
    if (u.startsWith("http://") || u.startsWith("https://")) return u
    if (u.startsWith("//")) return "https:$u"
    val web = "https://mrblindbandit.net"
    return if (u.startsWith("/")) web + u else "$web/$u"
}


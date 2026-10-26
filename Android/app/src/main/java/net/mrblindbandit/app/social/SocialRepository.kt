package net.mrblindbandit.app.social

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.mrblindbandit.app.auth.ClerkAuthService
import net.mrblindbandit.app.config.AppConfig
import net.mrblindbandit.app.connect.BlindbanditApiEnvelope
import net.mrblindbandit.app.connect.DeviceIdentity
import net.mrblindbandit.app.connect.items
import net.mrblindbandit.app.connect.lString
import net.mrblindbandit.app.connect.normalizeHandle
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * BanditBites + newsfeed + profiles + Social Admin client.
 * Public GETs work signed-out; writes and admin need a Clerk session.
 */
class SocialRepository(
    context: Context,
    private val auth: ClerkAuthService,
) {
    private val appContext = context.applicationContext
    val cache = SocialCache(appContext)

    suspend fun bites(limit: Int = 30, useCacheFirst: Boolean = true): List<BanditBite> {
        if (useCacheFirst) {
            cache.loadBites()?.items()?.mapNotNull { BanditBite.parse(it) }?.takeIf { it.isNotEmpty() }?.let { cached ->
                // Return cache immediately path is handled by UI; still refresh below when called fresh.
            }
        }
        val data = request("/v1/social/bites?limit=$limit", allowPublic = true)
        cache.saveBites(data)
        return data.items().mapNotNull { BanditBite.parse(it) }
    }

    fun cachedBites(): List<BanditBite> =
        cache.loadBites()?.items()?.mapNotNull { BanditBite.parse(it) }.orEmpty()

    suspend fun newsfeed(limit: Int = 40, filter: String = "all"): List<SocialPost> {
        val data = request("/v1/social/newsfeed?limit=$limit&filter=${enc(filter)}", allowPublic = true)
        cache.saveNewsfeed(data)
        return data.items().mapNotNull { SocialPost.parse(it) }
    }

    fun cachedNewsfeed(): List<SocialPost> =
        cache.loadNewsfeed()?.items()?.mapNotNull { SocialPost.parse(it) }.orEmpty()

    suspend fun publishBite(caption: String, videoUrl: String, posterUrl: String = ""): BanditBite {
        val body = JSONObject()
            .put("caption", caption.trim().take(2200))
            .put("video_url", videoUrl.trim())
        if (posterUrl.isNotBlank()) body.put("poster_url", posterUrl.trim())
        val data = request("/v1/social/bites", method = "POST", body = body)
        return BanditBite.parse(data) ?: error("Server accepted the BanditBite but returned no id.")
    }

    suspend fun publishPost(bodyText: String): SocialPost {
        val data = request(
            "/v1/social/posts",
            method = "POST",
            body = JSONObject().put("body", bodyText.trim().take(4000)),
        )
        return SocialPost.parse(data) ?: error("Server accepted the post but returned no id.")
    }

    suspend fun reactBite(id: String, reaction: String = "like") {
        request("/v1/social/bites/${enc(id)}/react", method = "POST", body = JSONObject().put("reaction", reaction))
    }

    suspend fun markBiteViewed(id: String) {
        runCatching {
            request("/v1/social/bites/${enc(id)}/view", method = "POST", body = JSONObject(), allowPublic = true)
        }
    }

    suspend fun removeBite(id: String) {
        // Owner/admin delete — same path web uses for the author; Social Admin uses session role.
        request("/v1/social/bites/${enc(id)}", method = "DELETE")
    }

    suspend fun profile(handle: String, useCacheFirst: Boolean = true): PublicProfile {
        val h = normalizeHandle(handle)
        if (useCacheFirst) cache.loadProfile(h)?.let { PublicProfile.parse(it) }?.let { return it }
        val data = request("/v1/social/profiles/${enc(h)}/full", allowPublic = true)
        cache.saveProfile(h, data)
        return PublicProfile.parse(data) ?: error("Profile @$h was empty.")
    }

    fun cachedProfile(handle: String): PublicProfile? =
        cache.loadProfile(normalizeHandle(handle))?.let { PublicProfile.parse(it) }

    suspend fun refreshProfile(handle: String): PublicProfile {
        val h = normalizeHandle(handle)
        val data = request("/v1/social/profiles/${enc(h)}/full", allowPublic = true)
        cache.saveProfile(h, data)
        return PublicProfile.parse(data) ?: error("Profile @$h was empty.")
    }

    suspend fun followers(handle: String): List<SocialAuthor> {
        val h = normalizeHandle(handle)
        val data = request("/v1/social/profiles/${enc(h)}/followers?limit=100", allowPublic = true)
        cache.saveFollowers(h, data)
        return data.items().map { SocialAuthor.parse(it) }
    }

    suspend fun following(handle: String): List<SocialAuthor> {
        val h = normalizeHandle(handle)
        val data = request("/v1/social/profiles/${enc(h)}/following?limit=100", allowPublic = true)
        cache.saveFollowing(h, data)
        return data.items().map { SocialAuthor.parse(it) }
    }

    fun cachedFollowers(handle: String): List<SocialAuthor> =
        cache.loadFollowers(normalizeHandle(handle))?.items()?.map { SocialAuthor.parse(it) }.orEmpty()

    fun cachedFollowing(handle: String): List<SocialAuthor> =
        cache.loadFollowing(normalizeHandle(handle))?.items()?.map { SocialAuthor.parse(it) }.orEmpty()

    suspend fun follow(handle: String) {
        request("/v1/social/profiles/${enc(normalizeHandle(handle))}/follow", method = "POST", body = JSONObject())
    }

    suspend fun unfollow(handle: String) {
        request("/v1/social/profiles/${enc(normalizeHandle(handle))}/follow", method = "DELETE")
    }

    // —— Social Admin (@kheck / platform staff; server enforces role) ——

    suspend fun adminOverview(): JSONObject = request("/v1/social/admin/overview")

    suspend fun adminSearchUsers(q: String): List<JSONObject> =
        request("/v1/social/admin/users?limit=40&q=${enc(q)}").items()

    suspend fun adminVerify(userId: String) {
        request("/v1/social/admin/users/${enc(userId)}/verify", method = "POST", body = JSONObject())
    }

    suspend fun adminUnverify(userId: String) {
        request("/v1/social/admin/users/${enc(userId)}/unverify", method = "POST", body = JSONObject())
    }

    /** Resolve @handle via admin search, then verify/unverify. */
    suspend fun adminSetVerifiedByUsername(username: String, verified: Boolean): String {
        val handle = normalizeHandle(username)
        val matches = adminSearchUsers(handle)
        val user = matches.firstOrNull { it.lString("handle").equals(handle, ignoreCase = true) }
            ?: matches.firstOrNull()
            ?: error("No account matched @$handle.")
        val id = user.lString("id")
        if (id.isBlank()) error("Matched @$handle but the profile id was missing.")
        if (verified) adminVerify(id) else adminUnverify(id)
        // Bust local profile cache so badge updates on next open.
        cache.saveProfile(handle, request("/v1/social/profiles/${enc(handle)}/full", allowPublic = true))
        return user.lString("handle").ifBlank { handle }
    }

    suspend fun adminBan(userId: String, reason: String = "Banned by Social Admin") {
        request("/v1/social/admin/users/${enc(userId)}/ban", method = "POST", body = JSONObject().put("reason", reason))
    }

    suspend fun adminMutePosts(userId: String, mute: Boolean) {
        request(
            "/v1/social/admin/users/${enc(userId)}/restrictions",
            method = "PATCH",
            body = JSONObject().put("mute_posts", mute),
        )
    }

    suspend fun adminReinstate(userId: String) {
        request("/v1/social/admin/users/${enc(userId)}/reinstate", method = "POST", body = JSONObject())
    }

    suspend fun adminOpenReports(): List<JSONObject> =
        request("/v1/social/admin/reports?status=open&limit=50").items()

    suspend fun adminResolveReport(reportId: String, status: String) {
        request(
            "/v1/social/admin/reports/${enc(reportId)}/resolve",
            method = "POST",
            body = JSONObject().put("status", status),
        )
    }

    suspend fun adminPendingVerification(): List<JSONObject> =
        request("/v1/social/admin/verification?status=pending&limit=50").items()

    suspend fun adminReviewVerification(id: String, approve: Boolean) {
        request(
            "/v1/social/verification/${enc(id)}/review",
            method = "POST",
            body = JSONObject().put("approve", approve),
        )
    }

    suspend fun likePost(id: String) {
        request("/v1/social/posts/${enc(id)}/like", method = "POST", body = JSONObject())
    }

    suspend fun unlikePost(id: String) {
        runCatching { request("/v1/social/posts/${enc(id)}/like", method = "DELETE") }
    }

    suspend fun reactPost(id: String, reaction: String = "like") {
        request("/v1/social/posts/${enc(id)}/react", method = "POST", body = JSONObject().put("reaction", reaction))
    }

    /**
     * Two-step public media upload for BanditBite video:
     * POST /v1/media/uploads → PUT upload_url → POST /v1/media/{id}/complete → public content URL.
     */
    suspend fun uploadBiteVideo(bytes: ByteArray, mime: String = "video/mp4"): String = withContext(Dispatchers.IO) {
        require(bytes.isNotEmpty()) { "Choose a video first." }
        require(bytes.size <= 100 * 1024 * 1024) { "Video must be 100 MB or smaller." }
        val token = auth.sessionToken() ?: error("Sign in to publish a BanditBite.")
        val reserveBody = JSONObject()
            .put("kind", "video")
            .put("mime", mime.ifBlank { "video/mp4" })
            .put("bytes", bytes.size)
        val reserved = authedJson("/v1/media/uploads", "POST", reserveBody, token)
        val mediaId = reserved.lString("media_id", "id")
        val uploadUrl = reserved.lString("upload_url", "url")
        require(mediaId.isNotBlank() && uploadUrl.isNotBlank()) { "Media upload slot was incomplete." }
        putBytes(uploadUrl, bytes, mime.ifBlank { "video/mp4" }, reserved.optJSONObject("headers"))
        val done = runCatching {
            authedJson("/v1/media/${enc(mediaId)}/complete", "POST", JSONObject().put("alt_text", "BanditBite video"), token)
        }.getOrNull()
        val url = done?.lString("url", "content_url", "public_url").orEmpty()
            .ifBlank { reserved.lString("public_url", "content_url") }
            .ifBlank { AppConfig.API_BASE_URL.trimEnd('/') + "/v1/media/$mediaId/content" }
        absoluteMediaUrl(url)
    }

    private fun putBytes(url: String, bytes: ByteArray, mime: String, headers: JSONObject?) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "PUT"
            doOutput = true
            setFixedLengthStreamingMode(bytes.size)
            setRequestProperty("Content-Type", mime)
            headers?.keys()?.forEach { key ->
                val k = key as? String ?: return@forEach
                setRequestProperty(k, headers.optString(k))
            }
            connectTimeout = 30_000
            readTimeout = 120_000
        }
        try {
            connection.outputStream.use { it.write(bytes) }
            val status = connection.responseCode
            if (status !in 200..299) {
                val err = runCatching { connection.errorStream?.bufferedReader()?.use { it.readText() } }.getOrNull().orEmpty()
                throw IOException("Video upload failed ($status). $err")
            }
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun authedJson(path: String, method: String, body: JSONObject?, token: String): JSONObject =
        withContext(Dispatchers.IO) {
            val connection = (URL(AppConfig.API_BASE_URL.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("X-Installation-ID", DeviceIdentity.installationId(appContext))
                connectTimeout = 15_000
                readTimeout = 45_000
                if (body != null) {
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                }
            }
            try {
                if (body != null) connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                BlindbanditApiEnvelope.unwrap(status, text)
            } finally {
                connection.disconnect()
            }
        }

    private fun enc(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name())

    private suspend fun request(
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
        allowPublic: Boolean = false,
    ): JSONObject = withContext(Dispatchers.IO) {
        val token = auth.sessionToken()
        if (token.isNullOrBlank() && !allowPublic) error("Sign in to continue.")
        val connection = (URL(AppConfig.API_BASE_URL.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            if (!token.isNullOrBlank()) setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Installation-ID", DeviceIdentity.installationId(appContext))
            // Native clients are not browsers; Origin is omitted intentionally.
            connectTimeout = 15_000
            readTimeout = 20_000
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (body != null) connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            BlindbanditApiEnvelope.unwrap(status, text)
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        /** Client gate matching owner AI persona: Social Admin UI only for @kheck. Server still enforces platform_role. */
        fun isOwnerAdmin(handle: String): Boolean = handle.trim().removePrefix("@").equals("kheck", ignoreCase = true)
    }

    // --- Fat Admin: Call RTC + 50+ ops ---

    suspend fun adminCallRtc(): JSONObject = request("/v1/social/admin/call-rtc")

    suspend fun adminSetCallRtc(provider: String): JSONObject =
        request("/v1/social/admin/call-rtc", method = "PUT", body = JSONObject().put("provider", provider))

    suspend fun adminAgoraFlags(): JSONObject = request("/v1/social/admin/agora-flags")

    suspend fun adminSetAgoraFlags(flags: JSONObject): JSONObject =
        request("/v1/social/admin/agora-flags", method = "PUT", body = JSONObject().put("flags", flags))

    suspend fun adminUserAction(userId: String, action: String, body: JSONObject = JSONObject()): JSONObject {
        val suffix = when (action) {
            "verify" -> "verify"
            "unverify" -> "unverify"
            "ban" -> "ban"
            "suspend" -> "suspend"
            "reinstate" -> "reinstate"
            "mute_posts" -> "mute-posts"
            "unmute_posts" -> "unmute"
            "mute_messages" -> "mute-messages"
            "disable_calls" -> "disable-calls"
            "enable_calls" -> "enable-calls"
            "shadow" -> "shadow"
            "rate_limit" -> "rate-limit"
            "revoke_push" -> "revoke-push"
            "force_disconnect" -> "force-disconnect"
            "monetize_approve" -> "monetize"
            "monetize_reject" -> "monetize"
            "wipe_sessions" -> "wipe-sessions"
            "test_push" -> "test-push"
            else -> action
        }
        val b = JSONObject(body.toString())
        if (action == "monetize_approve") b.put("approve", true)
        if (action == "monetize_reject") b.put("approve", false)
        return request("/v1/social/admin/users/${enc(userId)}/$suffix", method = "POST", body = b)
    }

    suspend fun adminPostAction(postId: String, action: String): JSONObject {
        return when (action) {
            "hide" -> request("/v1/social/admin/posts/${enc(postId)}/hide", method = "POST", body = JSONObject())
            "unhide" -> request("/v1/social/admin/posts/${enc(postId)}/unhide", method = "POST", body = JSONObject())
            "delete" -> request("/v1/social/admin/posts/${enc(postId)}", method = "DELETE")
            "pin" -> request("/v1/social/admin/posts/${enc(postId)}/pin", method = "POST", body = JSONObject())
            "unpin" -> request("/v1/social/admin/posts/${enc(postId)}/pin", method = "DELETE")
            else -> throw IllegalArgumentException("Unknown post action $action")
        }
    }

    suspend fun adminPrettyGet(path: String): String {
        val obj = request(if (path.startsWith("/")) path else "/$path")
        return obj.toString(2)
    }

    suspend fun adminPut(path: String, body: JSONObject): JSONObject =
        request(if (path.startsWith("/")) path else "/$path", method = "PUT", body = body)

    suspend fun adminPost(path: String, body: JSONObject = JSONObject()): JSONObject =
        request(if (path.startsWith("/")) path else "/$path", method = "POST", body = body)

    suspend fun adminBroadcast(title: String, body: String): JSONObject =
        request("/v1/social/admin/broadcast", method = "POST", body = JSONObject().put("title", title).put("body", body))

    suspend fun adminGlobalFlags(): JSONObject = request("/v1/social/admin/global-flags")

    suspend fun adminSetGlobalFlags(flags: JSONObject): JSONObject =
        request("/v1/social/admin/global-flags", method = "PUT", body = JSONObject().put("flags", flags))


}

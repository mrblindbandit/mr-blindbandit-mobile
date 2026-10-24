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
}

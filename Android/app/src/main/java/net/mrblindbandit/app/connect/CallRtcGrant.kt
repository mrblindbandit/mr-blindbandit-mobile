package net.mrblindbandit.app.connect

import org.json.JSONObject

/**
 * Parsed RTC provider + grants from create/join/accept.
 *
 * Production `mintCallRtc` + `rtcFields` (Sites) does not match the older nested `agora.uid` sketch:
 * Agora tokens are `buildTokenWithUserAccount`, returned as `rtc_provider`, a nested `rtc` object
 * (`app_id`, `channel`, `user_account`, `token`), and a flat `token`. `livekit` is null.
 * Numeric `uid` grants are still accepted for older payloads.
 */
data class CallRtcGrant(
    val provider: String,
    val livekitToken: String?,
    val livekitUrl: String?,
    val agoraAppId: String?,
    val agoraToken: String?,
    val agoraChannel: String?,
    val agoraUid: Int?,
    val agoraUserAccount: String?,
) {
    val usesAgora: Boolean
        get() = provider == "agora" &&
            !agoraAppId.isNullOrBlank() &&
            !agoraToken.isNullOrBlank() &&
            !agoraChannel.isNullOrBlank() &&
            (agoraUid != null || !agoraUserAccount.isNullOrBlank())

    /** A real LiveKit grant. An Agora user-account token must never land here. */
    val hasLiveKit: Boolean
        get() = !livekitToken.isNullOrBlank()

    fun summary(): String {
        val appSuffix = agoraAppId?.takeLast(4)?.let { "…$it" } ?: "none"
        return "provider=$provider usesAgora=$usesAgora userAccount=${!agoraUserAccount.isNullOrBlank()} " +
            "uid=${agoraUid != null} livekit=$hasLiveKit appId=$appSuffix channel=${agoraChannel.orEmpty().take(24)}"
    }

    companion object {
        /** Owner selected Agora and the server has credentials. Client must send `rtc_provider=agora`. */
        fun shouldRequestAgora(preferredProvider: String?, agoraConfigured: Boolean): Boolean =
            preferredProvider.equals("agora", ignoreCase = true) && agoraConfigured

        fun parse(response: JSONObject): CallRtcGrant {
            val rtc = response.optJSONObject("rtc")
            val providerRaw = response.lString("provider", "rtc_provider")
                .ifBlank { rtc?.lString("provider").orEmpty() }
                .lowercase()
            val nestedLk = response.optJSONObject("livekit")
            val explicitAgora = response.optJSONObject("agora")
            val nestedAgora = explicitAgora ?: rtc?.takeIf {
                providerRaw == "agora" || it.lString("provider").equals("agora", ignoreCase = true)
            }

            val appId = first(
                nestedAgora?.lString("app_id", "appId"),
                response.lString("agora_app_id"),
                if (providerRaw == "agora") response.lString("app_id") else "",
            )
            val userAccount = first(
                nestedAgora?.lString("user_account", "userAccount"),
                response.lString("user_account", "userAccount"),
            )
            val agoraToken = first(
                nestedAgora?.lString("token"),
                response.lString("agora_token"),
                if (!appId.isNullOrBlank() || providerRaw == "agora" || userAccount != null) response.lString("token") else "",
            )
            val channel = first(
                nestedAgora?.lString("channel"),
                if (providerRaw == "agora") response.lString("channel") else response.lString("channel").takeIf { explicitAgora != null || !appId.isNullOrBlank() }.orEmpty(),
                if (providerRaw == "agora") response.lString("room") else "",
                if (providerRaw == "agora") rtc?.lString("channel", "room").orEmpty() else "",
            )
            val uid = uidOf(explicitAgora) ?: uidOf(nestedAgora) ?: if (providerRaw == "agora") uidOf(response) else null

            val lkToken = when (providerRaw) {
                "agora" -> nestedLk?.lString("token")?.ifBlank { null }
                else -> nestedLk?.lString("token")?.ifBlank { null }
                    ?: response.lString("token").ifBlank { null }
                    ?: rtc?.takeIf { it.lString("provider").equals("livekit", true) || providerRaw != "agora" }
                        ?.lString("token")?.ifBlank { null }
            }
            val lkUrl = nestedLk?.lString("url", "livekit_url")?.ifBlank { null }
                ?: response.lString("livekit_url").ifBlank { null }
                ?: if (providerRaw != "agora") rtc?.lString("url", "livekit_url")?.ifBlank { null } else null

            val provider = when {
                providerRaw == "agora" || providerRaw == "livekit" -> providerRaw
                !appId.isNullOrBlank() && !agoraToken.isNullOrBlank() && (uid != null || userAccount != null) -> "agora"
                else -> "livekit"
            }
            return CallRtcGrant(
                provider = provider,
                livekitToken = lkToken,
                livekitUrl = lkUrl,
                agoraAppId = appId,
                agoraToken = agoraToken,
                agoraChannel = channel,
                agoraUid = uid,
                agoraUserAccount = userAccount,
            )
        }

        private fun first(vararg values: String?): String? =
            values.firstOrNull { !it.isNullOrBlank() }

        private fun uidOf(obj: JSONObject?): Int? {
            if (obj == null) return null
            if (!obj.has("uid") || obj.isNull("uid")) return null
            val raw = obj.opt("uid") ?: return null
            return when (raw) {
                is Number -> raw.toInt()
                is String -> raw.toIntOrNull()
                else -> null
            }
        }
    }
}

package net.mrblindbandit.app.connect

import org.json.JSONObject

/** Parsed RTC provider + grants from create/join/accept (Sites mintCallRtcToken shape). */
data class CallRtcGrant(
    val provider: String,
    val livekitToken: String?,
    val livekitUrl: String?,
    val agoraAppId: String?,
    val agoraToken: String?,
    val agoraChannel: String?,
    val agoraUid: Int?,
) {
    val usesAgora: Boolean
        get() = provider == "agora" &&
            !agoraAppId.isNullOrBlank() &&
            !agoraToken.isNullOrBlank() &&
            !agoraChannel.isNullOrBlank() &&
            agoraUid != null

    companion object {
        fun parse(response: JSONObject): CallRtcGrant {
            val nestedLk = response.optJSONObject("livekit")
            val nestedAgora = response.optJSONObject("agora")
            val providerRaw = response.lString("provider", "rtc_provider").lowercase()
            val appId = nestedAgora?.lString("app_id", "appId")
                ?.ifBlank { null }
                ?: response.lString("agora_app_id", "app_id").ifBlank { null }
            val agoraToken = nestedAgora?.lString("token")
                ?.ifBlank { null }
                ?: response.lString("agora_token").ifBlank { null }
                ?: if (!appId.isNullOrBlank()) response.lString("token").ifBlank { null } else null
            val channel = nestedAgora?.lString("channel")
                ?.ifBlank { null }
                ?: response.lString("channel").ifBlank { null }
                ?: response.lString("room").ifBlank { null }
            val uid = uidOf(nestedAgora) ?: uidOf(response)

            val lkToken = nestedLk?.lString("token")?.ifBlank { null }
                ?: if (appId.isNullOrBlank()) response.lString("token").ifBlank { null } else null
            val lkUrl = nestedLk?.lString("url", "livekit_url")?.ifBlank { null }
                ?: response.lString("livekit_url").ifBlank { null }

            val provider = when {
                providerRaw == "agora" || providerRaw == "livekit" -> providerRaw
                !appId.isNullOrBlank() && !agoraToken.isNullOrBlank() -> "agora"
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
            )
        }

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

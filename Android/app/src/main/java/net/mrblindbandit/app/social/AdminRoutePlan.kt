package net.mrblindbandit.app.social

/** Maps an admin button to a route that exists on the platform API. */
data class AdminRoutePlan(
    val method: String,
    val path: String,
    val body: Map<String, String>,
    val unavailableReason: String?,
) {
    companion object {
        fun userAction(
            action: String,
            userId: String,
            reason: String? = null,
            untilEpochSeconds: Long? = null,
            multiplier: Int? = null,
            title: String? = null,
            message: String? = null,
        ): AdminRoutePlan {
            val id = userId.trim().removePrefix("@")
            val base = "/v1/social/admin/users/$id"
            return when (action) {
                "verify" -> AdminRoutePlan("POST", "$base/verify", emptyMap(), null)
                "unverify" -> AdminRoutePlan("POST", "$base/unverify", emptyMap(), null)
                "ban" -> AdminRoutePlan("POST", "$base/ban", reason?.let { mapOf("reason" to it) } ?: emptyMap(), null)
                "suspend" -> {
                    val end = untilEpochSeconds ?: (System.currentTimeMillis() / 1000L + 7 * 86400)
                    val body = mutableMapOf("until" to end.toString())
                    if (!reason.isNullOrBlank()) body["reason"] = reason
                    AdminRoutePlan("POST", "$base/suspend", body, null)
                }
                "reinstate" -> AdminRoutePlan("POST", "$base/reinstate", emptyMap(), null)
                "mute_posts" -> restrictions(base, mapOf("mute_posts" to "true"))
                "unmute_posts" -> restrictions(base, mapOf("mute_posts" to "false"))
                "mute_messages" -> restrictions(base, mapOf("mute_messages" to "true"))
                "disable_calls" -> restrictions(base, mapOf("calls_disabled" to "true"))
                "enable_calls" -> restrictions(base, mapOf("calls_disabled" to "false"))
                "shadow" -> restrictions(base, mapOf("shadow_restricted" to "true"))
                "rate_limit" -> restrictions(base, mapOf("rate_limit_multiplier" to (multiplier ?: 1).toString()))
                "revoke_push" -> AdminRoutePlan("POST", "$base/devices/revoke", emptyMap(), null)
                "force_disconnect" -> AdminRoutePlan("POST", "$base/calls/disconnect", emptyMap(), null)
                "monetize_approve" -> AdminRoutePlan("POST", "$base/monetization", mapOf("approve" to "true"), null)
                "monetize_reject" -> AdminRoutePlan("POST", "$base/monetization", mapOf("approve" to "false"), null)
                "test_push" -> {
                    val body = mutableMapOf("user_id" to id)
                    if (!title.isNullOrBlank()) body["title"] = title
                    if (!message.isNullOrBlank()) body["body"] = message
                    AdminRoutePlan("POST", "/v1/social/admin/notifications/test", body, null)
                }
                "wipe_sessions", "pin", "unpin" -> AdminRoutePlan(
                    "",
                    "",
                    emptyMap(),
                    "The server has no ${action.replace('_', ' ')} route. Nothing was changed.",
                )
                else -> AdminRoutePlan("", "", emptyMap(), "Unknown admin action $action. Nothing was sent.")
            }
        }

        private fun restrictions(base: String, fields: Map<String, String>) =
            AdminRoutePlan("PATCH", "$base/restrictions", fields, null)
    }
}

package net.mrblindbandit.app

import android.net.Uri

object UrlPolicy {
    private val firstPartyHosts = setOf(
        "mrblindbandit.net",
        "www.mrblindbandit.net",
        "portal.mrblindbandit.net",
        "api.mrblindbandit.net",
        "clerk.mrblindbandit.net",
        "accounts.mrblindbandit.net"
    )

    fun isFirstParty(raw: String?): Boolean {
        if (raw.isNullOrBlank()) return false
        return try {
            val uri = Uri.parse(raw)
            val scheme = uri.scheme?.lowercase()
            val host = uri.host?.lowercase()
            scheme == "https" && host != null && host in firstPartyHosts
        } catch (_: Exception) {
            false
        }
    }
}

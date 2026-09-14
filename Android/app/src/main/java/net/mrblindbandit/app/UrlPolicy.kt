package net.mrblindbandit.app

import java.net.URI

object UrlPolicy {
    val firstPartyHosts = setOf(
        "mrblindbandit.net",
        "www.mrblindbandit.net",
        "portal.mrblindbandit.net",
        "api.mrblindbandit.net",
        "clerk.mrblindbandit.net",
        "accounts.mrblindbandit.net"
    )

    fun isFirstParty(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        val host = uri.host?.lowercase() ?: return false
        return uri.scheme.equals("https", ignoreCase = true) && firstPartyHosts.contains(host)
    }
}

package net.mrblindbandit.app

import android.net.Uri

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
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
        return uri.scheme.equals("https", ignoreCase = true) && firstPartyHosts.contains(uri.host?.lowercase())
    }
}

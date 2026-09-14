package net.mrblindbandit.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UrlPolicyTest {
    @Test fun acceptsKnownFirstPartyHttpsHosts() {
        assertTrue(UrlPolicy.isFirstParty("https://mrblindbandit.net/"))
        assertTrue(UrlPolicy.isFirstParty("https://www.mrblindbandit.net/media-tools/"))
        assertTrue(UrlPolicy.isFirstParty("https://portal.mrblindbandit.net/portal/"))
        assertTrue(UrlPolicy.isFirstParty("https://api.mrblindbandit.net/v1/status"))
        assertTrue(UrlPolicy.isFirstParty("https://accounts.mrblindbandit.net/"))
    }

    @Test fun rejectsExternalSpoofedAndCleartextHosts() {
        assertFalse(UrlPolicy.isFirstParty("https://example.com/"))
        assertFalse(UrlPolicy.isFirstParty("http://mrblindbandit.net/"))
        assertFalse(UrlPolicy.isFirstParty("https://mrblindbandit.net.example.com/"))
        assertFalse(UrlPolicy.isFirstParty("javascript:alert(1)"))
    }
}

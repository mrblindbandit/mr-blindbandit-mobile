package net.mrblindbandit.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class UrlPolicyTest {
    @Test
    fun acceptsFirstPartyHttps() {
        assertTrue(UrlPolicy.isFirstParty("https://mrblindbandit.net/"))
        assertTrue(UrlPolicy.isFirstParty("https://www.mrblindbandit.net/music/"))
        assertTrue(UrlPolicy.isFirstParty("https://clerk.mrblindbandit.net/"))
        assertTrue(UrlPolicy.isFirstParty("https://accounts.mrblindbandit.net/"))
    }

    @Test
    fun rejectsExternalAndCleartext() {
        assertFalse(UrlPolicy.isFirstParty("https://example.com/"))
        assertFalse(UrlPolicy.isFirstParty("http://mrblindbandit.net/"))
        assertFalse(UrlPolicy.isFirstParty("https://mrblindbandit.net.evil.com/"))
        assertFalse(UrlPolicy.isFirstParty(null))
    }
}

class AppConfigVersionTest {
    @Test
    fun versionNameIs16() {
        // BuildConfig may be absent in pure JVM without AGP; validate the source-level release constant.
        assertTrue(net.mrblindbandit.app.config.AppConfig.MARKETING_VERSION == "1.6")
    }
}

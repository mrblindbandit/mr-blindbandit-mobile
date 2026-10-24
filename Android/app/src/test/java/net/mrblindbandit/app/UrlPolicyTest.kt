package net.mrblindbandit.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
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
    fun releaseVersionMatchesBuildMetadata() {
        org.junit.Assert.assertEquals(BuildConfig.VERSION_NAME, net.mrblindbandit.app.config.AppConfig.MARKETING_VERSION)
        assertTrue(BuildConfig.VERSION_CODE > 12)
        org.junit.Assert.assertEquals("net.mrblindbandit.app", BuildConfig.APPLICATION_ID)
    }
}

package net.mrblindbandit.app.connect

import net.mrblindbandit.app.social.AdminRoutePlan
import net.mrblindbandit.app.social.absoluteMediaUrl
import net.mrblindbandit.app.social.isSharedFeedVisible
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallAndFeedRegressionTest {
    @Test fun voiceChatSessionPublishesIntelligibleMono() {
        assertEquals(CallCapturePlan.STEREO_MEDIA, CallCapturePlan.choose(true))
        assertEquals(CallCapturePlan.MONO_INTELLIGIBLE, CallCapturePlan.choose(false))
        assertEquals(4, CallCapturePlan.MONO_HIGH_QUALITY_PROFILE)
        assertFalse(CallAudioPolicy.noiseSuppression)
        assertTrue(CallAudioPolicy.echoCancellation)
    }

    @Test fun callTitleHidesRawIds() {
        assertEquals("Emma", CallPeerLabel.spoken("Emma", "emma"))
        assertEquals("@emma", CallPeerLabel.spoken("4829103", "emma"))
        assertEquals("Caller", CallPeerLabel.spoken("", "4829103"))
        assertEquals("Caller", CallPeerLabel.spoken("profile_abc", ""))
        assertEquals("Blindbandit caller", CallPeerLabel.spoken("", "Blindbandit caller"))
    }

    @Test fun publicPhotoAddressUsesTheWebsite() {
        assertEquals("https://mrblindbandit.net/assets/a.jpg", absoluteMediaUrl("/assets/a.jpg"))
        assertEquals("https://cdn.example/a.jpg", absoluteMediaUrl("https://cdn.example/a.jpg"))
        assertEquals("", absoluteMediaUrl("  "))
    }

    @Test fun adminButtonsUseLiveRoutes() {
        val mute = AdminRoutePlan.userAction("mute_posts", "profile_1")
        assertEquals("PATCH", mute.method)
        assertEquals("/v1/social/admin/users/profile_1/restrictions", mute.path)
        assertEquals("true", mute.body["mute_posts"])
        assertEquals(null, mute.unavailableReason)
        val push = AdminRoutePlan.userAction("test_push", "profile_1", title = "Hi", message = "There")
        assertEquals("/v1/social/admin/notifications/test", push.path)
        assertEquals("profile_1", push.body["user_id"])
        val wipe = AdminRoutePlan.userAction("wipe_sessions", "profile_1")
        assertTrue(wipe.unavailableReason != null)
        assertEquals("", wipe.path)
    }

    @Test fun sharedFeedDropsPrivateStates() {
        assertTrue(isSharedFeedVisible("", ""))
        assertTrue(isSharedFeedVisible("public", "published"))
        assertFalse(isSharedFeedVisible("draft", ""))
        assertFalse(isSharedFeedVisible("private", "ok"))
        assertFalse(isSharedFeedVisible("", "deleted"))
        assertFalse(isSharedFeedVisible("", "reported"))
    }
}

package net.mrblindbandit.app.social

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SocialModelsTest {
    @Test
    fun absoluteMediaUrl_keepsHttps() {
        assertEquals("https://cdn.example/a.mp4", absoluteMediaUrl("https://cdn.example/a.mp4"))
    }

    @Test
    fun absoluteMediaUrl_protocolRelative() {
        assertEquals("https://cdn.example/a.mp4", absoluteMediaUrl("//cdn.example/a.mp4"))
    }

    @Test
    fun absoluteMediaUrl_rootedPath() {
        assertEquals("https://mrblindbandit.net/media/x.jpg", absoluteMediaUrl("/media/x.jpg"))
    }

    @Test
    fun absoluteMediaUrl_relative() {
        assertEquals("https://mrblindbandit.net/media/x.jpg", absoluteMediaUrl("media/x.jpg"))
    }

    @Test
    fun absoluteMediaUrl_blank() {
        assertEquals("", absoluteMediaUrl("  "))
    }

    @Test
    fun isOwnerAdmin_onlyKheck() {
        assertTrue(SocialRepository.isOwnerAdmin("kheck"))
        assertTrue(SocialRepository.isOwnerAdmin("@Kheck"))
        assertTrue(SocialRepository.isOwnerAdmin(" KHECK "))
        assertFalse(SocialRepository.isOwnerAdmin("mrblindbandit"))
        assertFalse(SocialRepository.isOwnerAdmin(""))
        assertFalse(SocialRepository.isOwnerAdmin("kheck2"))
    }

    @Test
    fun socialAuthor_parsesVerified() {
        val author = SocialAuthor.parse(
            JSONObject("""{"handle":"alice","display_name":"Alice","verified":true,"avatar_url":"/a.png"}""")
        )
        assertEquals("alice", author.handle)
        assertTrue(author.verified)
        assertEquals("https://mrblindbandit.net/a.png", author.avatarUrl)
    }

    @Test
    fun banditBite_parses() {
        val bite = BanditBite.parse(
            JSONObject(
                """{"id":"b1","caption":"hi","video_url":"https://cdn/v.mp4","author":{"handle":"bob","verified":false},"likes":3}"""
            )
        )!!
        assertEquals("b1", bite.id)
        assertEquals("hi", bite.caption)
        assertEquals("bob", bite.author.handle)
        assertEquals(3L, bite.reactionTotal)
    }
}


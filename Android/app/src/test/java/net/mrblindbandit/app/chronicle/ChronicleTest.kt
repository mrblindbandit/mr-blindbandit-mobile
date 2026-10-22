package net.mrblindbandit.app.chronicle

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ChronicleTest {
    private val feed = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Mr. Blindbandit</title>
<item><title>First Story</title><link>https://mrblindbandit.net/publications/first-story/</link>
<guid>first-story</guid><pubDate>Mon, 12 Oct 2026 10:00:00 GMT</pubDate>
<description><![CDATA[<p>A short summary.</p>]]></description></item>
<item><title>No link</title></item>
</channel></rss>"""

    @Test fun parsesFeedItemsWithLinks() {
        val stories = ChronicleRss.parse(feed)
        assertEquals(1, stories.size)
        assertEquals("First Story", stories[0].title)
        assertEquals("https://mrblindbandit.net/publications/first-story/", stories[0].url)
        assertNotNull(stories[0].date)
        assertTrue(stories[0].summary.contains("A short summary"))
    }

    @Test fun malformedFeedReturnsEmpty() {
        assertTrue(ChronicleRss.parse("not xml").isEmpty())
    }

    @Test fun deepLinksResolveToPublications() {
        assertEquals("https://mrblindbandit.net/publications/abc-1/", ChronicleDeepLink.articleUrl("https://mrblindbandit.net/publications/abc-1/"))
        assertEquals("https://mrblindbandit.net/publications/abc-1/", ChronicleDeepLink.articleUrl("mrblindbandit://article/abc-1"))
        assertNull(ChronicleDeepLink.articleUrl("https://evil.example/publications/abc/"))
        assertNull(ChronicleDeepLink.articleUrl("https://mrblindbandit.net/music/"))
    }
}

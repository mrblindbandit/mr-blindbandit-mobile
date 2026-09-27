package net.mrblindbandit.app

import net.mrblindbandit.app.safety.ContentFilter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ContentFilterTest {
    @Test
    fun masksBlockedWords() {
        assertEquals("what the **** is this", ContentFilter.mask("what the Fuck is this"))
        assertEquals("****** day", ContentFilter.mask("shitty day"))
        assertTrue(ContentFilter.containsBlockedLanguage("you BITCHES"))
    }

    @Test
    fun leavesEverydayWordsAlone() {
        listOf("Great mix on the new track", "Scunthorpe grass class", "spicy cocktail in the cockpit", "Pakistan and Dickens", "flame retardant")
            .forEach { assertEquals(it, ContentFilter.mask(it)) }
    }

    @Test
    fun canBeTurnedOff() {
        assertEquals("oh shit", ContentFilter.display("oh shit", enabled = false))
        assertEquals("oh ****", ContentFilter.display("oh shit", enabled = true))
    }
}

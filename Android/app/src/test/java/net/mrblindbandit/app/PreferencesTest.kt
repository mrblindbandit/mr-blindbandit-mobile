package net.mrblindbandit.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PreferencesTest {
    private lateinit var context: Context

    @Before fun resetPreferences() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("blindbandit_app", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test fun accessibilityDefaultsAreFriendly() {
        val prefs = AndroidAppPreferences(context)
        assertTrue(prefs.announcePageLoads)
        assertFalse(prefs.reduceMotion)
        assertEquals(100, prefs.textZoom)
    }

    @Test fun zoomIsClampedToSafeRange() {
        val prefs = AndroidAppPreferences(context)
        prefs.setTextZoom(500)
        assertEquals(200, prefs.textZoom)
        prefs.setTextZoom(10)
        assertEquals(75, prefs.textZoom)
    }
}

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

    @Test fun settingsPersistAcrossInstances() {
        val prefs = AndroidAppPreferences(context)
        prefs.setHighContrast(true)
        prefs.setHapticsEnabled(false)
        prefs.setAppearance(net.mrblindbandit.app.ui.Appearance.DARK)
        prefs.setSpeechRate(1.5f)
        val reloaded = AndroidAppPreferences(context)
        assertTrue(reloaded.highContrast)
        assertFalse(reloaded.hapticsEnabled)
        assertEquals(net.mrblindbandit.app.ui.Appearance.DARK, reloaded.appearance)
        assertEquals(1.5f, reloaded.speechRate, 0.001f)
    }

    @Test fun clearAllRestoresDefaults() {
        val prefs = AndroidAppPreferences(context)
        prefs.setReduceMotion(true)
        prefs.clearAll()
        assertFalse(AndroidAppPreferences(context).reduceMotion)
    }
}

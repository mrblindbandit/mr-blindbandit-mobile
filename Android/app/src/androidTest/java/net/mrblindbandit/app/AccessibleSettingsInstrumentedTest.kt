package net.mrblindbandit.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import net.mrblindbandit.app.settings.ToggleRow
import net.mrblindbandit.app.ui.Appearance
import net.mrblindbandit.app.ui.BlindbanditTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccessibleSettingsInstrumentedTest {
    @get:Rule val compose = createComposeRule()

    @Test fun toggleRowIsOneSwitchForTalkBackAndToggles() {
        compose.setContent {
            BlindbanditTheme(appearance = Appearance.DARK, highContrast = false) {
                var on by remember { mutableStateOf(false) }
                ToggleRow(label = "Haptic feedback", checked = on) { on = it }
            }
        }
        val row = compose.onNodeWithText("Haptic feedback", useUnmergedTree = false)
        row.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
        row.assertIsOff()
        row.performClick()
        row.assertIsOn()
    }

    @Test fun preferencesPersistOnDevice() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = AndroidAppPreferences(context)
        prefs.clearAll()
        prefs.setHighContrast(true)
        prefs.setAppearance(Appearance.LIGHT)
        val reloaded = AndroidAppPreferences(context)
        assertTrue(reloaded.highContrast)
        assertEquals(Appearance.LIGHT, reloaded.appearance)
        reloaded.clearAll()
    }
}

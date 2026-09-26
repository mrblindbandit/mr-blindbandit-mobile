package net.mrblindbandit.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Blindbandit Records design tokens shared by every Compose screen. */
object BrandColors {
    val Gold = Color(0xFFFFD54F)
    val GoldDeep = Color(0xFF8A6D00)
    val Ink = Color(0xFF0A0A0A)
    val Charcoal = Color(0xFF1A1A1A)
    val Graphite = Color(0xFF2A2A2A)
    val Paper = Color(0xFFFAF8F2)
    val Danger = Color(0xFFFF6B6B)
    val DangerDeep = Color(0xFFB3261E)
}

object Spacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 16.dp
    val lg = 24.dp
    val xl = 32.dp
    /** Minimum interactive size required by Android accessibility guidance. */
    val minTouch = 48.dp
}

enum class Appearance(val storageKey: String, val label: String) {
    SYSTEM("system", "Match device"),
    LIGHT("light", "Light"),
    DARK("dark", "Dark");

    companion object {
        fun fromKey(key: String?): Appearance = entries.firstOrNull { it.storageKey == key } ?: SYSTEM
    }
}

private val DarkBrand = darkColorScheme(
    primary = BrandColors.Gold,
    onPrimary = BrandColors.Ink,
    secondary = BrandColors.Gold,
    onSecondary = BrandColors.Ink,
    background = BrandColors.Ink,
    onBackground = Color.White,
    surface = BrandColors.Charcoal,
    onSurface = Color.White,
    surfaceVariant = BrandColors.Graphite,
    onSurfaceVariant = Color(0xFFD6D6D6),
    error = BrandColors.Danger,
    onError = BrandColors.Ink,
    outline = Color(0xFF8C8C8C),
)

private val LightBrand = lightColorScheme(
    primary = BrandColors.GoldDeep,
    onPrimary = Color.White,
    secondary = BrandColors.GoldDeep,
    onSecondary = Color.White,
    background = BrandColors.Paper,
    onBackground = BrandColors.Ink,
    surface = Color.White,
    onSurface = BrandColors.Ink,
    surfaceVariant = Color(0xFFEFEADB),
    onSurfaceVariant = Color(0xFF3D3D3D),
    error = BrandColors.DangerDeep,
    onError = Color.White,
    outline = Color(0xFF5E5E5E),
)

/** Maximum-contrast variants: pure black/white surfaces and saturated accents. */
private val DarkHighContrast = DarkBrand.copy(
    background = Color.Black,
    surface = Color.Black,
    surfaceVariant = Color(0xFF141414),
    onSurfaceVariant = Color.White,
    outline = Color.White,
)

private val LightHighContrast = LightBrand.copy(
    primary = Color(0xFF5C4700),
    background = Color.White,
    surface = Color.White,
    surfaceVariant = Color.White,
    onSurfaceVariant = Color.Black,
    outline = Color.Black,
)

/** Typography uses sp everywhere so it scales with the user's font size setting. */
val BrandTypography = Typography(
    displaySmall = TextStyle(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Black),
    headlineMedium = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold),
    headlineSmall = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 22.sp),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontSize = 16.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
)

fun brandColorScheme(dark: Boolean, highContrast: Boolean): ColorScheme = when {
    dark && highContrast -> DarkHighContrast
    dark -> DarkBrand
    highContrast -> LightHighContrast
    else -> LightBrand
}

@Composable
fun BlindbanditTheme(
    appearance: Appearance = Appearance.SYSTEM,
    highContrast: Boolean = false,
    content: @Composable () -> Unit,
) {
    val dark = when (appearance) {
        Appearance.SYSTEM -> isSystemInDarkTheme()
        Appearance.LIGHT -> false
        Appearance.DARK -> true
    }
    MaterialTheme(
        colorScheme = brandColorScheme(dark, highContrast),
        typography = BrandTypography,
        content = content,
    )
}

package dev.mayon.timetable.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.material3.Surface
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Palette provenance: aspects/appearance/appearance/onedark.nix, One Dark refined.
private val Dark = darkColorScheme(
    primaryContainer = Color(0xff2e3c2b), onPrimaryContainer = Color(0xff98c379),
    secondaryContainer = Color(0xff323843), onSecondaryContainer = Color(0xffd7dae0),
    tertiaryContainer = Color(0xff263c40), onTertiaryContainer = Color(0xff56b6c2),
    surfaceTint = Color.Transparent, surfaceContainer = Color(0xff272c33),
    surfaceContainerLow = Color(0xff22272e), surfaceContainerHigh = Color(0xff303640),
    surfaceContainerHighest = Color(0xff323843),
    primary = Color(0xff98c379), onPrimary = Color(0xff182217),
    secondary = Color(0xff61afef), tertiary = Color(0xff56b6c2),
    background = Color(0xff1e2228), onBackground = Color(0xffd7dae0),
    surface = Color(0xff272c33), onSurface = Color(0xffd7dae0),
    surfaceVariant = Color(0xff323843), onSurfaceVariant = Color(0xffabb2bf),
    outline = Color(0xff828a95), error = Color(0xffe06c75),
)
private val Light = lightColorScheme(
    primaryContainer = Color(0xffe1ecd9), onPrimaryContainer = Color(0xff284520),
    secondaryContainer = Color(0xffe5e8ec), onSecondaryContainer = Color(0xff20252c),
    tertiaryContainer = Color(0xffdcebec), onTertiaryContainer = Color(0xff24545b),
    surfaceTint = Color.Transparent, surfaceContainer = Color(0xffeef0f2),
    surfaceContainerLow = Color(0xfff5f6f7), surfaceContainerHigh = Color(0xffe7eaed),
    surfaceContainerHighest = Color(0xffe1e5e9),
    primary = Color(0xff416737), onPrimary = Color.White,
    secondary = Color(0xff23618c), tertiary = Color(0xff805f20),
    background = Color(0xfff5f6f7), onBackground = Color(0xff20252c),
    surface = Color.White, onSurface = Color(0xff20252c),
    surfaceVariant = Color(0xffe5e8ec), onSurfaceVariant = Color(0xff4d5662),
    outline = Color(0xff65707e), error = Color(0xffa33242),
)

@Composable
fun TimetableTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) Dark else Light) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background, contentColor = MaterialTheme.colorScheme.onBackground, content = content)
    }
}

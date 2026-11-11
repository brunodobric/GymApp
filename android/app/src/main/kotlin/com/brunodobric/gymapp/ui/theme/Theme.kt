package com.brunodobric.gymapp.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.model.AppTheme

/**
 * Naglasne boje, iste kao `AccentPalette` na iOS-u (Shared/Design/AccentPalette.swift): svaka ima svijetlu
 * i tamnu vrijednost. Ključ je `AccentChoice.rawValue`, a nepoznata vrijednost daje zadanu Apolon plavu.
 */
object AccentPalette {
    data class Pair(val light: Color, val dark: Color)

    val apolon = Pair(Color(0xFF1F5BD6), Color(0xFF4C88FA))

    fun forRaw(raw: String?): Pair = when (raw) {
        "indigo" -> Pair(Color(0xFF4B47D6), Color(0xFF7F7AF7))
        "purple" -> Pair(Color(0xFF8A3CCB), Color(0xFFA66CEB))
        "pink" -> Pair(Color(0xFFC8255F), Color(0xFFEA4F8B))
        "teal" -> Pair(Color(0xFF00707F), Color(0xFF1A98A7))
        "graphite" -> Pair(Color(0xFF3A404C), Color(0xFF868C98))
        else -> apolon
    }
}

@Composable
fun ApolonTheme(
    accentRaw: String? = null,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val accent = AccentPalette.forRaw(accentRaw)
    val colors = if (darkTheme) {
        // Tamni način kao standard: crna podloga kao systemBackground na iOS-u, kartice tamnosive.
        darkColorScheme(
            primary = accent.dark,
            onPrimary = Color.White,
            background = Color.Black,
            surface = Color.Black,
            surfaceContainerHighest = Color(0xFF1C1F26),
            surfaceContainerHigh = Color(0xFF181B21),
            surfaceContainer = Color(0xFF14161B),
        )
    } else {
        // Svijetla podloga #F3F5FA s bijelim karticama, tekst #12161F i #4A5263 (prijedlog dizajna).
        lightColorScheme(
            primary = accent.light,
            onPrimary = Color.White,
            background = Color(0xFFF3F5FA),
            surface = Color(0xFFF3F5FA),
            onBackground = Color(0xFF12161F),
            onSurface = Color(0xFF12161F),
            onSurfaceVariant = Color(0xFF4A5263),
            surfaceContainerHighest = Color.White,
            surfaceContainerHigh = Color(0xFFF7F9FC),
            surfaceContainer = Color(0xFFEEF1F7),
            surfaceContainerLow = Color(0xFFF7F9FC),
            outlineVariant = Color(0xFFDDE2EC),
        )
    }
    // Kartice su zaobljenije nego zadano u Materialu (20 dp), kao u prijedlogu dizajna.
    val shapes = Shapes(medium = RoundedCornerShape(20.dp), large = RoundedCornerShape(24.dp))
    MaterialTheme(colorScheme = colors, shapes = shapes, content = content)
}

/** Zelena za završene serije i potvrdu, svijetla i tamna. */
val ColorScheme.success: Color
    get() = if (background.luminance() < 0.5f) Color(0xFF3FBF7A) else Color(0xFF1B7F4A)

/** Je li tema tamna: "Sustav" prati postavku uređaja. */
@Composable
fun AppTheme.isDark(): Boolean = when (this) {
    AppTheme.SYSTEM -> isSystemInDarkTheme()
    AppTheme.LIGHT -> false
    AppTheme.DARK -> true
}

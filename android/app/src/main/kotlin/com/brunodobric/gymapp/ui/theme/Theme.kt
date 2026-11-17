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
 * Boje aplikacije, iste kao `AppPalette` na iOS-u (Shared/Design/AppPalette.swift, docs/DIZAJN.md, odjeljak Boja).
 * Plavo-siva paleta od šest tonova (#06141B, #11212D, #253745, #4A5C6A, #9BA8AB, #CCD0CF); svijetla tema dodaje
 * dva izvedena tona za podlogu i kartice. Akcent je jedan, Čelik, a tekst na njemu je [onAccent].
 */
object AppPalette {
    data class Pair(val light: Color, val dark: Color) {
        fun pick(dark: Boolean): Color = if (dark) this.dark else light
    }

    /** Akcent Čelik. */
    val accent = Pair(Color(0xFF253745), Color(0xFFCCD0CF))
    /** Tekst i simboli na punom akcentu. */
    val onAccent = Pair(Color.White, Color(0xFF06141B))
    val background = Pair(Color(0xFFE6E9E8), Color(0xFF06141B))
    val card = Pair(Color(0xFFF7F8F8), Color(0xFF11212D))
    val fill = Pair(Color(0xFFCCD0CF), Color(0xFF253745))
    val subtleFill = Pair(Color(0xFFE6E9E8), Color(0xFF1A2C39))
    /** Razdjelnici i obrubi, nije za tekst. */
    val separator = Pair(Color(0xFF9BA8AB), Color(0xFF4A5C6A))
    val text = Pair(Color(0xFF06141B), Color(0xFFCCD0CF))
    val secondaryText = Pair(Color(0xFF4A5C6A), Color(0xFF9BA8AB))
}

@Composable
fun ApolonTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val p = AppPalette
    val colors = if (darkTheme) {
        darkColorScheme(
            primary = p.accent.dark,
            onPrimary = p.onAccent.dark,
            primaryContainer = p.fill.dark,
            onPrimaryContainer = p.text.dark,
            secondary = p.accent.dark,
            onSecondary = p.onAccent.dark,
            secondaryContainer = p.fill.dark,
            onSecondaryContainer = p.text.dark,
            background = p.background.dark,
            onBackground = p.text.dark,
            surface = p.background.dark,
            onSurface = p.text.dark,
            surfaceVariant = p.fill.dark,
            onSurfaceVariant = p.secondaryText.dark,
            surfaceContainerLowest = p.background.dark,
            surfaceContainerLow = p.card.dark,
            surfaceContainer = p.card.dark,
            surfaceContainerHigh = p.card.dark,
            surfaceContainerHighest = p.card.dark,
            outline = p.separator.dark,
            outlineVariant = p.fill.dark,
        )
    } else {
        lightColorScheme(
            primary = p.accent.light,
            onPrimary = p.onAccent.light,
            primaryContainer = p.fill.light,
            onPrimaryContainer = p.text.light,
            secondary = p.accent.light,
            onSecondary = p.onAccent.light,
            secondaryContainer = p.fill.light,
            onSecondaryContainer = p.text.light,
            background = p.background.light,
            onBackground = p.text.light,
            surface = p.background.light,
            onSurface = p.text.light,
            surfaceVariant = p.fill.light,
            onSurfaceVariant = p.secondaryText.light,
            surfaceContainerLowest = Color.White,
            surfaceContainerLow = p.card.light,
            surfaceContainer = p.card.light,
            surfaceContainerHigh = p.card.light,
            surfaceContainerHighest = p.card.light,
            outline = p.separator.light,
            outlineVariant = p.fill.light,
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

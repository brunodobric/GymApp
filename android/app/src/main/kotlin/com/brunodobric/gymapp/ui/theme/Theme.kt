package com.brunodobric.gymapp.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
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
        // Tamni način kao standard: crna podloga kao systemBackground na iOS-u.
        darkColorScheme(
            primary = accent.dark,
            onPrimary = Color.White,
            background = Color.Black,
            surface = Color.Black,
        )
    } else {
        lightColorScheme(primary = accent.light, onPrimary = Color.White)
    }
    MaterialTheme(colorScheme = colors, content = content)
}

/** Je li tema tamna: "Sustav" prati postavku uređaja. */
@Composable
fun AppTheme.isDark(): Boolean = when (this) {
    AppTheme.SYSTEM -> isSystemInDarkTheme()
    AppTheme.LIGHT -> false
    AppTheme.DARK -> true
}

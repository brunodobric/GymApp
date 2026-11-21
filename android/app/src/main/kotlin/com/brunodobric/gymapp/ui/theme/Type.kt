package com.brunodobric.gymapp.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import com.brunodobric.gymapp.R

/**
 * Font Inter (SIL Open Font License 1.1, `assets/LICENSE-Inter.txt`) umjesto Roboto, da tekst bude što bliži SF Pro
 * na iOS-u. SF Pro se izvan Appleovih platformi ne smije koristiti. Font je u aplikaciji (`res/font`), ne preuzima
 * se s Google Fonts, pa aplikacija i dalje ne šalje nikakve zahtjeve vanjskim serverima.
 *
 * Jedna varijabilna datoteka (osi `wght` 100–900 i `opsz` 14–32) daje sve debljine. Kao SF Pro Text i SF Pro
 * Display, Inter ima dvije optičke veličine: [InterText] za tekst do 20 sp i [InterDisplay] (gušći razmak) za
 * velike naslove i brojke.
 */
private val weights = listOf(
    FontWeight.Thin,
    FontWeight.ExtraLight,
    FontWeight.Light,
    FontWeight.Normal,
    FontWeight.Medium,
    FontWeight.SemiBold,
    FontWeight.Bold,
    FontWeight.ExtraBold,
    FontWeight.Black,
)

@OptIn(ExperimentalTextApi::class)
private fun interFamily(opticalSize: Float): FontFamily = FontFamily(
    weights.map { weight ->
        Font(
            R.font.inter_variable,
            weight = weight,
            variationSettings = FontVariation.Settings(
                FontVariation.weight(weight.weight),
                FontVariation.Setting("opsz", opticalSize),
            ),
        )
    },
)

/** Inter za tekst (optička veličina 14). */
val InterText: FontFamily = interFamily(opticalSize = 14f)

/** Inter Display za naslove i velike brojke (optička veličina 32). */
val InterDisplay: FontFamily = interFamily(opticalSize = 32f)

private fun TextStyle.withFamily(family: FontFamily) = copy(fontFamily = family)

/**
 * Materialova ljestvica tipografije s fontom Inter u svim stilovima. Veličine i razmaci ostaju Materialovi, pa
 * veličina fonta sustava i dalje radi kao do sada. Display, headline i titleLarge (22 sp i više) koriste
 * [InterDisplay], kao što iOS za tekst od 20 pt naviše prelazi na SF Pro Display.
 */
val AppTypography: Typography = Typography().run {
    copy(
        displayLarge = displayLarge.withFamily(InterDisplay),
        displayMedium = displayMedium.withFamily(InterDisplay),
        displaySmall = displaySmall.withFamily(InterDisplay),
        headlineLarge = headlineLarge.withFamily(InterDisplay),
        headlineMedium = headlineMedium.withFamily(InterDisplay),
        headlineSmall = headlineSmall.withFamily(InterDisplay),
        titleLarge = titleLarge.withFamily(InterDisplay),
        titleMedium = titleMedium.withFamily(InterText),
        titleSmall = titleSmall.withFamily(InterText),
        bodyLarge = bodyLarge.withFamily(InterText),
        bodyMedium = bodyMedium.withFamily(InterText),
        bodySmall = bodySmall.withFamily(InterText),
        labelLarge = labelLarge.withFamily(InterText),
        labelMedium = labelMedium.withFamily(InterText),
        labelSmall = labelSmall.withFamily(InterText),
    )
}

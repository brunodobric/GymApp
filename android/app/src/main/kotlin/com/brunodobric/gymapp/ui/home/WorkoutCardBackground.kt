package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.dp

/** Oblik kartica treninga na Početnoj (kartica za početak i trening u tijeku). */
internal val WorkoutCardShape = RoundedCornerShape(24.dp)

/**
 * Pozadina kartice treninga (`WorkoutCardBackground` na iOS-u): ista podloga kao ostale kartice, preko nje
 * ujednačen poluprozirni sloj u boji akcenta (bez stupnjevanja) i tanki rub, da se kartica istakne među ostalima.
 * Akcent je boja iz postavki (`colorScheme.primary`). U tamnom načinu akcent na tamnoj podlozi treba malo više
 * boje da se jednako vidi.
 */
@Composable
internal fun Modifier.workoutCardBackground(shape: Shape = WorkoutCardShape): Modifier {
    val colors = MaterialTheme.colorScheme
    val accent = colors.primary
    val strength = if (colors.background.luminance() < 0.5f) 1.4f else 1f
    return clip(shape)
        .background(colors.surfaceContainerHighest)
        .background(accent.copy(alpha = 0.15f * strength))
        .border(1.dp, accent.copy(alpha = 0.3f), shape)
}

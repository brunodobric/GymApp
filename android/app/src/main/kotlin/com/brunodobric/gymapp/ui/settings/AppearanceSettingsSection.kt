package com.brunodobric.gymapp.ui.settings

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.AccentChoice
import com.brunodobric.gymapp.model.AppTheme
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.theme.AccentPalette
import com.brunodobric.gymapp.ui.theme.isDark

/** Tema, naglasna boja i tijelo na prikazu mišića, kao `AppearanceSettingsSection` na iOS-u (bez Live Activityja). */
@Composable
internal fun AppearanceSettingsSection(services: AppServices) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.theme), style = MaterialTheme.typography.bodyLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppTheme.entries.forEach { theme ->
                FilterChip(
                    selected = settings.theme == theme,
                    onClick = {
                        settings.theme = theme
                        store.save()
                    },
                    label = { Text(stringResource(themeTitle(theme))) },
                )
            }
        }
        Text(stringResource(R.string.accent_color), style = MaterialTheme.typography.bodyLarge)
        val dark = settings.theme.isDark()
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            AccentChoice.entries.forEach { choice ->
                val pair = AccentPalette.forRaw(choice.raw)
                val selected = settings.accent == choice
                val title = stringResource(accentTitle(choice))
                Box(
                    Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(if (dark) pair.dark else pair.light)
                        .selectable(selected = selected, role = Role.RadioButton) {
                            settings.accent = choice
                            store.save()
                        }
                        .semantics { contentDescription = title },
                    contentAlignment = Alignment.Center,
                ) {
                    if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White)
                }
            }
        }
    }
    val male = stringResource(R.string.sex_male)
    val female = stringResource(R.string.sex_female)
    ChoiceRow(
        title = stringResource(R.string.body_in_muscle_view),
        value = if (settings.bodyMapFemale) female else male,
        options = listOf(false, true),
        label = { if (it) female else male },
    ) {
        settings.bodyMapFemale = it
        store.save()
    }
}

@StringRes
private fun themeTitle(theme: AppTheme): Int = when (theme) {
    AppTheme.SYSTEM -> R.string.theme_system
    AppTheme.LIGHT -> R.string.theme_light
    AppTheme.DARK -> R.string.theme_dark
}

@StringRes
private fun accentTitle(choice: AccentChoice): Int = when (choice) {
    AccentChoice.BLUE -> R.string.accent_blue
    AccentChoice.INDIGO -> R.string.accent_indigo
    AccentChoice.PURPLE -> R.string.accent_purple
    AccentChoice.PINK -> R.string.accent_pink
    AccentChoice.TEAL -> R.string.accent_teal
    AccentChoice.GRAPHITE -> R.string.accent_graphite
}

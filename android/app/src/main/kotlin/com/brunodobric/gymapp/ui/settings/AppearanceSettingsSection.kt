package com.brunodobric.gymapp.ui.settings

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.AppTheme
import com.brunodobric.gymapp.ui.rememberStoreRevision

/** Tema i tijelo na prikazu mišića, kao `AppearanceSettingsSection` na iOS-u (bez Live Activityja). Akcent je jedan, Čelik. */
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

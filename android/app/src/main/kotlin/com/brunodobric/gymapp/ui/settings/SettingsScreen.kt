package com.brunodobric.gymapp.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.BuildConfig
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.onboarding.ProgramRecommendationScreen

/**
 * Postavke: Profil, Trening, Podaci (izvoz, uvoz, brisanje) i O aplikaciji. Ostale kategorije s iOS-a
 * (izgled, ploče, obavijesti) dolaze kasnije.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(services: AppServices, onClose: () -> Unit) {
    var showsRecommendation by rememberSaveable { mutableStateOf(false) }
    if (showsRecommendation) {
        ProgramRecommendationScreen(services, onClose = { showsRecommendation = false })
        return
    }
    BackHandler(onBack = onClose)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            SectionHeader(stringResource(R.string.settings_profile))
            ProfileSettingsSection(services, onSuggestSchedule = { showsRecommendation = true })
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SectionHeader(stringResource(R.string.settings_appearance))
            AppearanceSettingsSection(services)
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SectionHeader(stringResource(R.string.settings_training))
            TrainingSettingsSection(services)
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SectionHeader(stringResource(R.string.bar_and_plates))
            PlatesSettingsSection(services)
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SectionHeader(stringResource(R.string.settings_data))
            DataSettingsSection(services)
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            SectionHeader(stringResource(R.string.settings_about))
            ListItem(
                headlineContent = { Text(stringResource(R.string.settings_version)) },
                trailingContent = { Text(appVersion()) },
            )
            ListItem(
                headlineContent = { Text(stringResource(R.string.settings_catalog)) },
                trailingContent = { Text("MoveKit") },
            )
        }
    }
}

@Composable
internal fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

private fun appVersion(): String = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

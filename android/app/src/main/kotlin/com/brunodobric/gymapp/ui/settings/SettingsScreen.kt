package com.brunodobric.gymapp.ui.settings

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.BuildConfig
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.onboarding.ProgramRecommendationScreen

/** Kategorije postavki kao na iOS-u (`SettingsCategory`): svaka je redak na prvom ekranu i otvara svoju stranicu. */
internal enum class SettingsCategory {
    PROFILE, APPEARANCE, TRAINING, PLATES, NOTIFICATIONS, HEALTH, SYNC, DATA, ABOUT;

    @get:StringRes
    val title: Int
        get() = when (this) {
            PROFILE -> R.string.settings_profile
            APPEARANCE -> R.string.settings_appearance
            TRAINING -> R.string.settings_training
            PLATES -> R.string.bar_and_plates
            NOTIFICATIONS -> R.string.settings_notifications
            HEALTH -> R.string.health_connect
            SYNC -> R.string.settings_sync
            DATA -> R.string.settings_data
            ABOUT -> R.string.settings_about
        }

    @Composable
    fun icon(): Painter = when (this) {
        PROFILE -> rememberVectorPainter(Icons.Filled.AccountCircle)
        APPEARANCE -> painterResource(R.drawable.ic_settings_appearance)
        TRAINING -> painterResource(R.drawable.ic_kind_strength)
        PLATES -> painterResource(R.drawable.ic_settings_plates)
        NOTIFICATIONS -> rememberVectorPainter(Icons.Filled.Notifications)
        HEALTH -> rememberVectorPainter(Icons.Filled.Favorite)
        SYNC -> rememberVectorPainter(Icons.Filled.Refresh)
        DATA -> painterResource(R.drawable.ic_settings_data)
        ABOUT -> rememberVectorPainter(Icons.Filled.Info)
    }

    companion object {
        /**
         * Grupe na prvom ekranu kao na iOS-u: profil, trening i izgled, veze sa sustavom, podaci te o aplikaciji.
         * Mjesto iCloud retka na iOS-u ima sinkronizacija preko datoteke (`FileSync`).
         */
        val groups = listOf(
            listOf(PROFILE),
            listOf(APPEARANCE, TRAINING, PLATES),
            listOf(NOTIFICATIONS, HEALTH),
            listOf(SYNC, DATA),
            listOf(ABOUT),
        )
    }
}

/**
 * Postavke: popis kategorija u grupama, a svaka kategorija je zasebna stranica s povratkom na popis.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(services: AppServices, onClose: () -> Unit) {
    var opened by rememberSaveable { mutableStateOf<SettingsCategory?>(null) }
    opened?.let { category ->
        SettingsPage(services, category, onBack = { opened = null })
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
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SettingsCategory.groups.forEach { group ->
                Card(Modifier.fillMaxWidth()) {
                    group.forEachIndexed { index, category ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 56.dp))
                        ListItem(
                            modifier = Modifier.clickable { opened = category },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            leadingContent = {
                                Icon(category.icon(), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            headlineContent = { Text(stringResource(category.title)) },
                            trailingContent = {
                                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                            },
                        )
                    }
                }
            }
        }
    }
}

/** Stranica jedne kategorije: naslov s povratkom i sadržaj kategorije. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsPage(services: AppServices, category: SettingsCategory, onBack: () -> Unit) {
    var showsRecommendation by rememberSaveable { mutableStateOf(false) }
    var showsMuscleMapLicense by rememberSaveable { mutableStateOf(false) }
    if (showsMuscleMapLicense) {
        MuscleMapLicenseDialog(services, onDismiss = { showsMuscleMapLicense = false })
    }
    if (showsRecommendation) {
        ProgramRecommendationScreen(services, onClose = { showsRecommendation = false })
        return
    }
    BackHandler(onBack = onBack)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(category.title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            when (category) {
                SettingsCategory.PROFILE -> ProfileSettingsSection(services, onSuggestSchedule = { showsRecommendation = true })
                SettingsCategory.APPEARANCE -> AppearanceSettingsSection(services)
                SettingsCategory.TRAINING -> TrainingSettingsSection(services)
                SettingsCategory.PLATES -> PlatesSettingsSection(services)
                SettingsCategory.NOTIFICATIONS -> NotificationSettingsSection(services)
                SettingsCategory.HEALTH -> HealthSettingsSection(services)
                SettingsCategory.SYNC -> SyncSettingsSection()
                SettingsCategory.DATA -> DataSettingsSection(services)
                SettingsCategory.ABOUT -> {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_version)) },
                        trailingContent = { Text(appVersion()) },
                    )
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_catalog)) },
                        trailingContent = { Text("MoveKit") },
                    )
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.body_drawings)) },
                        trailingContent = { Text("MuscleMap") },
                        modifier = Modifier.clickable { showsMuscleMapLicense = true },
                    )
                    // Javna pravila privatnosti (GitHub Pages iz mape site/), na jeziku sučelja, kao na iOS-u.
                    val uriHandler = LocalUriHandler.current
                    val privacyUrl = stringResource(R.string.privacy_policy_url)
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.privacy_policy)) },
                        modifier = Modifier.clickable { runCatching { uriHandler.openUri(privacyUrl) } },
                    )
                }
            }
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

/** Atribucija i tekst MIT licence crteža tijela (`MuscleMapLicenseScreen` na iOS-u). */
@Composable
private fun MuscleMapLicenseDialog(services: AppServices, onDismiss: () -> Unit) {
    val license = remember { services.muscleMapLicense() }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("MuscleMap") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(stringResource(R.string.musclemap_intro))
                Text("github.com/Jsplice/MuscleMap", modifier = Modifier.padding(vertical = 8.dp))
                Text(license, style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
    )
}

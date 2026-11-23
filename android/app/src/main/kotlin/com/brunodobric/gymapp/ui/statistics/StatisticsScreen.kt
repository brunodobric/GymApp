package com.brunodobric.gymapp.ui.statistics

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.TabScaffold
import com.brunodobric.gymapp.ui.OpenRequest
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.StatsDetail
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.ExercisePoint
import com.brunodobric.gymapp.stats.FrequencyPoint
import com.brunodobric.gymapp.stats.OverviewPeriod
import com.brunodobric.gymapp.stats.WeekProgress
import com.brunodobric.gymapp.stats.weekProgress
import java.time.LocalDate
import com.brunodobric.gymapp.stats.PeriodSummary
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.StatisticsSettings
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.stats.periodSummary
import com.brunodobric.gymapp.ui.LineChart
import com.brunodobric.gymapp.ui.body.BodyScreen
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.WeightFormatter
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Statistika: kartica Pregled (tjedan, mjesec i godina, otvara [OverviewScreen]), mišići (tvrde serije tjedno), trend snage po mišićima,
 * osobni rekordi, napor i intenzitet, DOTS, mjere tijela i napredak vježbe. Mapa tijela i savjeti dolaze kasnije.
 */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatisticsScreen(
    services: AppServices,
    bodyRequest: OpenRequest? = null,
    onRequestHandled: () -> Unit = {},
    overviewRequest: OpenRequest? = null,
    onOverviewHandled: () -> Unit = {},
) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val locale = LocalConfiguration.current.locales[0]
    val calendar = remember(locale) { StatsCalendar.system(locale) }
    // Otvoren Pregled razdoblja (`OverviewPeriod.raw`); kartice Početne ga otvaraju na svom razdoblju.
    var overviewRaw by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(overviewRequest) {
        if (overviewRequest != null) {
            overviewRaw = overviewRequest.value
            onOverviewHandled()
        }
    }
    var openedKey by rememberSaveable { mutableStateOf<String?>(null) }
    var showsBody by rememberSaveable { mutableStateOf(false) }
    // Dodir na widget težine otvara praćenje tijela.
    LaunchedEffect(bodyRequest) {
        if (bodyRequest != null) {
            showsBody = true
            onRequestHandled()
        }
    }
    var showsRecords by rememberSaveable { mutableStateOf(false) }

    val exercises = remember(revision) {
        // Vježbe iz završenih treninga, od zadnje odrađene.
        store.finishedSessions().reversed()
            .flatMap { session -> session.orderedExercises.filter { exercise -> !exercise.isRemoved && exercise.sets.any { it.isCompleted } } }
            .distinctBy { it.exerciseKey }
            .map { it.exercise }
    }
    val settings = store.settings()
    // Teški dio statistike je izračunat unaprijed (`StatisticsCache`). Ovdje se računa samo ako ga još nema
    // ili je zastario (npr. novi dan ili trening u tijeku), što inače ne radi ništa.
    val cache = services.statistics
    LaunchedEffect(revision) { cache.refresh(revision, StatisticsSettings.of(settings)) }
    val stats = cache.snapshot
    val records = stats?.records.orEmpty()
    if (showsRecords) {
        RecordsScreen(records, settings.weightUnit, onClose = { showsRecords = false })
        return
    }
    OverviewPeriod.entries.firstOrNull { it.raw == overviewRaw }?.let { period ->
        OverviewScreen(services, period, onClose = { overviewRaw = null })
        return
    }
    if (showsBody) {
        BodyScreen(services, onClose = { showsBody = false })
        return
    }
    openedKey?.let { key ->
        val ref = exercises.firstOrNull { it.key == key }
        if (ref != null) {
            ExerciseProgressScreen(services, ref, onClose = { openedKey = null })
            return
        }
    }

    val info = remember(revision) { ExerciseInfoBuilder.provider(services.catalog, store.customExercises) }
    val isCardio = remember(info) { ExerciseInfoBuilder.isCardio(info) }
    // Detaljni prikaz (Postavke > Trening > Prikaz statistike) dodaje kartice; u osnovnom se ne računaju (kao na iOS-u).
    val isPro = settings.statsDetail == StatsDetail.PRO
    val loads = stats?.heatmap.orEmpty()
    val strengthTrends = stats?.trends.orEmpty()
    val weekly = stats?.weekly
    val effort = stats?.effort
    val intensity = stats?.intensity
    val dots = stats?.dots
    val weight = remember(settings.weightUnit, locale) { WeightFormatter(settings.weightUnit, locale) }
    val goal = settings.trainingDaysPerWeek
    val today = LocalDate.now()
    val overview = remember(revision, calendar, goal, isCardio, today) {
        val engine = StatisticsEngine(store)
        val now = Instant.now()
        OverviewFigures(
            week = engine.weekProgress(now, goal, calendar, isCardio),
            month = engine.periodSummary(OverviewPeriod.MONTH, now, now, goal, calendar, isCardio),
            year = engine.periodSummary(OverviewPeriod.YEAR, now, now, goal, calendar, isCardio),
            frequency = engine.frequency(12, now, calendar),
        )
    }

    TabScaffold(stringResource(R.string.tab_statistics)) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OverviewCard(overview.week, overview.month, overview.year, overview.frequency, locale, onOpen = { overviewRaw = it.raw })
            if (isPro) {
                weekly?.let { WeeklyReviewCard(it.first, it.second, locale) }
                MusclesCard(
                    cache.muscleDays,
                    onDaysChange = cache::changeMuscleDays,
                    loads = loads,
                    locale = locale,
                    diagrams = services.bodyMap,
                    female = settings.bodyMapFemale,
                )
                if (strengthTrends.isNotEmpty()) StrengthTrendCard(strengthTrends, locale)
            }

            RecordsCard(records, settings.weightUnit, onShowAll = { showsRecords = true })
            if (effort != null && intensity != null && (effort.rated > 0 || intensity.total > 0)) EffortIntensityCard(effort, intensity)
            dots?.let { DotsCard(it, weight, locale) }

            Card(Modifier.fillMaxWidth()) {
                ListItem(
                    modifier = Modifier.clickable { showsBody = true },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    headlineContent = { Text(stringResource(R.string.body)) },
                    supportingContent = { Text(stringResource(R.string.body_subtitle)) },
                )
            }

            Text(stringResource(R.string.exercise_progress), style = MaterialTheme.typography.titleMedium)
            if (exercises.isEmpty()) {
                Text(stringResource(R.string.history_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Card {
                exercises.forEachIndexed { index, ref ->
                    if (index > 0) HorizontalDivider()
                    ListItem(
                        modifier = Modifier.clickable { openedKey = ref.key },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(ref.name) },
                    )
                }
            }
        }
    }
}

/** Brojke kartice Pregled: tekući tjedan, mjesec i godina te treninzi po tjednu za zadnjih 12 tjedana. */
private class OverviewFigures(
    val week: WeekProgress,
    val month: PeriodSummary,
    val year: PeriodSummary,
    val frequency: List<FrequencyPoint>,
)

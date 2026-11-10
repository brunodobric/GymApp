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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
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
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.stats.BodyTracking
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.ExercisePoint
import com.brunodobric.gymapp.stats.OverviewPeriod
import com.brunodobric.gymapp.stats.PeriodSummary
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.stats.dotsScore
import com.brunodobric.gymapp.stats.effortDistribution
import com.brunodobric.gymapp.stats.intensityDistribution
import com.brunodobric.gymapp.stats.periodSummary
import com.brunodobric.gymapp.stats.weeklyReview
import com.brunodobric.gymapp.training.PRKind
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
 * Statistika: pregled tjedna, mjeseca ili godine, mišići (tvrde serije tjedno), trend snage po mišićima,
 * osobni rekordi, napor i intenzitet, DOTS, mjere tijela i napredak vježbe. Mapa tijela i savjeti dolaze kasnije.
 */
/** Četiri tjedna u sekundama, razdoblje kartice Napor i intenzitet. */
private const val FOUR_WEEKS = 28L * 24 * 3600

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatisticsScreen(services: AppServices) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val locale = LocalConfiguration.current.locales[0]
    val calendar = remember(locale) { StatsCalendar.system(locale) }
    var period by rememberSaveable { mutableStateOf(OverviewPeriod.WEEK) }
    var dateMillis by rememberSaveable { mutableStateOf(Instant.now().toEpochMilli()) }
    var openedKey by rememberSaveable { mutableStateOf<String?>(null) }
    var showsBody by rememberSaveable { mutableStateOf(false) }
    var showsRecords by rememberSaveable { mutableStateOf(false) }
    val date = Instant.ofEpochMilli(dateMillis)

    val exercises = remember(revision) {
        // Vježbe iz završenih treninga, od zadnje odrađene.
        store.finishedSessions().reversed()
            .flatMap { session -> session.orderedExercises.filter { exercise -> !exercise.isRemoved && exercise.sets.any { it.isCompleted } } }
            .distinctBy { it.exerciseKey }
            .map { it.exercise }
    }
    val settings = store.settings()
    val records = remember(revision) {
        StatisticsEngine(store).personalRecords(PRKind.tracked(settings), settings.prExcludedExerciseKeys)
    }
    if (showsRecords) {
        RecordsScreen(records, settings.weightUnit, onClose = { showsRecords = false })
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
    var muscleDays by rememberSaveable { mutableStateOf(MUSCLE_PERIODS.first()) }
    val loads = remember(revision, muscleDays) {
        val now = Instant.now()
        StatisticsEngine(store).heatmap(now.minusSeconds(muscleDays * 24L * 3600), now.plusSeconds(1), info)
    }
    val strengthTrends = remember(revision) { StatisticsEngine(store).strengthTrends(info = info) }
    val weekly = remember(revision, settings.goal, settings.trainingDaysPerWeek) {
        StatisticsEngine(store).weeklyReview(goal = settings.goal, plannedPerWeek = settings.trainingDaysPerWeek, info = info)
    }
    val effort = remember(revision) {
        val now = Instant.now()
        StatisticsEngine(store).effortDistribution(now.minusSeconds(FOUR_WEEKS), now.plusSeconds(1))
    }
    val intensity = remember(revision) {
        val now = Instant.now()
        StatisticsEngine(store).intensityDistribution(now.minusSeconds(FOUR_WEEKS), now.plusSeconds(1))
    }
    // DOTS uz spol i zadnju upisanu tjelesnu težinu, kao na iOS-u.
    val dots = remember(revision) {
        val sex = settings.sex
        val bodyWeight = BodyTracking(store).latest(BodyMeasurementKind.WEIGHT)?.value
        if (sex != null && bodyWeight != null && bodyWeight > 0) StatisticsEngine(store).dotsScore(bodyWeight, sex) else null
    }
    val weight = remember(settings.weightUnit, locale) { WeightFormatter(settings.weightUnit, locale) }
    val goal = settings.trainingDaysPerWeek
    val summary = remember(revision, period, dateMillis, calendar) {
        StatisticsEngine(store).periodSummary(period, date, goal = goal, calendar = calendar, isCardio = isCardio)
    }

    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.tab_statistics)) }) }) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OverviewPeriod.entries.forEach { option ->
                    FilterChip(
                        selected = option == period,
                        onClick = {
                            period = option
                            dateMillis = Instant.now().toEpochMilli()
                        },
                        label = { Text(stringResource(periodTitle(option))) },
                    )
                }
            }
            SummaryCard(summary, locale, onShift = { step -> dateMillis = period.shift(date, step, calendar).toEpochMilli() })
            WeeklyReviewCard(weekly.first, weekly.second, locale)

            MusclesCard(
                muscleDays,
                onDaysChange = { muscleDays = it },
                loads = loads,
                locale = locale,
                diagrams = services.bodyMap,
                female = settings.sex == Sex.FEMALE,
            )
            if (strengthTrends.isNotEmpty()) StrengthTrendCard(strengthTrends, locale)

            RecordsCard(records, settings.weightUnit, onShowAll = { showsRecords = true })
            if (effort.rated > 0 || intensity.total > 0) EffortIntensityCard(effort, intensity)
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

private fun periodTitle(period: OverviewPeriod): Int = when (period) {
    OverviewPeriod.WEEK -> R.string.period_week
    OverviewPeriod.MONTH -> R.string.period_month
    OverviewPeriod.YEAR -> R.string.period_year
}

@Composable
private fun SummaryCard(summary: PeriodSummary, locale: java.util.Locale, onShift: (Int) -> Unit) {
    val zone = ZoneId.systemDefault()
    val formatter = remember(locale) { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(zone) }
    // Kraj intervala je početak sljedećeg razdoblja, pa se prikazuje dan prije.
    val lastDay = summary.interval.end.minusSeconds(1)
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { onShift(-1) }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(R.string.previous_period))
                }
                Text(
                    formatter.format(summary.interval.start) + " – " + formatter.format(lastDay),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { onShift(1) }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = stringResource(R.string.next_period))
                }
            }
            Figure(stringResource(R.string.stat_workouts), summary.sessions.toString())
            Figure(stringResource(R.string.stat_trained_days), summary.trainedDays.toString())
            Figure(stringResource(R.string.stat_hard_sets), summary.hardSets.toString())
            Figure(stringResource(R.string.stat_time), DurationInput.format(summary.totalSeconds.toInt()))
            if (summary.cardioSeconds > 0) Figure(stringResource(R.string.stat_cardio), DurationInput.format(summary.cardioSeconds))
            summary.weeklyGoal?.let { goal ->
                if (summary.period != OverviewPeriod.WEEK) {
                    Figure(stringResource(R.string.stat_per_week), String.format(locale, "%.1f / %d", summary.sessionsPerWeek, goal))
                }
            }
        }
    }
}

@Composable
private fun Figure(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}

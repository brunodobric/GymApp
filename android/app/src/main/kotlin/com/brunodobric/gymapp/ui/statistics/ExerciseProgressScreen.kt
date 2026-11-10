package com.brunodobric.gymapp.ui.statistics

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.stats.DoneExercises
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.ExercisePoint
import com.brunodobric.gymapp.stats.ExerciseStatus
import com.brunodobric.gymapp.stats.ExerciseTrendEntry
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.TrendMeasure
import com.brunodobric.gymapp.stats.exerciseTrend
import com.brunodobric.gymapp.stats.repMaxTable
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.ui.ChartSeries
import com.brunodobric.gymapp.ui.DatedLineChart
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.WeightFormatter
import java.text.NumberFormat
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Napredak jedne vježbe (`ExerciseProgressScreen` na iOS-u): status u zadnjih 8 tjedana, crta procjene 1RM
 * (ili najveće težine) po treningu, najteža serija po ponavljanjima i svi treninzi. Otvara se iz Statistike
 * i s detalja vježbe ("Napredak i rekordi"). Graf može usporediti drugu vježbu i računati 1RM po Brzyckom.
 * Izbor mjere (volumen) i raspona s iOS-a dolaze kasnije.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExerciseProgressScreen(services: AppServices, ref: ExerciseRef, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val engine = remember(store) { StatisticsEngine(store) }
    var useBrzycki by rememberSaveable { mutableStateOf(false) }
    var comparedKey by rememberSaveable { mutableStateOf<String?>(null) }
    var pickingCompared by remember { mutableStateOf(false) }
    val formula = if (useBrzycki) SetMetrics.OneRepMaxFormula.BRZYCKI else SetMetrics.OneRepMaxFormula.EPLEY
    val points = remember(revision, ref.key, formula) { engine.progress(ref, formula) }
    val locale = LocalConfiguration.current.locales[0]
    val done = remember(revision, locale) { DoneExercises.fetch(store, locale).filter { it.key != ref.key } }
    val compared = done.firstOrNull { it.key == comparedKey }
    val comparedRef = compared?.ref
    val comparedPoints = remember(revision, comparedRef?.key, formula) { comparedRef?.let { engine.progress(it, formula) } ?: emptyList() }
    val trend = remember(revision, ref.key) {
        engine.exerciseTrend(ref, info = ExerciseInfoBuilder.provider(services.catalog, store.customExercises))
    }
    val repMax = remember(revision, ref.key) { engine.repMaxTable(ref) }
    val unit = store.settings().weightUnit
    val weight = remember(unit, locale) { WeightFormatter(unit, locale) }
    val formatter = remember(locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(ZoneId.systemDefault())
    }
    BackHandler(onBack = onClose)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(ref.name) },
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
            trend?.let { StatusCard(it, locale) }

            val usesOneRepMax = (points + comparedPoints).any { it.estimatedOneRepMaxKg != null }
            val mainColor = MaterialTheme.colorScheme.primary
            val comparedColor = MaterialTheme.colorScheme.tertiary
            val lines = listOfNotNull(
                ChartSeries(points.map { it.date.toEpochMilli() to chartValue(it) }, mainColor),
                if (comparedRef != null) ChartSeries(comparedPoints.map { it.date.toEpochMilli() to chartValue(it) }, comparedColor) else null,
            )
            if (points.count { chartValue(it) > 0 } < 2 && comparedRef == null) {
                Text(stringResource(R.string.chart_needs_two), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Text(
                    stringResource(if (usesOneRepMax) R.string.estimated_one_rep_max else R.string.heaviest_weight),
                    style = MaterialTheme.typography.titleSmall,
                )
                val chartLabel = if (compared != null) {
                    stringResource(R.string.progress_chart_compare, ref.name, compared.name)
                } else {
                    stringResource(R.string.progress_chart, ref.name)
                }
                DatedLineChart(lines, Modifier.fillMaxWidth().height(200.dp).semantics { contentDescription = chartLabel })
                if (compared != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        LegendItem(ref.name, mainColor)
                        LegendItem(compared.name, comparedColor)
                    }
                }
            }
            if (usesOneRepMax) {
                Text(
                    stringResource(R.string.one_rep_max_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.brzycki_instead_of_epley), modifier = Modifier.weight(1f))
                    Switch(checked = useBrzycki, onCheckedChange = { useBrzycki = it })
                }
            }
            if (done.isNotEmpty()) {
                OutlinedButton(onClick = { pickingCompared = true }, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        if (compared != null) stringResource(R.string.compare_with, compared.name) else stringResource(R.string.compare_other_exercise),
                    )
                }
            }

            if (repMax.isNotEmpty()) {
                Text(stringResource(R.string.rep_max_table), style = MaterialTheme.typography.titleSmall)
                Card {
                    repMax.forEachIndexed { index, entry ->
                        if (index > 0) HorizontalDivider()
                        ListItem(
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(stringResource(R.string.reps_plus, entry.reps)) },
                            supportingContent = { Text(formatter.format(entry.date)) },
                            trailingContent = { Text(weight.string(entry.weightKg)) },
                        )
                    }
                }
            }

            Text(pluralStringResource(R.plurals.workout_count, points.size, points.size), style = MaterialTheme.typography.titleSmall)
            Card {
                points.reversed().forEachIndexed { index, point ->
                    if (index > 0) HorizontalDivider()
                    val oneRepMax = point.estimatedOneRepMaxKg
                    ListItem(
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = {
                            Text(if (point.bestWeightKg > 0) "${weight.string(point.bestWeightKg)} × ${point.bestReps}" else "× ${point.bestReps}")
                        },
                        supportingContent = { Text(formatter.format(point.date)) },
                        trailingContent = if (oneRepMax != null) {
                            { Text("1RM " + weight.string(oneRepMax)) }
                        } else {
                            null
                        },
                    )
                }
            }
        }
    }

    if (pickingCompared) {
        AlertDialog(
            onDismissRequest = { pickingCompared = false },
            title = { Text(stringResource(R.string.compare_other_exercise)) },
            text = {
                Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
                    if (compared != null) {
                        ListItem(
                            modifier = Modifier.clickable {
                                comparedKey = null
                                pickingCompared = false
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(stringResource(R.string.no_comparison)) },
                        )
                    }
                    done.forEach { item ->
                        ListItem(
                            modifier = Modifier.clickable {
                                comparedKey = item.key
                                pickingCompared = false
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(item.name) },
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { pickingCompared = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Boja i naziv crte ispod grafa kad su na njemu dvije vježbe. */
@Composable
private fun LegendItem(name: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(10.dp).background(color, CircleShape))
        Text(name, style = MaterialTheme.typography.bodySmall)
    }
}

/** Status napretka u zadnjih 8 tjedana i mjesečna promjena, s objašnjenjem kako se računa. */
@Composable
private fun StatusCard(entry: ExerciseTrendEntry, locale: Locale) {
    val trend = entry.trend
    val change = trend.monthlyChange
    val measure = stringResource(if (entry.measure == TrendMeasure.ONE_REP_MAX) R.string.measure_one_rep_max else R.string.measure_reps)
    Card(Modifier.fillMaxWidth()) {
        ListItem(
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            headlineContent = { Text(stringResource(R.string.last_8_weeks)) },
            supportingContent = if (change != null) {
                { Text(stringResource(R.string.per_month, signedPercent(change, locale))) }
            } else {
                null
            },
            trailingContent = {
                Text(stringResource(statusTitle(trend.status)), color = statusColor(trend.status), style = MaterialTheme.typography.titleSmall)
            },
        )
    }
    val footer = if (trend.status == ExerciseStatus.INSUFFICIENT_DATA) {
        stringResource(R.string.status_footer_insufficient, measure)
    } else {
        stringResource(R.string.status_footer, measure, NumberFormat.getPercentInstance(locale).format(trend.noise))
    }
    Text(footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

internal fun statusTitle(status: ExerciseStatus): Int = when (status) {
    ExerciseStatus.IMPROVING -> R.string.status_improving
    ExerciseStatus.STABLE -> R.string.status_stable
    ExerciseStatus.PLATEAU -> R.string.status_plateau
    ExerciseStatus.DECLINING -> R.string.status_declining
    ExerciseStatus.INSUFFICIENT_DATA -> R.string.status_insufficient
}

@Composable
private fun statusColor(status: ExerciseStatus): Color = when (status) {
    ExerciseStatus.IMPROVING -> Color(0xFF2E7D32)
    ExerciseStatus.DECLINING -> MaterialTheme.colorScheme.error
    ExerciseStatus.PLATEAU -> Color(0xFFEF6C00)
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}

/** Promjena s predznakom, npr. "+2,8 %" ili "−1 %" (`ChangeFormat.percent` na iOS-u). */
internal fun signedPercent(change: Double, locale: Locale): String {
    val format = NumberFormat.getPercentInstance(locale).apply { maximumFractionDigits = 1 }
    val text = format.format(kotlin.math.abs(change))
    return when {
        change > 0 -> "+$text"
        change < 0 -> "−$text"
        else -> text
    }
}

private fun chartValue(point: ExercisePoint): Double = point.estimatedOneRepMaxKg ?: point.bestWeightKg

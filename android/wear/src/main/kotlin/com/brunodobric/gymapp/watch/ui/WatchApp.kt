package com.brunodobric.gymapp.watch.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.watch.HealthTracker
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.wear.PlannedWorkoutPayload
import com.brunodobric.gymapp.wear.WatchContextPayload
import com.brunodobric.gymapp.wear.WatchError
import com.brunodobric.gymapp.wear.WatchSummary
import com.brunodobric.gymapp.wear.WatchWorkoutStore
import java.time.Instant
import kotlinx.coroutines.delay

/** Naglasne boje kao na mobitelu (`AccentPalette`, tamna vrijednost jer je sat uvijek taman). */
internal fun accentColor(raw: String?): Color = when (raw) {
    "indigo" -> Color(0xFF7F7AF7)
    "purple" -> Color(0xFFA66CEB)
    "pink" -> Color(0xFFEA4F8B)
    "teal" -> Color(0xFF1A98A7)
    "graphite" -> Color(0xFF868C98)
    else -> Color(0xFF4C88FA)
}

/** Zelena za završenu seriju (kao kvačica na mobitelu), ne prati naglasnu boju. */
internal val DoneGreen = Color(0xFF30D158)

@Composable
fun WatchApp(store: WatchWorkoutStore, health: HealthTracker, onStart: (PlannedWorkoutPayload) -> Unit) {
    val state by store.state.collectAsStateWithLifecycle()
    val accent = accentColor(state.context.accent)
    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(primary = accent, onPrimary = Color.White)) {
        AppScaffold {
            var plan by remember { mutableStateOf<PlannedWorkoutPayload?>(null) }
            val summary = state.summary
            val error = state.error
            when {
                error != null -> MessageScreen(
                    title = stringResource(R.string.error_title),
                    message = stringResource(
                        if (error == WatchError.SET_INCOMPLETE) R.string.error_set_incomplete else R.string.error_save_failed,
                    ),
                    confirm = stringResource(R.string.ok),
                    onConfirm = store::clearError,
                )
                summary != null -> SummaryScreen(summary, state.context, onDone = store::closeSummary)
                state.active != null -> WorkoutScreen(store, state, health)
                plan != null -> PlanScreen(
                    plan = plan!!,
                    context = state.context,
                    onStart = { selected ->
                        plan = null
                        onStart(selected)
                    },
                    onBack = { plan = null },
                )
                else -> HomeScreen(state.context, onSelect = { plan = it })
            }
            // Trening je počeo s mobitela dok je bio otvoren detalj: detalj se zatvara.
            LaunchedEffect(state.active?.id) { if (state.active != null) plan = null }
        }
    }
}

/** Sadašnje vrijeme koje se osvježava svake sekunde (trajanje treninga, odmor, štoperica). */
@Composable
internal fun rememberNow(periodMillis: Long = 1000): Instant {
    val now by produceState(Instant.now()) {
        while (true) {
            value = Instant.now()
            delay(periodMillis)
        }
    }
    return now
}

/** "1:05" ili "1:02:05". */
internal fun clock(totalSeconds: Long): String {
    val seconds = totalSeconds.coerceAtLeast(0)
    val hours = seconds / 3600
    val minutes = seconds % 3600 / 60
    val rest = seconds % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, rest) else "%d:%02d".format(minutes, rest)
}

internal val listPadding = PaddingValues(top = 32.dp, bottom = 48.dp, start = 10.dp, end = 10.dp)

// MARK: - Početni ekran

@Composable
private fun HomeScreen(context: WatchContextPayload, onSelect: (PlannedWorkoutPayload) -> Unit) {
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(state = listState, contentPadding = listPadding, modifier = Modifier.fillMaxSize()) {
        if (context.upcoming.isEmpty() && context.templates.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.home_empty),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = 8.dp),
                )
            }
            return@ScalingLazyColumn
        }
        if (context.upcoming.isNotEmpty()) {
            item { ListHeader { Text(stringResource(R.string.home_next)) } }
            items(context.upcoming, key = { "u" + it.id }) { plan -> PlanButton(plan, context, showsSchedule = true, onSelect) }
        }
        val others = context.templates.filter { template -> context.upcoming.none { it.templateId == template.templateId } }
        if (others.isNotEmpty()) {
            item {
                ListHeader {
                    Text(stringResource(if (context.upcoming.isEmpty()) R.string.home_workouts else R.string.home_other_workouts))
                }
            }
            items(others, key = { "t" + it.id }) { plan -> PlanButton(plan, context, showsSchedule = false, onSelect) }
        }
    }
}

@Composable
private fun PlanButton(plan: PlannedWorkoutPayload, context: WatchContextPayload, showsSchedule: Boolean, onSelect: (PlannedWorkoutPayload) -> Unit) {
    val count = pluralStringResource(R.plurals.exercise_count, plan.exercises.size, plan.exercises.size)
    val minutes = plan.estimatedMinutes(context.restDefaults)
    val details = listOfNotNull(
        plan.scheduleName?.takeIf { showsSchedule },
        count,
        minutes?.let { stringResource(R.string.approx_minutes, it) },
    ).joinToString(" · ")
    FilledTonalButton(
        onClick = { onSelect(plan) },
        modifier = Modifier.fillMaxWidth(),
        secondaryLabel = { Text(details, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        label = { Text(plan.name, maxLines = 2, overflow = TextOverflow.Ellipsis) },
    )
}

// MARK: - Detalj treninga

@Composable
private fun PlanScreen(plan: PlannedWorkoutPayload, context: WatchContextPayload, onStart: (PlannedWorkoutPayload) -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(state = listState, contentPadding = listPadding, modifier = Modifier.fillMaxSize()) {
        item {
            Text(plan.name, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, maxLines = 2)
        }
        item {
            Button(onClick = { onStart(plan) }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.start)) })
        }
        items(plan.exercises) { exercise ->
            val cardio = if (exercise.isCardio) " · " + stringResource(R.string.cardio) else ""
            Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp)) {
                Text(exercise.exercise.name, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    pluralStringResource(R.plurals.set_count, exercise.sets.size, exercise.sets.size) + cardio,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (context.savesToHealth) {
            item {
                Text(
                    stringResource(R.string.plan_measures),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

// MARK: - Sažetak

@Composable
private fun SummaryScreen(summary: WatchSummary, context: WatchContextPayload, onDone: () -> Unit) {
    BackHandler(onBack = onDone)
    val weight = WeightFormatter(context.unit)
    val rows = buildList {
        add(stringResource(R.string.summary_duration) to clock(summary.durationSeconds))
        if (summary.mix != SessionMix.CARDIO) {
            add(stringResource(R.string.summary_sets) to summary.completedSets.toString())
            if (summary.volumeKg > 0) add(stringResource(R.string.summary_volume) to weight.string(summary.volumeKg))
        }
        summary.cardio?.let { cardio ->
            add(stringResource(R.string.cardio) to stringResource(R.string.minutes_short, (cardio.seconds + 30) / 60))
        }
        summary.activeEnergyKilocalories?.let { add(stringResource(R.string.summary_energy) to "${it.toInt()} kcal") }
        summary.averageHeartRate?.let { add(stringResource(R.string.summary_heart_rate) to "${it.toInt()} BPM") }
    }
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(state = listState, contentPadding = listPadding, modifier = Modifier.fillMaxSize()) {
        item { ListHeader { Text(stringResource(R.string.summary_title)) } }
        item { Text(summary.name, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, maxLines = 2) }
        items(rows) { (title, value) ->
            Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp)) {
                Text(title, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(value, style = MaterialTheme.typography.titleLarge)
            }
        }
        item { Button(onClick = onDone, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.done)) }) }
    }
}

// MARK: - Poruka i potvrda

/** Poruka preko cijelog zaslona s glavnim i, po želji, sporednim gumbom (potvrde završetka i odbacivanja). */
@Composable
internal fun MessageScreen(
    title: String,
    message: String,
    confirm: String,
    onConfirm: () -> Unit,
    cancel: String? = null,
    onCancel: () -> Unit = {},
    destructive: Boolean = false,
) {
    if (cancel != null) BackHandler(onBack = onCancel)
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(state = listState, contentPadding = listPadding, modifier = Modifier.fillMaxSize()) {
        item { Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center) }
        item {
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        item { Spacer(Modifier.height(4.dp)) }
        item {
            val colors = if (destructive) {
                ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
            } else {
                ButtonDefaults.buttonColors()
            }
            Button(onClick = onConfirm, colors = colors, modifier = Modifier.fillMaxWidth(), label = { Text(confirm) })
        }
        if (cancel != null) {
            item { FilledTonalButton(onClick = onCancel, modifier = Modifier.fillMaxWidth(), label = { Text(cancel) }) }
        }
    }
}

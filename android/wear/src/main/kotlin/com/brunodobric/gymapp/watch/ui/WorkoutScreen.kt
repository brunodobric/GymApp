package com.brunodobric.gymapp.watch.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.wear.compose.foundation.pager.HorizontalPager
import androidx.wear.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.CircularProgressIndicator
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.HorizontalPageIndicator
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.training.SetField
import com.brunodobric.gymapp.training.SetFieldValues
import com.brunodobric.gymapp.units.WeightUnit
import com.brunodobric.gymapp.watch.HealthTracker
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.wear.ExerciseSnapshot
import com.brunodobric.gymapp.wear.SetSnapshot
import com.brunodobric.gymapp.wear.SnapshotEngine
import com.brunodobric.gymapp.wear.WatchUiState
import com.brunodobric.gymapp.wear.WatchWorkoutStore
import com.brunodobric.gymapp.wear.fieldValues
import java.time.Duration
import kotlinx.coroutines.launch

private enum class Confirmation { FINISH, DISCARD, NOTHING_COMPLETED }

private const val CONTROLS_PAGE = 0
private const val SET_PAGE = 1
private const val LIST_PAGE = 2

/** Aktivni trening: lijevo kontrole (trajanje, puls, završetak), u sredini serija ili odmor, desno popis vježbi. */
@Composable
internal fun WorkoutScreen(store: WatchWorkoutStore, state: WatchUiState, health: HealthTracker) {
    var confirmation by remember { mutableStateOf<Confirmation?>(null) }
    when (confirmation) {
        Confirmation.FINISH -> MessageScreen(
            title = stringResource(R.string.finish_title),
            message = stringResource(R.string.finish_message),
            confirm = stringResource(R.string.finish_confirm),
            onConfirm = { confirmation = if (store.finish()) null else Confirmation.NOTHING_COMPLETED },
            cancel = stringResource(R.string.continue_workout),
            onCancel = { confirmation = null },
        )
        Confirmation.DISCARD -> MessageScreen(
            title = stringResource(R.string.discard_title),
            message = stringResource(R.string.discard_message),
            confirm = stringResource(R.string.discard_confirm),
            onConfirm = {
                confirmation = null
                store.discard()
            },
            cancel = stringResource(R.string.continue_workout),
            onCancel = { confirmation = null },
            destructive = true,
        )
        Confirmation.NOTHING_COMPLETED -> MessageScreen(
            title = stringResource(R.string.nothing_completed_title),
            message = stringResource(R.string.nothing_completed_message),
            confirm = stringResource(R.string.discard_confirm),
            onConfirm = {
                confirmation = null
                store.discard()
            },
            cancel = stringResource(R.string.continue_workout),
            onCancel = { confirmation = null },
            destructive = true,
        )
        null -> WorkoutPager(store, state, health, onFinish = { confirmation = Confirmation.FINISH }, onDiscard = { confirmation = Confirmation.DISCARD })
    }
}

@Composable
private fun WorkoutPager(store: WatchWorkoutStore, state: WatchUiState, health: HealthTracker, onFinish: () -> Unit, onDiscard: () -> Unit) {
    val pager = rememberPagerState(initialPage = SET_PAGE) { 3 }
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
            when (page) {
                CONTROLS_PAGE -> ControlsPage(state, health, onFinish, onDiscard)
                SET_PAGE -> {
                    val timer = state.restTimer
                    if (state.isResting && timer != null) {
                        RestPage(store, state)
                    } else {
                        SetPage(store, state, isCurrentPage = pager.currentPage == SET_PAGE, onFinish = onFinish)
                    }
                }
                else -> ExerciseListPage(store, state, onSelect = { scope.launch { pager.animateScrollToPage(SET_PAGE) } })
            }
        }
        HorizontalPageIndicator(pagerState = pager, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 4.dp))
    }
}

// MARK: - Kontrole

@Composable
private fun ControlsPage(state: WatchUiState, health: HealthTracker, onFinish: () -> Unit, onDiscard: () -> Unit) {
    val active = state.active ?: return
    val now = rememberNow()
    val heartRate by health.heartRate.collectAsStateWithLifecycle()
    val energy by health.activeEnergyKilocalories.collectAsStateWithLifecycle()
    Column(
        Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, top = 30.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            clock(Duration.between(active.startedAt, now).seconds),
            fontSize = 34.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFFFFD60A),
            maxLines = 1,
        )
        if (state.showsHealthMetrics) {
            Column {
                Metric("♥", heartRate, "BPM", Color(0xFFFF453A))
                Metric("🔥", energy, "kcal", Color(0xFFFF9F0A))
            }
        }
        Column {
            if (!state.isController) {
                Text(stringResource(R.string.phone_leads), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                pluralStringResource(R.plurals.completed_sets, active.completedSetCount, active.completedSetCount) + " · " +
                    stringResource(R.string.exercises_progress, active.completedExerciseCount, active.visibleExercises.size),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            Button(onClick = onFinish, modifier = Modifier.weight(1f), label = { Text(stringResource(R.string.finish), maxLines = 1) })
            FilledTonalButton(onClick = onDiscard, modifier = Modifier.weight(1f), label = { Text(stringResource(R.string.discard), maxLines = 1) })
        }
    }
}

@Composable
private fun Metric(symbol: String, value: Double?, unit: String, color: Color) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(symbol, color = color, style = MaterialTheme.typography.bodyMedium)
        Text(value?.let { "${Math.round(it)}" } ?: "–", style = MaterialTheme.typography.titleLarge)
        Text(unit, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// MARK: - Serija

/**
 * Trenutna vježba i serija: gore vježba, u sredini vrijednosti (kruna mijenja odabrano polje, dodir bira polje) i
 * "prošli put", a pri dnu − kvačica +. Serija s trajanjem umjesto toga ima štopericu.
 */
@Composable
private fun SetPage(store: WatchWorkoutStore, state: WatchUiState, isCurrentPage: Boolean, onFinish: () -> Unit) {
    val current = state.currentSet
    if (current == null || state.showsFinishPrompt) {
        ExerciseDone(store, state, onFinish)
        return
    }
    val (exercise, set) = current
    val fields = SetField.fields(exercise.inputType)
    var selected by remember(set.id) { mutableStateOf(fields.first()) }
    val unit = state.unit
    val focus = remember { FocusRequester() }
    var rotary by remember { mutableFloatStateOf(0f) }

    fun move(steps: Int) {
        val value = selected.value(set.fieldValues, unit)
        val moved = selected.moved(value, steps, selected.step(unit, exercise.weightStep))
        val range = selected.range(unit)
        store.setValue(moved.coerceIn(range.start, range.endInclusive), selected, set.id)
    }

    LaunchedEffect(isCurrentPage, set.id) { if (isCurrentPage) runCatching { focus.requestFocus() } }
    val stopwatch = state.stopwatch?.takeIf { it.setId == set.id }
    val usesStopwatch = SetField.DURATION in fields
    val now = rememberNow(if (stopwatch?.isRunning == true) 250 else 1000)

    Column(
        Modifier
            .fillMaxSize()
            .onRotaryScrollEvent { event ->
                rotary += event.verticalScrollPixels
                val steps = (rotary / ROTARY_STEP_PIXELS).toInt()
                if (steps != 0) {
                    rotary -= steps * ROTARY_STEP_PIXELS
                    move(steps)
                }
                true
            }
            .focusRequester(focus)
            .focusable()
            .padding(start = 14.dp, end = 14.dp, top = 28.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                (if (state.isCardio(exercise)) "🏃 " else "") + exercise.exercise.name,
                style = MaterialTheme.typography.titleSmall,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(setLabel(exercise, set), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            for (field in fields) {
                val text = if (field == SetField.DURATION && stopwatch != null) {
                    clock(stopwatch.elapsedSeconds(now).toLong())
                } else {
                    field.text(set.fieldValues, unit)
                }
                FieldValue(text, fieldUnit(field, unit), isSelected = field == selected, onClick = { selected = field })
            }
        }
        previousText(state, exercise, set)?.let { previous ->
            Text(
                stringResource(R.string.previous_time, previous),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (usesStopwatch) {
                FilledTonalButton(onClick = { store.toggleStopwatch(set.id) }, modifier = Modifier.size(48.dp), label = {
                    Text(if (stopwatch?.isRunning == true) "❚❚" else "▶", textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                })
            } else {
                FilledTonalButton(onClick = { move(-1) }, modifier = Modifier.size(44.dp), label = { StepText("−") })
            }
            Button(
                onClick = store::completeCurrentSet,
                colors = ButtonDefaults.buttonColors(containerColor = DoneGreen, contentColor = Color.Black),
                modifier = Modifier.size(56.dp),
                label = { Text("✓", fontSize = 26.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) },
            )
            FilledTonalButton(onClick = { move(1) }, modifier = Modifier.size(44.dp), label = { StepText("+") })
        }
    }
}

private const val ROTARY_STEP_PIXELS = 48f

@Composable
private fun StepText(text: String) {
    Text(text, fontSize = 22.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
}

@Composable
private fun FieldValue(text: String, unit: String, isSelected: Boolean, onClick: () -> Unit) {
    val border = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer
    Column(
        Modifier
            .background(border.copy(alpha = if (isSelected) 0.35f else 1f), RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(text, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        Text(unit, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun fieldUnit(field: SetField, unit: WeightUnit): String = when (field) {
    SetField.WEIGHT -> unit.symbol
    SetField.EXTRA_WEIGHT -> "+" + unit.symbol
    SetField.REPS -> stringResource(R.string.reps_short)
    SetField.DURATION -> stringResource(R.string.duration_unit)
    SetField.DISTANCE -> "m"
}

@Composable
private fun setLabel(exercise: ExerciseSnapshot, set: SetSnapshot): String {
    val ordered = exercise.orderedSets
    val number = ordered.indexOfFirst { it.id == set.id } + 1
    val base = stringResource(R.string.set_of, number, ordered.size)
    return if (set.kind == SetKind.WARM_UP) base + " · " + stringResource(R.string.warm_up) else base
}

private fun previousText(state: WatchUiState, exercise: ExerciseSnapshot, set: SetSnapshot): String? {
    val previous = state.previousSet(set, exercise) ?: return null
    val values = SetFieldValues(previous.weightKg, previous.reps, previous.extraWeightKg, previous.durationSeconds, previous.distanceMeters)
    return SetField.fields(exercise.inputType).joinToString(" × ") { it.text(values, state.unit) }
}

/** Vježba nema nezavršenih serija (ili su sve gotove): dodaj seriju, idi dalje ili završi trening. */
@Composable
private fun ExerciseDone(store: WatchWorkoutStore, state: WatchUiState, onFinish: () -> Unit) {
    val exercise = state.currentExercise
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(state = listState, contentPadding = listPadding, modifier = Modifier.fillMaxSize()) {
        item {
            Text(
                stringResource(if (state.showsFinishPrompt) R.string.all_sets_done else R.string.exercise_done),
                style = MaterialTheme.typography.titleSmall,
                textAlign = TextAlign.Center,
            )
        }
        if (state.showsFinishPrompt) {
            item { Button(onClick = onFinish, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.finish_confirm)) }) }
        } else if (state.canMoveExercise(1)) {
            item {
                Button(onClick = { store.moveExercise(1) }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.next_exercise)) })
            }
        }
        if (exercise != null) {
            item {
                FilledTonalButton(onClick = { store.addSet(exercise.id) }, modifier = Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.add_set)) })
            }
        }
    }
}

// MARK: - Odmor

@Composable
private fun RestPage(store: WatchWorkoutStore, state: WatchUiState) {
    val timer = state.restTimer ?: return
    val now = rememberNow(250)
    val remaining = timer.remaining(now)
    val next = state.currentSet?.first
    Box(Modifier.fillMaxSize()) {
        CircularProgressIndicator(progress = { (1 - timer.progress(now)).toFloat() }, modifier = Modifier.fillMaxSize().padding(2.dp))
        Column(
            Modifier.fillMaxSize().padding(horizontal = 18.dp, vertical = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(stringResource(R.string.rest), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(clock(Math.ceil(remaining).toLong()), fontSize = 40.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                FilledTonalButton(onClick = { store.adjustRest(-10) }, modifier = Modifier.size(44.dp), label = { StepText("−10") })
                Button(onClick = store::skipRest, modifier = Modifier.height(44.dp), label = { Text(stringResource(R.string.skip_rest), maxLines = 1) })
                FilledTonalButton(onClick = { store.adjustRest(10) }, modifier = Modifier.size(44.dp), label = { StepText("+10") })
            }
            Text(
                next?.let { stringResource(R.string.next_up, it.exercise.name) }.orEmpty(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// MARK: - Popis vježbi

/** Pregled cijelog treninga. Dodir na vježbu otvara je na ekranu serije, a dodir na završenu seriju poništava kvačicu. */
@Composable
private fun ExerciseListPage(store: WatchWorkoutStore, state: WatchUiState, onSelect: () -> Unit) {
    val active = state.active ?: return
    val engine = SnapshotEngine(active)
    val listState = rememberScalingLazyListState()
    ScalingLazyColumn(state = listState, contentPadding = listPadding, modifier = Modifier.fillMaxSize()) {
        item { ListHeader { Text(stringResource(R.string.exercises)) } }
        items(active.visibleExercises, key = { it.id }) { exercise ->
            val isCurrent = exercise.id == state.currentExerciseId
            val superset = if (engine.group(exercise.id).size > 1) " · " + stringResource(R.string.superset) else ""
            val done = if (exercise.sets.isNotEmpty() && exercise.isFullyCompleted) "✓ " else ""
            val button: @Composable () -> Unit = {
                Column(Modifier.fillMaxWidth()) {
                    Text(done + exercise.exercise.name, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(
                        stringResource(R.string.sets_progress, exercise.completedSetCount, exercise.sets.size) + superset,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            if (isCurrent) {
                Button(onClick = { store.select(exercise.id); onSelect() }, modifier = Modifier.fillMaxWidth(), label = { button() })
            } else {
                FilledTonalButton(onClick = { store.select(exercise.id); onSelect() }, modifier = Modifier.fillMaxWidth(), label = { button() })
            }
        }
        val completed = active.visibleExercises.flatMap { exercise -> exercise.orderedSets.filter { it.isCompleted }.map { exercise to it } }
        if (completed.isNotEmpty()) {
            item { ListHeader { Text(stringResource(R.string.completed_sets_header)) } }
            items(completed.takeLast(MAX_UNDO_ROWS), key = { it.second.id }) { (exercise, set) ->
                val values = SetField.fields(exercise.inputType).joinToString(" × ") { it.text(set.fieldValues, state.unit) }
                FilledTonalButton(
                    onClick = { store.uncomplete(set.id) },
                    modifier = Modifier.fillMaxWidth(),
                    secondaryLabel = { Text(stringResource(R.string.tap_to_undo), maxLines = 1) },
                    label = { Text("${exercise.exercise.name}: $values", maxLines = 2, overflow = TextOverflow.Ellipsis) },
                )
            }
        }
        item { Spacer(Modifier.height(8.dp)) }
    }
}

/** Najviše zadnjih završenih serija za poništavanje na popisu. */
private const val MAX_UNDO_ROWS = 6

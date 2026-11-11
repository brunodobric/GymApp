package com.brunodobric.gymapp.ui.workout

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.ref
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.WorkoutError
import com.brunodobric.gymapp.training.restDefaults
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.rememberTicker
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Duration
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * Trening u tijeku, prvi korak: vježbe sa serijama, unos težine i ponavljanja, kvačica s odmorom i završetak
 * sa sažetkom ([WorkoutSummaryScreen]).
 * Svaka izmjena odmah se sprema (`WorkoutEngine.touch`), pa prekinut trening ostaje sačuvan.
 * Izbornik vježbe dodaje zagrijavanje i izbacuje vježbu, a dodir na broj serije briše seriju; oboje se
 * može poništiti iz snackbara. Odmor se produljuje ili skraćuje za 15 s.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkoutScreen(services: AppServices, onClose: () -> Unit) {
    val store = services.store
    rememberStoreRevision(store)
    var finishedId by rememberSaveable { mutableStateOf<String?>(null) }
    finishedId?.let { id ->
        WorkoutSummaryScreen(services, UUID.fromString(id), onClose = onClose)
        return
    }
    val session = store.activeSession()
    if (session == null) {
        // Trening je završen ili odbačen (npr. iz obavijesti): ekran se zatvara.
        LaunchedEffect(Unit) { onClose() }
        return
    }
    val engine = remember(store) { WorkoutEngine(store) }
    val settings = store.settings()
    val unit = settings.weightUnit
    var picking by rememberSaveable { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var plateTarget by rememberSaveable { mutableStateOf<String?>(null) }
    // Vježba za koju se bira partner u supersetu.
    var supersetSource by rememberSaveable { mutableStateOf<String?>(null) }
    val now = rememberTicker()
    RestEndEffects(
        endsAt = session.restTimerEndsAt,
        soundEnabled = settings.restEndSoundEnabled,
        notificationsEnabled = settings.restNotificationEnabled,
        onExpired = { engine.cancelRest(session) },
    )
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val undoLabel = stringResource(R.string.undo)
    val setDeleted = stringResource(R.string.set_deleted)
    val exerciseRemoved = stringResource(R.string.exercise_removed)

    /** Poruka s "Poništi"; prethodna poruka se zamjenjuje. */
    fun offerUndo(message: String, undo: () -> Unit) {
        snackbar.currentSnackbarData?.dismiss()
        scope.launch {
            val result = snackbar.showSnackbar(message, actionLabel = undoLabel, duration = SnackbarDuration.Short)
            if (result == SnackbarResult.ActionPerformed) undo()
        }
    }

    BackHandler(enabled = picking) { picking = false }
    BackHandler(enabled = !picking, onBack = onClose)

    if (picking) {
        ExercisePicker(
            services = services,
            onPick = { summary ->
                val input = inputTypeOf(services, summary)
                engine.addExercise(summary.ref, input, session)
                picking = false
            },
            onClose = { picking = false },
        )
        return
    }

    val isCompound: (String) -> Boolean? = { key ->
        if (key.startsWith("c:")) services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(session.name)
                        val seconds = Duration.between(session.startedAt, now).seconds.coerceAtLeast(0).toInt()
                        Text(DurationInput.format(seconds), style = MaterialTheme.typography.bodySmall)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    TextButton(onClick = {
                        try {
                            WorkoutLifecycle.finish(session, store)
                            finishedId = session.id.toString()
                        } catch (_: WorkoutError.NothingCompleted) {
                            confirmDiscard = true
                        }
                    }) { Text(stringResource(R.string.finish_workout)) }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            engine.restTimer(session)?.takeIf { it.remaining(now) > 0 }?.let { timer ->
                item(key = "rest") {
                    RestCard(
                        remaining = timer.remaining(now).toInt(),
                        onAdjust = { delta -> engine.adjustRest(session, delta) },
                        onSkip = { engine.cancelRest(session) },
                    )
                }
            }
            items(engine.visibleExercises(session), key = { it.id.toString() }) { exercise ->
                ExerciseCard(
                    exercise = exercise,
                    unit = unit,
                    onChange = { engine.touch(session) },
                    onToggle = { set ->
                        if (set.isCompleted) {
                            engine.uncompleteSet(set)
                        } else {
                            try {
                                engine.completeSet(set, settings.restDefaults, isCompound)
                            } catch (_: WorkoutError.SetIncomplete) {
                                // Kvačica se ne stavlja dok serija nema sve vrijednosti.
                            }
                        }
                    },
                    onAddSet = { engine.addSet(exercise) },
                    onAddWarmUp = { engine.addSet(exercise, SetKind.WARM_UP) },
                    onDeleteSet = { set ->
                        val removed = engine.removeSet(set)
                        offerUndo(setDeleted) { engine.restoreSet(removed, exercise) }
                    },
                    onRemove = {
                        engine.removeExercise(exercise)
                        offerUndo(exerciseRemoved) { engine.restoreExercise(exercise) }
                    },
                    onPlates = { plateTarget = it },
                    onSuperset = { supersetSource = exercise.id.toString() },
                    onLeaveSuperset = { engine.removeFromSuperset(exercise) },
                )
            }
            item(key = "add") {
                Button(onClick = { picking = true }, modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text(stringResource(R.string.add_exercise), Modifier.padding(start = 8.dp))
                }
            }
        }
    }

    supersetSource?.let { id ->
        val visible = engine.visibleExercises(session)
        val source = visible.firstOrNull { it.id.toString() == id }
        if (source == null) {
            supersetSource = null
        } else {
            // Za partnera se nude samo vježbe koje još nisu u supersetu (kao na iOS-u).
            val candidates = visible.filter { it.id != source.id && it.supersetGroupId == null }
            SupersetPartnerDialog(
                candidates = candidates,
                onPick = { partner ->
                    supersetSource = null
                    engine.makeSuperset(engine.group(source) + partner, session)
                },
                onDismiss = { supersetSource = null },
            )
        }
    }

    plateTarget?.let { target ->
        PlateCalculatorDialog(target, unit, settings, onDismiss = { plateTarget = null })
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(R.string.discard_workout_title)) },
            text = { Text(stringResource(R.string.discard_workout_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDiscard = false
                    WorkoutLifecycle.discard(session, store)
                    onClose()
                }) { Text(stringResource(R.string.discard_workout)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDiscard = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun RestCard(remaining: Int, onAdjust: (Int) -> Unit, onSkip: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.rest), style = MaterialTheme.typography.labelLarge)
                Text(DurationInput.format(remaining), style = MaterialTheme.typography.headlineMedium)
            }
            TextButton(onClick = { onAdjust(-15) }) { Text("−15") }
            TextButton(onClick = { onAdjust(15) }) { Text("+15") }
            TextButton(onClick = onSkip) { Text(stringResource(R.string.skip_rest)) }
        }
    }
}

@Composable
private fun ExerciseCard(
    exercise: SessionExercise,
    unit: WeightUnit,
    onChange: () -> Unit,
    onToggle: (SetLog) -> Unit,
    onAddSet: () -> Unit,
    onAddWarmUp: () -> Unit,
    onDeleteSet: (SetLog) -> Unit,
    onRemove: () -> Unit,
    onPlates: (String) -> Unit,
    onSuperset: () -> Unit,
    onLeaveSuperset: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    if (exercise.supersetGroupId != null) {
                        Text(
                            stringResource(R.string.superset).uppercase(LocalConfiguration.current.locales[0]),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Text(exercise.exerciseName, style = MaterialTheme.typography.titleMedium)
                }
                Box {
                    IconButton(onClick = { menu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more_options))
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.add_warm_up)) },
                            onClick = {
                                menu = false
                                onAddWarmUp()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.superset)) },
                            onClick = {
                                menu = false
                                onSuperset()
                            },
                        )
                        if (exercise.supersetGroupId != null) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.leave_superset)) },
                                onClick = {
                                    menu = false
                                    onLeaveSuperset()
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.remove_exercise), color = MaterialTheme.colorScheme.error) },
                            onClick = {
                                menu = false
                                onRemove()
                            },
                        )
                    }
                }
            }
            var working = 0
            for (set in exercise.orderedSets) {
                val label = if (set.kind == SetKind.WARM_UP) stringResource(R.string.warm_up_short) else (++working).toString()
                SetRow(label, set, exercise.inputType, unit, onChange, onToggle, onDelete = { onDeleteSet(set) }, onPlates = onPlates)
            }
            TextButton(onClick = onAddSet) { Text(stringResource(R.string.add_set)) }
        }
    }
}

/** "Superset s": vježbe koje se mogu spojiti s odabranom, ili uputa kad ih nema. */
@Composable
private fun SupersetPartnerDialog(candidates: List<SessionExercise>, onPick: (SessionExercise) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.superset_with)) },
        text = {
            Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
                if (candidates.isEmpty()) {
                    Text(stringResource(R.string.superset_no_partner), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                candidates.forEach { candidate ->
                    ListItem(
                        modifier = Modifier.clickable { onPick(candidate) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(candidate.exerciseName) },
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** Polja serije prema vrsti unosa vježbe. Težina se upisuje u jedinici iz Postavki, a sprema u kg. */
@Composable
private fun SetRow(
    label: String,
    set: SetLog,
    inputType: ExerciseInputType,
    unit: WeightUnit,
    onChange: () -> Unit,
    onToggle: (SetLog) -> Unit,
    onDelete: () -> Unit,
    onPlates: (String) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(unit, locale) { WeightFormatter(unit, locale) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box {
            Text(label, Modifier.width(24.dp).clickable { menu = true }, style = MaterialTheme.typography.bodyLarge)
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                if (inputType == ExerciseInputType.WEIGHT_REPS) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.plate_calculator)) },
                        onClick = {
                            menu = false
                            onPlates(set.weightKg?.let(formatter::number) ?: "")
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.delete_set), color = MaterialTheme.colorScheme.error) },
                    onClick = {
                        menu = false
                        onDelete()
                    },
                )
            }
        }
        when (inputType) {
            ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> {
                val weight = if (inputType == ExerciseInputType.WEIGHT_REPS) set.weightKg else set.extraWeightKg
                NumberField(
                    key = "${set.id}-weight",
                    initial = weight?.let(formatter::number) ?: "",
                    label = unit.symbol,
                    decimal = true,
                    modifier = Modifier.weight(1f),
                ) { text ->
                    val kilograms = NumberInput.parse(text, locale)?.let { WeightConversion.kilograms(it, unit) }
                    if (inputType == ExerciseInputType.WEIGHT_REPS) set.weightKg = kilograms else set.extraWeightKg = kilograms
                    onChange()
                }
                RepsField(set, Modifier.weight(1f), onChange)
            }
            ExerciseInputType.BODYWEIGHT -> RepsField(set, Modifier.weight(1f), onChange)
            ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> {
                NumberField(
                    key = "${set.id}-duration",
                    initial = DurationInput.format(set.durationSeconds),
                    label = stringResource(R.string.duration_label),
                    decimal = false,
                    modifier = Modifier.weight(1f),
                ) { text ->
                    set.durationSeconds = DurationInput.parse(text)
                    onChange()
                }
                if (inputType == ExerciseInputType.DURATION_DISTANCE) {
                    NumberField(
                        key = "${set.id}-distance",
                        initial = set.distanceMeters?.let { NumberInput.format(it / 1000, locale) } ?: "",
                        label = "km",
                        decimal = true,
                        modifier = Modifier.weight(1f),
                    ) { text ->
                        set.distanceMeters = NumberInput.parse(text, locale)?.let { it * 1000 }
                        onChange()
                    }
                }
            }
        }
        FilledIconToggleButton(checked = set.isCompleted, onCheckedChange = { onToggle(set) }) {
            Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.complete_set))
        }
    }
}

@Composable
private fun RepsField(set: SetLog, modifier: Modifier, onChange: () -> Unit) {
    NumberField(
        key = "${set.id}-reps",
        initial = set.reps?.toString() ?: "",
        label = stringResource(R.string.reps_label),
        decimal = false,
        modifier = modifier,
    ) { text ->
        set.reps = text.trim().toIntOrNull()?.takeIf { it >= 0 }
        onChange()
    }
}

/** Tekst polja živi u ekranu, a vrijednost se pretvara i sprema pri svakoj izmjeni. */
@Composable
private fun NumberField(
    key: String,
    initial: String,
    label: String,
    decimal: Boolean,
    modifier: Modifier,
    onValue: (String) -> Unit,
) {
    var text by rememberSaveable(key) { mutableStateOf(initial) }
    OutlinedTextField(
        value = text,
        onValueChange = {
            text = it
            onValue(it)
        },
        modifier = modifier,
        label = { Text(label) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number),
    )
}

package com.brunodobric.gymapp.ui.history

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.text.format.DateFormat
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.ref
import com.brunodobric.gymapp.model.weightStep
import com.brunodobric.gymapp.training.SessionEditor
import com.brunodobric.gymapp.training.WorkoutError
import com.brunodobric.gymapp.ui.workout.ExerciseCardActions
import com.brunodobric.gymapp.ui.workout.ExercisePicker
import com.brunodobric.gymapp.ui.workout.PlateCalculatorDialog
import com.brunodobric.gymapp.ui.workout.SetSheet
import com.brunodobric.gymapp.ui.workout.WorkoutExerciseCard
import com.brunodobric.gymapp.ui.workout.inputTypeOf
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * Naknadno uređivanje odrađenog treninga (`SessionEditorScreen` na iOS-u): naziv, početak i kraj, bilješke,
 * vježbe i serije. Ništa se ne sprema usput: "Spremi" sprema ([SessionEditor.save]), a izlazak bez spremanja
 * vraća zadnje spremljeno stanje ([SessionEditor.cancel]). Serije bez kvačice i vježbe bez završene serije
 * se pri spremanju brišu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionEditorScreen(services: AppServices, sessionId: UUID, onClose: () -> Unit) {
    val store = services.store
    val editor = remember(store) { SessionEditor(store) }
    // Izmjene se ne spremaju, pa ih ekran broji sam da se iscrta i zna pitati pri izlasku.
    var changes by remember { mutableIntStateOf(0) }
    val session: Session? = remember(changes) { store.sessions.firstOrNull { it.id == sessionId } }
    var picking by rememberSaveable { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var nothingCompleted by remember { mutableStateOf(false) }
    var editingSetId by rememberSaveable { mutableStateOf<String?>(null) }
    var plateTarget by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]

    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val setIncomplete = stringResource(R.string.set_incomplete)

    fun changed() {
        changes++
    }

    /** Kvačica kao u treningu: nepotpuna serija se ne označava, a poruka kaže zašto. */
    fun toggle(set: SetLog) {
        try {
            editor.toggleCompleted(set)
            changed()
        } catch (_: WorkoutError.SetIncomplete) {
            snackbar.currentSnackbarData?.dismiss()
            scope.launch { snackbar.showSnackbar(setIncomplete) }
        }
    }

    fun leave() {
        if (changes > 0) confirmDiscard = true else onClose()
    }

    if (session == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }
    val settings = store.settings()
    val unit = settings.weightUnit

    if (picking) {
        BackHandler { picking = false }
        ExercisePicker(
            services = services,
            onPick = { summary ->
                editor.addExercise(summary.ref, inputTypeOf(services, summary), session)
                picking = false
                changed()
            },
            onClose = { picking = false },
        )
        return
    }
    BackHandler { leave() }

    val zone = ZoneId.systemDefault()
    val formatter = remember(locale) { DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale).withZone(zone) }

    /** Sustavski odabir datuma pa vremena; [onPick] dobiva novi trenutak. */
    fun pickDateTime(current: Instant, onPick: (Instant) -> Unit) {
        val start = current.atZone(zone)
        DatePickerDialog(context, { _, year, month, day ->
            TimePickerDialog(context, { _, hour, minute ->
                onPick(ZonedDateTime.of(year, month + 1, day, hour, minute, 0, 0, zone).toInstant())
            }, start.hour, start.minute, DateFormat.is24HourFormat(context)).show()
        }, start.year, start.monthValue - 1, start.dayOfMonth).show()
    }

    val exercises = session.orderedExercises.filter { !it.isRemoved }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.edit_workout)) },
                navigationIcon = {
                    IconButton(onClick = { leave() }) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel))
                    }
                },
                actions = {
                    TextButton(onClick = {
                        try {
                            editor.save(session)
                            onClose()
                        } catch (_: WorkoutError.NothingCompleted) {
                            nothingCompleted = true
                        }
                    }) { Text(stringResource(R.string.save)) }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(key = "info") {
                Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    var name by rememberSaveable(sessionId) { mutableStateOf(session.name) }
                    OutlinedTextField(
                        value = name,
                        onValueChange = {
                            name = it
                            session.name = it
                            changed()
                        },
                        label = { Text(stringResource(R.string.workout_name_field)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                    )
                    ListItem(
                        modifier = Modifier.clickable {
                            pickDateTime(session.startedAt) { picked ->
                                // Trening se pomiče cijeli: kraj zadržava trajanje.
                                val length = session.endedAt?.let { java.time.Duration.between(session.startedAt, it) }
                                session.startedAt = picked
                                length?.let { session.endedAt = picked.plus(it) }
                                changed()
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(stringResource(R.string.started_at)) },
                        trailingContent = { Text(formatter.format(session.startedAt), color = MaterialTheme.colorScheme.primary) },
                    )
                    session.endedAt?.let { end ->
                        ListItem(
                            modifier = Modifier.clickable {
                                pickDateTime(end) { picked ->
                                    session.endedAt = maxOf(picked, session.startedAt)
                                    changed()
                                }
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(stringResource(R.string.ended_at)) },
                            trailingContent = { Text(formatter.format(end), color = MaterialTheme.colorScheme.primary) },
                        )
                    }
                }
            }
            items(exercises, key = { it.id.toString() }) { exercise ->
                WorkoutExerciseCard(
                    exercise = exercise,
                    posterPath = null,
                    isOpen = true,
                    previousText = { null },
                    unit = unit,
                    effortScale = settings.effortScale,
                    tracksProgress = false,
                    actions = ExerciseCardActions(
                        onToggleOpen = {},
                        onChange = { changed() },
                        onToggle = { toggle(it) },
                        onEditSet = { editingSetId = it.id.toString() },
                        onChangeKind = { set, kind ->
                            set.kind = kind
                            changed()
                        },
                        onAddSet = { kind ->
                            editor.addSet(exercise, kind)
                            changed()
                        },
                        onDeleteSet = { set ->
                            editor.removeSet(set)
                            changed()
                        },
                        onRemove = {
                            editor.removeExercise(exercise)
                            changed()
                        },
                        onPlates = { plateTarget = it },
                        onSuperset = null,
                        onLeaveSuperset = null,
                        onShowInfo = null,
                    ),
                )
            }
            item(key = "add") {
                OutlinedButton(onClick = { picking = true }, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text(stringResource(R.string.add_exercise), Modifier.padding(start = 8.dp))
                }
                Text(
                    stringResource(R.string.editor_footer),
                    Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item(key = "notes") {
                var notes by rememberSaveable(sessionId) { mutableStateOf(session.notes) }
                OutlinedTextField(
                    value = notes,
                    onValueChange = {
                        notes = it
                        session.notes = it
                        changed()
                    },
                    label = { Text(stringResource(R.string.notes)) },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp),
                )
            }
        }
    }

    editingSetId?.let { id ->
        val exercise = exercises.firstOrNull { exercise -> exercise.orderedSets.any { it.id.toString() == id } }
        val set = exercise?.orderedSets?.firstOrNull { it.id.toString() == id }
        if (exercise == null || set == null) {
            editingSetId = null
        } else {
            val number = exercise.orderedSets.filter { it.kind == set.kind }.indexOfFirst { it.id == set.id } + 1
            SetSheet(
                title = if (set.kind == SetKind.WARM_UP) "${stringResource(R.string.kind_warm_up)} $number" else stringResource(R.string.set_number, number),
                exerciseName = exercise.exerciseName,
                set = set,
                inputType = exercise.inputType,
                unit = unit,
                weightStep = settings.weightStep(exercise.exercise, services.catalog, store.customExercises),
                effortScale = settings.effortScale,
                previousText = null,
                onSave = {
                    editingSetId = null
                    changed()
                },
                onConfirm = {
                    editingSetId = null
                    changed()
                    toggle(set)
                },
                onDismiss = { editingSetId = null },
            )
        }
    }

    plateTarget?.let { target -> PlateCalculatorDialog(target, unit, settings, onDismiss = { plateTarget = null }) }

    if (nothingCompleted) {
        AlertDialog(
            onDismissRequest = { nothingCompleted = false },
            title = { Text(stringResource(R.string.discard_workout_title)) },
            text = { Text(stringResource(R.string.nothing_completed_save)) },
            confirmButton = { TextButton(onClick = { nothingCompleted = false }) { Text(stringResource(R.string.keep_editing)) } },
        )
    }

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(R.string.discard_changes_title)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDiscard = false
                    editor.cancel()
                    onClose()
                }) { Text(stringResource(R.string.discard_changes), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text(stringResource(R.string.keep_editing)) } },
        )
    }
}

package com.brunodobric.gymapp.ui.workout

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.ref
import com.brunodobric.gymapp.model.weightStep
import com.brunodobric.gymapp.training.LiveSetEditor
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.WorkoutError
import com.brunodobric.gymapp.training.WorkoutFlow
import com.brunodobric.gymapp.training.previousSetValues
import com.brunodobric.gymapp.training.restDefaults
import com.brunodobric.gymapp.ui.exercises.ExerciseDetailScreen
import com.brunodobric.gymapp.ui.exercises.MoveKitAssets
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.rememberTicker
import com.brunodobric.gymapp.units.DurationInput
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * Trening u tijeku (`ActiveWorkoutScreen` na iOS-u, u novom dizajnu): traka s trajanjem i "Završi", napredak
 * serija, kartice vježbi s tablicom serija ([WorkoutExerciseCard]) i odmor u plutajućoj traci pri dnu.
 * Svaka izmjena odmah se sprema (`WorkoutEngine.touch`), pa prekinut trening ostaje sačuvan.
 * Težina i ponavljanja upisuju se kotačićem u donjem listu ([SetSheet]). Brisanje serije i vježbe može se
 * poništiti iz snackbara; izbornik vrha mijenja redoslijed, vraća uklonjene vježbe i odbacuje trening.
 * Kad su sve serije gotove, nudi se kraj treninga ili nova vježba.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkoutScreen(services: AppServices, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
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
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    var picking by rememberSaveable { mutableStateOf(false) }
    var reordering by rememberSaveable { mutableStateOf(false) }
    var confirmFinish by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var nothingCompleted by remember { mutableStateOf(false) }
    var finishPrompt by remember { mutableStateOf(false) }
    var showsRemoved by remember { mutableStateOf(false) }
    var plateTarget by rememberSaveable { mutableStateOf<String?>(null) }
    // Serija u donjem listu s kotačićem.
    var editingSetId by rememberSaveable { mutableStateOf<String?>(null) }
    // Vježba čija je stranica otvorena ("Prikaži vježbu"), po ključu `ExerciseRef.key`.
    var infoKey by rememberSaveable { mutableStateOf<String?>(null) }
    // Vježba za koju se bira partner u supersetu.
    var supersetSource by rememberSaveable { mutableStateOf<String?>(null) }
    // Otvorena vježba (kao `openExerciseID` na iOS-u): ostale su sklopljene, a superset se otvara u cjelini.
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    // Broj završenih serija pri zadnjem pogledu, da se nova serija (i iz obavijesti) prepozna.
    var seenCompleted by rememberSaveable { mutableStateOf<Int?>(null) }
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
    val setIncomplete = stringResource(R.string.set_incomplete)

    /** Poruka s "Poništi"; prethodna poruka se zamjenjuje. */
    fun offerUndo(message: String, undo: () -> Unit) {
        snackbar.currentSnackbarData?.dismiss()
        scope.launch {
            val result = snackbar.showSnackbar(message, actionLabel = undoLabel, duration = SnackbarDuration.Short)
            if (result == SnackbarResult.ActionPerformed) undo()
        }
    }

    fun finish() {
        try {
            WorkoutLifecycle.finish(session, store)
            finishedId = session.id.toString()
        } catch (_: WorkoutError.NothingCompleted) {
            nothingCompleted = true
        }
    }

    infoKey?.let { key ->
        val source = if (key.startsWith("u:")) {
            ExerciseSummary.Source.Custom(UUID.fromString(key.drop(2)))
        } else {
            ExerciseSummary.Source.Catalog(key.drop(2))
        }
        ExerciseDetailScreen(
            services = services,
            source = source,
            onClose = { infoKey = null },
            onEdit = {},
            onOpenSession = {},
            showsHistory = false,
        )
        return
    }

    BackHandler(enabled = picking) { picking = false }
    BackHandler(enabled = !picking && reordering) { reordering = false }
    BackHandler(enabled = !picking && !reordering, onBack = onClose)

    if (picking) {
        ExercisePicker(
            services = services,
            onPick = { summary ->
                val input = inputTypeOf(services, summary)
                openId = engine.addExercise(summary.ref, input, session).id.toString()
                picking = false
            },
            onClose = { picking = false },
        )
        return
    }

    val visible = engine.visibleExercises(session)
    val removed = engine.removedExercises(session)
    fun firstIncomplete(): SessionExercise? = visible.firstOrNull { exercise -> exercise.orderedSets.any { !it.isCompleted } }
    if (openId == null && seenCompleted == null) openId = (firstIncomplete() ?: visible.firstOrNull())?.id?.toString()
    fun isOpen(exercise: SessionExercise): Boolean {
        if (exercise.id.toString() == openId) return true
        val group = exercise.supersetGroupId ?: return false
        return visible.firstOrNull { it.id.toString() == openId }?.supersetGroupId == group
    }

    // Prošli put po vježbi (završene serije zadnjeg izvođenja), kao `previousSets` na iOS-u.
    val keys = visible.map { it.exerciseKey }
    val previousByKey = remember(revision, keys) { visible.associate { it.exerciseKey to store.previousSetValues(it.exercise) } }
    val posters = remember(keys) {
        val available = MoveKitAssets.available(context)
        visible.associate { exercise ->
            exercise.exerciseKey to exercise.exerciseCatalogId?.let(services.catalog::exercise)?.poster?.takeIf { it in available }
        }
    }

    // Nova završena serija: kad je otvorena vježba (ili superset) gotova, otvara se prva nezavršena vježba,
    // a kad je sve gotovo nudi se kraj treninga.
    val completedCount = visible.sumOf { exercise -> exercise.orderedSets.count { it.isCompleted } }
    val totalCount = visible.sumOf { it.orderedSets.size }
    LaunchedEffect(completedCount) {
        val seen = seenCompleted
        seenCompleted = completedCount
        if (seen == null || !WorkoutFlow.hasNewCompletion(completedCount, seen)) return@LaunchedEffect
        val open = visible.firstOrNull { it.id.toString() == openId }
            ?: visible.maxByOrNull { exercise -> exercise.orderedSets.mapNotNull { it.completedAt }.maxOrNull() ?: Instant.MIN }
            ?: return@LaunchedEffect
        val groupDone = engine.group(open).all { exercise -> exercise.orderedSets.all { it.isCompleted } }
        val flags = visible.map { exercise -> exercise.orderedSets.all { it.isCompleted } }
        when (val advance = WorkoutFlow.advance(groupDone, flags)) {
            is WorkoutFlow.Advance.Open -> openId = visible[advance.index].id.toString()
            WorkoutFlow.Advance.Finished -> finishPrompt = true
            WorkoutFlow.Advance.Stay -> Unit
        }
    }

    val isCompound: (String) -> Boolean? = { key ->
        if (key.startsWith("c:")) services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
    }

    fun toggle(set: SetLog) {
        if (set.isCompleted) {
            engine.uncompleteSet(set)
        } else {
            try {
                engine.completeSet(set, settings.restDefaults, isCompound)
            } catch (_: WorkoutError.SetIncomplete) {
                // Kvačica se ne stavlja dok serija nema sve vrijednosti: poruka kaže zašto.
                snackbar.currentSnackbarData?.dismiss()
                scope.launch { snackbar.showSnackbar(setIncomplete, duration = SnackbarDuration.Short) }
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(session.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        val seconds = Duration.between(session.startedAt, now).seconds.coerceAtLeast(0).toInt()
                        Text(
                            DurationInput.format(seconds),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { if (reordering) reordering = false else onClose() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    if (reordering) {
                        // Dok traje premještanje u kutu je samo kvačica koja ga završava, kao na iOS-u.
                        IconButton(onClick = { reordering = false }) {
                            Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.reorder_done))
                        }
                    } else {
                        Button(onClick = { confirmFinish = true }) { Text(stringResource(R.string.finish_workout)) }
                        WorkoutMenu(
                            removedCount = removed.size,
                            onReorder = { reordering = true },
                            onShowRemoved = { showsRemoved = true },
                            onDiscard = { confirmDiscard = true },
                        )
                    }
                },
            )
        },
        bottomBar = {
            engine.restTimer(session)?.takeIf { it.remaining(now) > 0 }?.let { timer ->
                RestBar(
                    remaining = timer.remaining(now),
                    total = timer.totalSeconds,
                    onAdjust = { delta -> engine.adjustRest(session, delta) },
                    onSkip = { engine.cancelRest(session) },
                )
            }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(key = "progress") {
                Column(Modifier.padding(horizontal = 16.dp).padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        stringResource(R.string.sets_progress, completedCount, totalCount),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    LinearProgressIndicator(
                        progress = { if (totalCount == 0) 0f else completedCount.toFloat() / totalCount },
                        modifier = Modifier.fillMaxWidth(),
                        strokeCap = StrokeCap.Round,
                    )
                }
            }
            if (reordering) {
                itemsIndexed(visible, key = { _, exercise -> exercise.id.toString() }) { index, exercise ->
                    ReorderRow(
                        name = exercise.exerciseName,
                        canMoveUp = index > 0,
                        canMoveDown = index < visible.lastIndex,
                        onMoveUp = { engine.moveExercises(session, listOf(index), index - 1) },
                        onMoveDown = { engine.moveExercises(session, listOf(index), index + 2) },
                    )
                }
            } else {
                items(visible, key = { it.id.toString() }) { exercise ->
                    val open = isOpen(exercise)
                    val previous = previousByKey[exercise.exerciseKey].orEmpty()
                    val key = exercise.exerciseKey
                    WorkoutExerciseCard(
                        exercise = exercise,
                        posterPath = posters[key],
                        isOpen = open,
                        previousText = { set -> LiveSetEditor.previousText(set, exercise.inputType, previous, unit, locale) },
                        unit = unit,
                        effortScale = settings.effortScale,
                        actions = ExerciseCardActions(
                            onToggleOpen = { openId = if (open) null else exercise.id.toString() },
                            onChange = { engine.touch(session) },
                            onToggle = { toggle(it) },
                            onEditSet = { editingSetId = it.id.toString() },
                            onChangeKind = { set, kind ->
                                set.kind = kind
                                engine.touch(session)
                            },
                            onAddSet = { kind -> engine.addSet(exercise, kind) },
                            onDeleteSet = { set ->
                                val removedSet = engine.removeSet(set)
                                offerUndo(setDeleted) { engine.restoreSet(removedSet, exercise) }
                            },
                            onRemove = {
                                engine.removeExercise(exercise)
                                if (openId == exercise.id.toString()) openId = firstIncomplete()?.id?.toString()
                                offerUndo(exerciseRemoved) { engine.restoreExercise(exercise) }
                            },
                            onPlates = { plateTarget = it },
                            onSuperset = { supersetSource = exercise.id.toString() },
                            onLeaveSuperset = { engine.removeFromSuperset(exercise) },
                            onShowInfo = if (key.startsWith("c:") || key.startsWith("u:")) ({ infoKey = key }) else null,
                        ),
                    )
                }
                item(key = "add") {
                    OutlinedButton(
                        onClick = { picking = true },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = null)
                        Text(stringResource(R.string.add_exercise), Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
    }

    editingSetId?.let { id ->
        val exercise = visible.firstOrNull { exercise -> exercise.orderedSets.any { it.id.toString() == id } }
        val set = exercise?.orderedSets?.firstOrNull { it.id.toString() == id }
        if (exercise == null || set == null) {
            editingSetId = null
        } else {
            val number = exercise.orderedSets.filter { it.kind == set.kind }.indexOfFirst { it.id == set.id } + 1
            val title = if (set.kind == SetKind.WARM_UP) {
                "${stringResource(R.string.kind_warm_up)} $number"
            } else {
                stringResource(R.string.set_number, number)
            }
            SetSheet(
                title = title,
                exerciseName = exercise.exerciseName,
                set = set,
                inputType = exercise.inputType,
                unit = unit,
                weightStep = settings.weightStep(exercise.exercise, services.catalog, store.customExercises),
                effortScale = settings.effortScale,
                previousText = LiveSetEditor.previousText(
                    set, exercise.inputType, previousByKey[exercise.exerciseKey].orEmpty(), unit, locale,
                ),
                onSave = {
                    editingSetId = null
                    engine.touch(session)
                },
                onConfirm = {
                    editingSetId = null
                    engine.touch(session)
                    toggle(set)
                },
                onDismiss = { editingSetId = null },
            )
        }
    }

    supersetSource?.let { id ->
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

    if (showsRemoved) {
        RemovedExercisesDialog(
            exercises = removed,
            onRestore = { exercise ->
                engine.restoreExercise(exercise)
                showsRemoved = false
            },
            onDismiss = { showsRemoved = false },
        )
    }

    if (finishPrompt) {
        AlertDialog(
            onDismissRequest = { finishPrompt = false },
            title = { Text(stringResource(R.string.all_sets_done_title)) },
            text = {
                Column {
                    TextButton(
                        onClick = {
                            finishPrompt = false
                            finish()
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(stringResource(R.string.finish_workout_full)) }
                    TextButton(
                        onClick = {
                            finishPrompt = false
                            picking = true
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(stringResource(R.string.add_exercise)) }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { finishPrompt = false }) { Text(stringResource(R.string.continue_workout)) } },
        )
    }

    if (confirmFinish) {
        AlertDialog(
            onDismissRequest = { confirmFinish = false },
            title = { Text(stringResource(R.string.finish_confirm_title)) },
            text = { Text(stringResource(R.string.finish_confirm_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmFinish = false
                    finish()
                }) { Text(stringResource(R.string.finish_workout_full)) }
            },
            dismissButton = { TextButton(onClick = { confirmFinish = false }) { Text(stringResource(R.string.continue_workout)) } },
        )
    }

    if (confirmDiscard || nothingCompleted) {
        AlertDialog(
            onDismissRequest = {
                confirmDiscard = false
                nothingCompleted = false
            },
            title = { Text(stringResource(if (nothingCompleted) R.string.discard_workout_title else R.string.discard_confirm_title)) },
            text = { Text(stringResource(if (nothingCompleted) R.string.discard_workout_message else R.string.discard_confirm_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDiscard = false
                    nothingCompleted = false
                    WorkoutLifecycle.discard(session, store)
                    onClose()
                }) { Text(stringResource(R.string.discard_workout), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = {
                    confirmDiscard = false
                    nothingCompleted = false
                }) { Text(stringResource(R.string.continue_workout)) }
            },
        )
    }
}

/** Izbornik vrha ekrana: redoslijed, uklonjene vježbe i odbacivanje treninga. */
@Composable
private fun WorkoutMenu(removedCount: Int, onReorder: () -> Unit, onShowRemoved: () -> Unit, onDiscard: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { menu = true }) {
            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more_options))
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.reorder_exercises)) }, onClick = {
                menu = false
                onReorder()
            })
            DropdownMenuItem(
                text = { Text(stringResource(R.string.removed_exercises_count, removedCount)) },
                enabled = removedCount > 0,
                onClick = {
                    menu = false
                    onShowRemoved()
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.discard_workout), color = MaterialTheme.colorScheme.error) },
                onClick = {
                    menu = false
                    onDiscard()
                },
            )
        }
    }
}

/** Redak vježbe dok se mijenja redoslijed: naziv i strelice gore i dolje. */
@Composable
private fun ReorderRow(name: String, canMoveUp: Boolean, canMoveDown: Boolean, onMoveUp: () -> Unit, onMoveDown: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(name, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            IconButton(onClick = onMoveUp, enabled = canMoveUp) {
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = stringResource(R.string.move_up))
            }
            IconButton(onClick = onMoveDown, enabled = canMoveDown) {
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = stringResource(R.string.move_down))
            }
        }
    }
}

/** Odmor u tamnoj plutajućoj traci: prsten s preostalim vremenom, −15, +15 i preskakanje. */
@Composable
private fun RestBar(remaining: Double, total: Double, onAdjust: (Int) -> Unit, onSkip: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.inverseSurface,
        contentColor = MaterialTheme.colorScheme.inverseOnSurface,
        shadowElevation = 6.dp,
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(
                progress = { if (total <= 0) 0f else (remaining / total).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.size(40.dp),
                color = MaterialTheme.colorScheme.inversePrimary,
                trackColor = MaterialTheme.colorScheme.inverseOnSurface.copy(alpha = 0.2f),
                strokeWidth = 4.dp,
                strokeCap = StrokeCap.Round,
            )
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(
                    stringResource(R.string.rest),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.inverseOnSurface.copy(alpha = 0.7f),
                )
                Text(DurationInput.format(remaining.toInt()), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
            }
            val buttonColor = MaterialTheme.colorScheme.inverseOnSurface
            TextButton(onClick = { onAdjust(-15) }) { Text("−15", color = buttonColor) }
            TextButton(onClick = { onAdjust(15) }) { Text("+15", color = buttonColor) }
            TextButton(onClick = onSkip) { Text(stringResource(R.string.skip_rest), color = MaterialTheme.colorScheme.inversePrimary) }
        }
    }
}

/** Uklonjene vježbe s brojem završenih serija i "Vrati". */
@Composable
private fun RemovedExercisesDialog(exercises: List<SessionExercise>, onRestore: (SessionExercise) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.removed_exercises)) },
        text = {
            Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
                exercises.forEach { exercise ->
                    ListItem(
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(exercise.exerciseName) },
                        supportingContent = {
                            Text(stringResource(R.string.completed_sets_count, exercise.orderedSets.count { it.isCompleted }))
                        },
                        trailingContent = { TextButton(onClick = { onRestore(exercise) }) { Text(stringResource(R.string.restore)) } },
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
    )
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


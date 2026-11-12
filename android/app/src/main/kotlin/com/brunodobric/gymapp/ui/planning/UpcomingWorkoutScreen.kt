package com.brunodobric.gymapp.ui.planning

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.CycleOverride
import com.brunodobric.gymapp.model.CycleOverrideKind
import com.brunodobric.gymapp.model.ref
import com.brunodobric.gymapp.planning.PlannedExercise
import com.brunodobric.gymapp.planning.PlannedWorkout
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateStarter
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.settings.Footer
import com.brunodobric.gymapp.ui.settings.SectionHeader
import com.brunodobric.gymapp.ui.workout.ExercisePicker
import com.brunodobric.gymapp.ui.workout.inputTypeOf
import java.util.UUID

/**
 * Sljedeći trening rasporeda s privremenim izmjenama samo za ovaj ciklus (`UpcomingWorkoutScreen` na iOS-u):
 * preskoči trening, izbaci vježbu ili zamijeni vježbu. Izmjene se mogu poništiti dok trening nije završen.
 * Ovaj zaslon otvara dodir na podsjetnik rasporeda.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpcomingWorkoutScreen(services: AppServices, scheduleId: UUID, onClose: () -> Unit, onStarted: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val engine = remember(store) { ScheduleEngine(store) }
    val schedule = remember(revision, scheduleId) { store.schedules.firstOrNull { it.id == scheduleId } }
    val planned = remember(revision, schedule) { schedule?.let(engine::nextWorkout) }
    // Izvor (stavka predloška) vježbe koja se mijenja; null kad se ne bira zamjena.
    var replacing by rememberSaveable { mutableStateOf<String?>(null) }

    BackHandler(enabled = replacing == null) { onClose() }
    BackHandler(enabled = replacing != null) { replacing = null }

    replacing?.let { source ->
        ExercisePicker(
            services = services,
            title = stringResource(R.string.replace_exercise),
            onPick = { summary ->
                val current = schedule?.let(engine::nextWorkout)
                val original = current?.template?.orderedExercises?.firstOrNull { it.id.toString() == source }
                if (current != null && original != null) {
                    engine.replaceExercise(original, summary.ref, inputTypeOf(services, summary), current)
                }
                replacing = null
            },
            onClose = { replacing = null },
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.upcoming_workout)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                    }
                },
            )
        },
    ) { padding ->
        if (planned == null) {
            Box(Modifier.padding(padding).fillMaxSize().padding(16.dp)) {
                Text(stringResource(R.string.no_next_workout), style = MaterialTheme.typography.titleMedium)
            }
            return@Scaffold
        }
        val changes = remember(revision, planned) {
            engine.overrides(planned.schedule, planned.cycle).filter {
                it.scheduleItemId == planned.item.id &&
                    (it.kind == CycleOverrideKind.REMOVE_EXERCISE || it.kind == CycleOverrideKind.REPLACE_EXERCISE)
            }
        }
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            item {
                ListItem(
                    headlineContent = { Text(planned.template.name, style = MaterialTheme.typography.titleLarge) },
                    supportingContent = { Text(stringResource(R.string.schedule_cycle, planned.schedule.name, planned.cycle)) },
                )
                Button(
                    onClick = {
                        TemplateStarter(store).start(planned)
                        onStarted()
                    },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                ) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Text(stringResource(R.string.start_workout), Modifier.padding(start = 8.dp))
                }
            }
            item { SectionHeader(stringResource(R.string.tab_exercises)) }
            items(planned.exercises, key = { it.source }) { exercise ->
                PlannedExerciseRow(
                    exercise = exercise,
                    onRemove = {
                        planned.template.orderedExercises.firstOrNull { it.id == exercise.source }
                            ?.let { engine.removeExercise(it, planned) }
                    },
                    onReplace = { replacing = exercise.source.toString() },
                )
                HorizontalDivider()
            }
            if (changes.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.cycle_changes)) }
                items(changes, key = { it.id }) { change ->
                    ListItem(
                        headlineContent = { Text(changeLabel(change, planned)) },
                        trailingContent = {
                            TextButton(onClick = { engine.undo(change) }) { Text(stringResource(R.string.undo)) }
                        },
                    )
                }
                item { Footer(stringResource(R.string.cycle_changes_footer)) }
            }
            item {
                OutlinedButton(
                    onClick = { engine.skipNextWorkout(planned.schedule) },
                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 24.dp),
                ) { Text(stringResource(R.string.skip_this_workout)) }
                Footer(stringResource(R.string.skip_this_workout_footer))
            }
        }
    }
}

/** Vježba sljedećeg treninga s izbornikom Izbaci i Zamijeni (na iOS-u su to radnje povlačenjem). */
@Composable
private fun PlannedExerciseRow(exercise: PlannedExercise, onRemove: () -> Unit, onReplace: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(exercise.ref.name) },
        supportingContent = if (exercise.isReplacement) {
            { Text(stringResource(R.string.replaced_this_cycle), color = MaterialTheme.colorScheme.tertiary) }
        } else {
            null
        },
        trailingContent = {
            Box {
                IconButton(onClick = { menu = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.exercise_options))
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.replace)) },
                        onClick = {
                            menu = false
                            onReplace()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.drop_exercise), color = MaterialTheme.colorScheme.error) },
                        onClick = {
                            menu = false
                            onRemove()
                        },
                    )
                }
            }
        },
    )
}

@Composable
private fun changeLabel(change: CycleOverride, planned: PlannedWorkout): String {
    val original = planned.template.orderedExercises.firstOrNull { it.exercise.key == change.targetExerciseKey }?.exerciseName ?: ""
    return when (change.kind) {
        CycleOverrideKind.REMOVE_EXERCISE -> stringResource(R.string.removed_exercise, original)
        CycleOverrideKind.REPLACE_EXERCISE -> stringResource(R.string.replaced_exercise, original, change.replacementName ?: "")
        else -> ""
    }
}



package com.brunodobric.gymapp.ui.planning

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.ref
import com.brunodobric.gymapp.planning.TemplateEngine
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.workout.ExercisePicker
import com.brunodobric.gymapp.ui.workout.inputTypeOf
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightConversion
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.units.WeightUnit
import java.util.UUID

/**
 * Uređivač spremljenog treninga: naziv, vježbe s redoslijedom, serije s ciljanom težinom i ponavljanjima te
 * odmor po vježbi. Promjene se spremaju odmah. Superserije, rasponi ponavljanja i tijek
 * "Spremi / Izađi bez spremanja" s iOS-a dolaze kasnije.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TemplateEditorScreen(services: AppServices, templateId: UUID, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val template = remember(revision, templateId) { store.template(templateId) }
    val engine = remember(store) { TemplateEngine(store) }
    var picking by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var name by rememberSaveable(templateId) { mutableStateOf(template?.name ?: "") }
    val unit = store.settings().weightUnit

    if (template == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }

    fun close() {
        val trimmed = name.trim()
        if (trimmed.isNotEmpty() && trimmed != template.name) {
            template.name = trimmed
            store.save()
        }
        onClose()
    }

    BackHandler(enabled = picking) { picking = false }
    BackHandler(enabled = !picking) { close() }

    if (picking) {
        ExercisePicker(
            services = services,
            onPick = { summary ->
                val input = inputTypeOf(services, summary)
                engine.addExercise(summary.ref, input, template)
                picking = false
            },
            onClose = { picking = false },
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(name.ifBlank { template.name }) },
                navigationIcon = {
                    IconButton(onClick = { close() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    IconButton(onClick = { confirmDelete = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete_template))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.template_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            val exercises = template.orderedExercises
            exercises.forEachIndexed { index, exercise ->
                ExerciseCard(
                    exercise = exercise,
                    unit = unit,
                    canMoveUp = index > 0,
                    canMoveDown = index < exercises.lastIndex,
                    onMove = { delta -> engine.moveExercises(template, listOf(index), if (delta < 0) index - 1 else index + 2) },
                    onRemove = { engine.removeExercise(exercise) },
                    onAddSet = { engine.addSet(exercise) },
                    onRemoveSet = { exercise.orderedSets.lastOrNull()?.let(engine::removeSet) },
                    onRest = { engine.setRest(it, exercise) },
                    onTargets = { set, kilograms, reps -> engine.setTargets(set, kilograms, reps) },
                )
            }
            OutlinedButton(onClick = { picking = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Text(stringResource(R.string.add_exercise), modifier = Modifier.padding(start = 8.dp))
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_template_title)) },
            text = { Text(stringResource(R.string.delete_template_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    engine.delete(template)
                    onClose()
                }) { Text(stringResource(R.string.delete_template), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun ExerciseCard(
    exercise: TemplateExercise,
    unit: WeightUnit,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMove: (Int) -> Unit,
    onRemove: () -> Unit,
    onAddSet: () -> Unit,
    onRemoveSet: () -> Unit,
    onRest: (Int?) -> Unit,
    onTargets: (TemplateSet, Double?, Int?) -> Unit,
) {
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(unit, locale) { WeightFormatter(unit, locale) }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(exercise.exerciseName, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton(enabled = canMoveUp, onClick = { onMove(-1) }) {
                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = stringResource(R.string.move_up))
                }
                IconButton(enabled = canMoveDown, onClick = { onMove(1) }) {
                    Icon(Icons.Filled.KeyboardArrowDown, contentDescription = stringResource(R.string.move_down))
                }
                IconButton(onClick = onRemove) {
                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove_exercise))
                }
            }
            val hasWeight = exercise.inputType in setOf(
                ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED,
            )
            val hasReps = hasWeight || exercise.inputType == ExerciseInputType.BODYWEIGHT
            var working = 0
            exercise.orderedSets.forEach { set ->
                val label = if (set.kind == SetKind.WARM_UP) stringResource(R.string.warm_up_short) else (++working).toString()
                Row(Modifier.padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(label, Modifier.width(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (hasWeight) {
                        TargetField(
                            key = "${set.id}-weight",
                            initial = set.targetWeightKg?.let(formatter::number) ?: "",
                            label = unit.symbol,
                            decimal = true,
                            modifier = Modifier.weight(1f),
                        ) { text ->
                            val kilograms = NumberInput.parse(text, locale)?.let { WeightConversion.kilograms(it, unit) }
                            onTargets(set, kilograms, set.targetReps)
                        }
                    }
                    if (hasReps) {
                        TargetField(
                            key = "${set.id}-reps",
                            initial = set.targetReps?.toString() ?: "",
                            label = stringResource(R.string.reps_label),
                            decimal = false,
                            modifier = Modifier.weight(1f),
                        ) { text ->
                            onTargets(set, set.targetWeightKg, text.trim().toIntOrNull()?.takeIf { it > 0 })
                        }
                    }
                    if (!hasReps) Text(stringResource(R.string.set_without_targets), Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = exercise.sets.size > 1, onClick = onRemoveSet) { Text("− " + stringResource(R.string.set_short)) }
                TextButton(onClick = onAddSet) { Text("+ " + stringResource(R.string.set_short)) }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.rest), Modifier.weight(1f))
                val rest = exercise.restSeconds
                TextButton(enabled = rest != null, onClick = {
                    onRest(rest?.let { if (it <= 15) null else it - 15 })
                }) { Text("−") }
                Text(rest?.let { DurationInput.format(it) } ?: stringResource(R.string.rest_default))
                TextButton(enabled = (rest ?: 0) < 600, onClick = { onRest((rest ?: 75) + 15) }) { Text("+") }
            }
        }
    }
}

/** Tekst polja živi u ekranu, a cilj se pretvara i sprema pri svakoj izmjeni. */
@Composable
private fun TargetField(key: String, initial: String, label: String, decimal: Boolean, modifier: Modifier, onValue: (String) -> Unit) {
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

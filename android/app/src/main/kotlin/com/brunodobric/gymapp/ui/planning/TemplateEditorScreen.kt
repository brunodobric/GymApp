package com.brunodobric.gymapp.ui.planning

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.model.ref
import com.brunodobric.gymapp.planning.TemplateEngine
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.workout.ExercisePicker
import java.util.UUID

/**
 * Uređivač spremljenog treninga, prvi korak: naziv, vježbe i broj serija. Promjene se spremaju odmah.
 * Ciljevi serija, odmor, superserije, redoslijed i tijek "Spremi / Izađi bez spremanja" s iOS-a dolaze kasnije.
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
                val input = (summary.source as? ExerciseSummary.Source.Catalog)
                    ?.let { services.catalog.exercise(it.id)?.inputType } ?: ExerciseInputType.WEIGHT_REPS
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
            template.orderedExercises.forEach { exercise ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(exercise.exerciseName, style = MaterialTheme.typography.titleMedium)
                            val sets = exercise.sets.size
                            Text(
                                pluralStringResource(R.plurals.set_count, sets, sets),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        TextButton(
                            enabled = exercise.sets.size > 1,
                            onClick = { exercise.orderedSets.lastOrNull()?.let(engine::removeSet) },
                        ) { Text("−") }
                        TextButton(onClick = { engine.addSet(exercise) }) { Text("+") }
                        IconButton(onClick = { engine.removeExercise(exercise) }) {
                            Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove_exercise))
                        }
                    }
                }
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

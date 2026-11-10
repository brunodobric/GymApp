package com.brunodobric.gymapp.ui.planning

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.planning.Program
import com.brunodobric.gymapp.planning.ProgramInstaller
import com.brunodobric.gymapp.planning.ProgramLibrary
import com.brunodobric.gymapp.planning.ProgramWorkout
import com.brunodobric.gymapp.planning.TrainingProfile
import com.brunodobric.gymapp.ui.catalogLanguage

/** Gotovi programi: jedan dodir stvara treninge i raspored (`ProgramsScreen` na iOS-u). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProgramsScreen(services: AppServices, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val store = services.store
    val context = LocalContext.current
    val language = catalogLanguage()
    var added by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }

    fun install(program: Program) {
        try {
            // Ponavljanja prema cilju i iskustvu, vježbe prema opremi iz profila.
            val profile = TrainingProfile.from(store.settings())
            val schedule = ProgramInstaller(store).install(
                program,
                profile,
                name = context.getString(programTitle(program)),
                workoutName = { workout -> workoutTitle(workout)?.let(context::getString) ?: workout.name },
            ) { id -> services.catalog.exercise(id)?.displayName(language) ?: id }
            added = schedule.name
        } catch (_: Exception) {
            failed = true
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.programs)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(ProgramLibrary.all, key = { it.id }) { program ->
                Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(programTitle(program)), style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(programDetails(program)),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedButton(onClick = { install(program) }) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Text(stringResource(R.string.add_program), Modifier.padding(start = 8.dp))
                        }
                    }
                }
            }
        }
    }

    added?.let { name ->
        AlertDialog(
            onDismissRequest = { added = null },
            title = { Text(stringResource(R.string.program_added)) },
            text = { Text(stringResource(R.string.program_added_message, name)) },
            confirmButton = {
                TextButton(onClick = {
                    added = null
                    onClose()
                }) { Text(stringResource(R.string.ok)) }
            },
        )
    }
    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            text = { Text(stringResource(R.string.program_failed)) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** Nazivi programa na jeziku sučelja (u modulu planning su hrvatski, kao u GymKitu). */
@StringRes
private fun programTitle(program: Program): Int = when (program.id) {
    "basic-full-body-2" -> R.string.program_basic_full_body_2
    "beginner-full-body-3" -> R.string.program_beginner_full_body_3
    "full-body-3" -> R.string.program_full_body_3
    "upper-lower-4" -> R.string.program_upper_lower_4
    "upper-lower-ppl-5" -> R.string.program_upper_lower_ppl_5
    else -> R.string.program_ppl_6
}

@StringRes
private fun programDetails(program: Program): Int = when (program.id) {
    "basic-full-body-2" -> R.string.program_basic_full_body_2_details
    "beginner-full-body-3" -> R.string.program_beginner_full_body_3_details
    "full-body-3" -> R.string.program_full_body_3_details
    "upper-lower-4" -> R.string.program_upper_lower_4_details
    "upper-lower-ppl-5" -> R.string.program_upper_lower_ppl_5_details
    else -> R.string.program_ppl_6_details
}

@StringRes
private fun workoutTitle(workout: ProgramWorkout): Int? = when (workout.key) {
    "basicA", "beginnerA", "fullA" -> R.string.program_workout_full_a
    "basicB", "beginnerB", "fullB" -> R.string.program_workout_full_b
    "fullC" -> R.string.program_workout_full_c
    "upperA" -> R.string.program_workout_upper_a
    "upperB" -> R.string.program_workout_upper_b
    "lowerA" -> R.string.program_workout_lower_a
    "lowerB" -> R.string.program_workout_lower_b
    "legsA" -> R.string.program_workout_legs_a
    "legsB" -> R.string.program_workout_legs_b
    else -> null // Push A/B i Pull A/B su isti na oba jezika.
}

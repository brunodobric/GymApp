package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateStarter
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.rememberTicker
import com.brunodobric.gymapp.units.DurationInput
import java.time.Duration

/** Početna, prvi korak: nastavak treninga u tijeku ili kartica za početak treninga. Ostale kartice dolaze kasnije. */
@Composable
fun HomeScreen(services: AppServices, onOpenWorkout: () -> Unit, onOpenSettings: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val active = store.activeSession()
    val emptyName = stringResource(R.string.workout_default_name)
    val locale = LocalConfiguration.current.locales[0]
    val upcoming = remember(revision) { ScheduleEngine(store).upcomingWorkouts() }
    val startable = remember(revision, locale) { TemplateStarter.startable(store.templates, locale) }
    var showsPicker by remember { mutableStateOf(false) }
    // Aktivni rasporedi čiji su treninzi u izboru (prazno: izbor bez rasporeda).
    var pickerSchedules by remember { mutableStateOf<List<Schedule>>(emptyList()) }

    fun start(begin: () -> Unit) {
        showsPicker = false
        begin()
        onOpenWorkout()
    }

    if (showsPicker) {
        val schedules = pickerSchedules
        val groups = remember(revision, schedules) {
            val engine = ScheduleEngine(store)
            schedules.distinctBy { it.id }.map { schedule ->
                ScheduleChoices(
                    schedule = schedule,
                    workouts = engine.workoutChoices(schedule),
                    nextItemId = upcoming.firstOrNull { it.schedule.id == schedule.id }?.item?.id,
                )
            }.filter { it.workouts.isNotEmpty() }
        }
        TemplatePickerDialog(
            groups = groups,
            templates = startable,
            onPlanned = { planned -> start { TemplateStarter(store).start(planned) } },
            onTemplate = { template -> start { TemplateStarter(store).start(template) } },
            onDismiss = { showsPicker = false },
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Postavke su na Početnoj, kao na iOS-u (gumb u alatnoj traci).
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_home), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = onOpenSettings) {
                Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.settings))
            }
        }
        if (active != null) {
            val now = rememberTicker()
            Card(onClick = onOpenWorkout, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.workout_in_progress), style = MaterialTheme.typography.labelLarge)
                    Text(active.name, style = MaterialTheme.typography.titleLarge)
                    val seconds = Duration.between(active.startedAt, now).seconds.coerceAtLeast(0).toInt()
                    Text(DurationInput.format(seconds), style = MaterialTheme.typography.bodyMedium)
                }
            }
        } else {
            StartWorkoutCard(
                planned = upcoming,
                templateCount = startable.size,
                offersOtherWorkout = upcoming.map { it.template.id }.toSet().let { next -> startable.any { it.id !in next } },
                onStart = { planned -> start { TemplateStarter(store).start(planned) } },
                onChooseTemplate = { schedules ->
                    pickerSchedules = schedules
                    showsPicker = true
                },
                onStartEmpty = { start { WorkoutEngine(store).startSession(emptyName) } },
            )
        }
    }
}

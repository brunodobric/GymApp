package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.rememberTicker
import com.brunodobric.gymapp.units.DurationInput
import java.time.Duration

/** Početna, prvi korak: nastavak treninga u tijeku ili početak praznog treninga. Kartice dolaze kasnije. */
@Composable
fun HomeScreen(services: AppServices, onOpenWorkout: () -> Unit, onOpenSettings: () -> Unit) {
    val store = services.store
    rememberStoreRevision(store)
    val active = store.activeSession()
    val emptyName = stringResource(R.string.workout_default_name)

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
            Button(
                onClick = {
                    WorkoutEngine(store).startSession(emptyName)
                    onOpenWorkout()
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.start_empty_workout))
            }
        }
    }
}

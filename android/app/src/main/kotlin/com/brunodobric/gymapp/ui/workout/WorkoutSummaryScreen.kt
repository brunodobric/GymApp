package com.brunodobric.gymapp.ui.workout

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.comparison
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecord
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.ui.statistics.prKindTitle
import com.brunodobric.gymapp.ui.statistics.recordValue
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.WeightFormatter
import java.text.NumberFormat
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Sažetak nakon završetka treninga, prvi korak: trajanje, volumen, tvrde serije, usporedba s prošlim
 * izvođenjem, najviše tri istaknuta rekorda (ostali na dodir) i bilješka koja se sprema pri zatvaranju.
 * Rezultat po vježbi, mišići, napor treninga i kardio dio s iOS-a dolaze kasnije.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkoutSummaryScreen(services: AppServices, sessionId: UUID, onClose: () -> Unit) {
    val store = services.store
    val session = remember(sessionId) { store.sessions.firstOrNull { it.id == sessionId } }
    if (session == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }
    val settings = store.settings()
    val locale = LocalConfiguration.current.locales[0]
    val weight = remember(settings.weightUnit, locale) { WeightFormatter(settings.weightUnit, locale) }
    val summary = remember(sessionId) {
        val provider = ExerciseInfoBuilder.provider(services.catalog, store.customExercises)
        WorkoutEngine(store).summary(
            session,
            trackedKinds = PRKind.tracked(settings),
            excludedExercises = settings.prExcludedExerciseKeys,
            isCompound = { key ->
                if (key.startsWith("c:")) services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
            },
            isCardio = ExerciseInfoBuilder.isCardio(provider),
        )
    }
    val comparison = remember(sessionId) { StatisticsEngine(store).comparison(session) }
    var notes by rememberSaveable(sessionId) { mutableStateOf(session.notes) }
    var showsOther by rememberSaveable { mutableStateOf(false) }

    fun close() {
        val trimmed = notes.trim()
        if (trimmed != session.notes) {
            session.notes = trimmed
            store.save()
        }
        onClose()
    }
    BackHandler { close() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.summary)) },
                actions = { TextButton(onClick = { close() }) { Text(stringResource(R.string.close)) } },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Card(Modifier.fillMaxWidth()) {
                SummaryRow(stringResource(R.string.duration), DurationInput.format(summary.durationSeconds.toInt()))
                if (summary.totalVolumeKg > 0) SummaryRow(stringResource(R.string.volume), weight.string(summary.totalVolumeKg))
                if (summary.hardSets > 0) SummaryRow(stringResource(R.string.hard_sets), summary.hardSets.toString())
            }

            comparison?.volumeChange?.let { change ->
                Card(Modifier.fillMaxWidth()) {
                    Text(
                        stringResource(R.string.volume_vs_previous, signed(change, locale)),
                        modifier = Modifier.padding(16.dp),
                    )
                }
            }

            if (summary.records.isNotEmpty() || summary.hardSets > 0) {
                Text(stringResource(R.string.personal_records), style = MaterialTheme.typography.titleMedium)
                Card(Modifier.fillMaxWidth()) {
                    if (summary.records.isEmpty()) {
                        Text(
                            stringResource(R.string.no_new_records),
                            modifier = Modifier.padding(16.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    summary.highlights.forEach { RecordItem(it.exerciseName, it.record, weight) }
                    if (summary.otherRecordsCount > 0) {
                        HorizontalDivider()
                        if (showsOther) {
                            val shown = summary.highlights.map { it.exerciseKey to it.record.kind }.toSet()
                            summary.records.forEach { item ->
                                item.records
                                    .filter { (item.exerciseKey to it.kind) !in shown }
                                    .forEach { RecordItem(item.exerciseName, it, weight) }
                            }
                        } else {
                            TextButton(onClick = { showsOther = true }, modifier = Modifier.padding(horizontal = 8.dp)) {
                                Text(stringResource(R.string.other_records, summary.otherRecordsCount))
                            }
                        }
                    }
                }
            }

            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(stringResource(R.string.note)) },
                placeholder = { Text(stringResource(R.string.note_hint)) },
                minLines = 2,
                maxLines = 6,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun SummaryRow(title: String, value: String) {
    ListItem(
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = { Text(title) },
        trailingContent = { Text(value, style = MaterialTheme.typography.titleSmall) },
    )
}

@Composable
private fun RecordItem(exerciseName: String, record: PersonalRecord, weight: WeightFormatter) {
    val reps = record.reps
    val title = if (record.kind == PRKind.REP_MAX && reps != null) {
        stringResource(R.string.pr_rep_max_reps, reps)
    } else {
        stringResource(prKindTitle(record.kind))
    }
    ListItem(
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = { Text(exerciseName) },
        supportingContent = { Text(title) },
        trailingContent = { Text(recordValue(record, weight), style = MaterialTheme.typography.titleSmall) },
    )
}

/** Promjena kao postotak s predznakom, u zapisu jezika. */
private fun signed(change: Double, locale: java.util.Locale): String {
    val rounded = (change * 100).roundToInt() / 100.0
    val text = NumberFormat.getPercentInstance(locale).format(rounded)
    return if (rounded > 0) "+$text" else text
}

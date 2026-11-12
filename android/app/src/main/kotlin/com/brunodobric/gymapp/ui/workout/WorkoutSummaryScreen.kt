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
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.ui.statistics.SessionMusclesCard
import com.brunodobric.gymapp.ui.settings.ChoiceRow
import com.brunodobric.gymapp.ui.exercises.setValuesText
import com.brunodobric.gymapp.training.CardioText
import com.brunodobric.gymapp.stats.exerciseResults
import com.brunodobric.gymapp.stats.ExerciseResult
import com.brunodobric.gymapp.stats.BucketSize
import com.brunodobric.gymapp.model.StatsDetail
import com.brunodobric.gymapp.catalog.ExerciseInputType
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
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
import com.brunodobric.gymapp.ui.statistics.signedPercent
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Sažetak nakon završetka treninga (`WorkoutSummarySheet` na iOS-u): trajanje, volumen, tvrde serije, kardio
 * (vrijeme, udaljenost, tempo, brzina), usporedba s prošlim izvođenjem, najviše tri istaknuta rekorda (ostali na
 * dodir), rezultat po vježbi, mišići i bilješka. U detaljnom prikazu statistike još odmor između serija i napor
 * treninga. Bilješka, puls i napor spremaju se pri zatvaranju.
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
    var heartRateText by rememberSaveable(sessionId) { mutableStateOf(NumberInput.format(session.averageHeartRate)) }
    var sessionRPE by rememberSaveable(sessionId) { mutableStateOf(session.sessionRPE) }
    var showsOther by rememberSaveable { mutableStateOf(false) }
    val isPro = settings.statsDetail == StatsDetail.PRO
    val results = remember(sessionId) { StatisticsEngine(store).exerciseResults(session) }
    val weekSets = remember(sessionId) {
        val info = ExerciseInfoBuilder.provider(services.catalog, store.customExercises)
        StatisticsEngine(store).volumeBuckets(BucketSize.WEEK, 1, now = session.startedAt, info = info)
            .lastOrNull()?.loads?.mapValues { it.value.sets }.orEmpty()
    }
    val hasCardio = summary.cardio != null || session.orderedExercises.any {
        it.inputType == ExerciseInputType.DURATION_DISTANCE || it.inputType == ExerciseInputType.DURATION
    }

    fun close() {
        session.notes = notes.trim()
        session.averageHeartRate = NumberInput.parse(heartRateText)?.takeIf { it > 0 }
        session.sessionRPE = sessionRPE
        store.save()
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
                summary.cardio?.let { cardio ->
                    // Trening sa samo kardio vježbama već ima ukupno trajanje gore; ovdje je vrijeme samih vježbi.
                    if (cardio.seconds > 0) {
                        SummaryRow(
                            stringResource(if (summary.hardSets > 0) R.string.stat_cardio else R.string.cardio_time),
                            CardioText.duration(cardio.seconds.toDouble()),
                        )
                    }
                    cardio.meters?.let { SummaryRow(stringResource(R.string.distance), CardioText.distance(it, locale)) }
                    CardioText.pace(cardio)?.let { SummaryRow(stringResource(R.string.average_pace), it) }
                    CardioText.speed(cardio, locale)?.let { SummaryRow(stringResource(R.string.average_speed), it) }
                }
                if (summary.cardio?.meters == null) {
                    session.distanceMeters?.takeIf { it > 0 }?.let { SummaryRow(stringResource(R.string.distance), CardioText.distance(it, locale)) }
                }
            }
            if (summary.hardSets > 0) {
                Text(
                    stringResource(R.string.hard_sets_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            comparison?.volumeChange?.let { change ->
                Card(Modifier.fillMaxWidth()) {
                    Text(
                        stringResource(R.string.volume_vs_previous, signedPercent(change, locale)),
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

            if (results.isNotEmpty()) {
                Text(stringResource(R.string.exercises_section), style = MaterialTheme.typography.titleMedium)
                Card(Modifier.fillMaxWidth()) {
                    results.forEachIndexed { index, result ->
                        if (index > 0) HorizontalDivider()
                        ExerciseResultRow(result, weight, showsRest = isPro, locale = locale)
                    }
                }
            }

            SessionMusclesCard(services, session, revision = 0L, weekSets = weekSets)

            if (isPro) {
                Card(Modifier.fillMaxWidth()) {
                    ChoiceRow(
                        title = stringResource(R.string.workout_effort),
                        value = sessionRPE?.let { stringResource(R.string.effort_out_of_ten, it.toInt()) } ?: stringResource(R.string.no_rating),
                        options = listOf<Double?>(null) + (1..10).map { it.toDouble() },
                        label = { option -> option?.toInt()?.toString() ?: stringResource(R.string.no_rating) },
                    ) { sessionRPE = it }
                }
                Text(
                    stringResource(R.string.workout_effort_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (hasCardio) {
                OutlinedTextField(
                    value = heartRateText,
                    onValueChange = { text -> heartRateText = text.filter { it.isDigit() }.take(3) },
                    label = { Text(stringResource(R.string.average_heart_rate)) },
                    suffix = { Text(stringResource(R.string.bpm)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
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
internal fun RecordItem(exerciseName: String, record: PersonalRecord, weight: WeightFormatter) {
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


/** Rezultat vježbe u sažetku i detalju treninga (`ExerciseResultRow` na iOS-u): najbolja serija, 1RM i promjena. */
@Composable
internal fun ExerciseResultRow(result: ExerciseResult, weight: WeightFormatter, showsRest: Boolean, locale: java.util.Locale) {
    ListItem(
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = { Text(result.name) },
        supportingContent = {
            val lines = listOfNotNull(
                result.bestSet?.let { setValuesText(it, result.inputType, weight) },
                result.restSeconds?.takeIf { showsRest }?.let { stringResource(R.string.rest_about, DurationInput.format(it.roundToInt())) },
            )
            if (lines.isNotEmpty()) Text(lines.joinToString("\n"))
        },
        trailingContent = result.oneRepMaxKg?.let { oneRepMax ->
            {
                Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                    Text(stringResource(R.string.one_rep_max_about, weight.string(oneRepMax)), style = MaterialTheme.typography.bodyMedium)
                    result.change?.let { change ->
                        Text(
                            signedPercent(change, locale),
                            style = MaterialTheme.typography.bodySmall,
                            color = when {
                                change > 0.005 -> Color(0xFF2E7D32)
                                change < -0.005 -> MaterialTheme.colorScheme.error
                                else -> MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                }
            }
        },
    )
}

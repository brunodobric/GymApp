package com.brunodobric.gymapp.ui.history

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.planning.TemplateEngine
import com.brunodobric.gymapp.stats.HistoryQueries
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.comparison
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.values
import com.brunodobric.gymapp.ui.planning.TemplateEditorScreen
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightFormatter
import java.text.NumberFormat
import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Detalj završenog treninga, prvi korak: sažetak, usporedba s prošlim treningom istog predloška,
 * vježbe sa serijama, bilješke, brisanje i "Novi trening iz ovog" (predložak se otvara u uređivaču).
 * Uređivanje odrađenog treninga i mišići dolaze kasnije.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionDetailScreen(services: AppServices, sessionId: UUID, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val session = remember(revision, sessionId) { store.sessions.firstOrNull { it.id == sessionId } }
    var confirmDelete by remember { mutableStateOf(false) }
    var showsMenu by remember { mutableStateOf(false) }
    var newTemplateId by rememberSaveable { mutableStateOf<UUID?>(null) }

    newTemplateId?.let { id ->
        // Uređivač sprema odmah, pa novi trening ostaje i kad se uređivač zatvori.
        TemplateEditorScreen(services, id, onClose = { newTemplateId = null })
        return
    }
    BackHandler(onBack = onClose)

    if (session == null) {
        // Trening je obrisan (npr. uvozom ili brisanjem svih podataka): ekran se zatvara.
        LaunchedEffect(Unit) { onClose() }
        return
    }
    val unit = store.settings().weightUnit
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(locale) {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.FULL, FormatStyle.SHORT).withLocale(locale)
            .withZone(ZoneId.systemDefault())
    }
    val weight = remember(unit, locale) { WeightFormatter(unit, locale) }
    val exercises = session.orderedExercises.filter { exercise -> !exercise.isRemoved && exercise.sets.any { it.isCompleted } }
    val completedSets = exercises.sumOf { exercise -> exercise.sets.count { it.isCompleted } }
    val volume = exercises.sumOf { exercise ->
        exercise.sets.filter { it.isCompleted }.sumOf { SetMetrics.volume(it.values, exercise.inputType) }
    }
    val seconds = session.endedAt?.let { Duration.between(session.startedAt, it).seconds.toInt() } ?: 0
    val comparison = remember(revision, sessionId) { StatisticsEngine(store).comparison(session) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(session.name) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    IconButton(onClick = { confirmDelete = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete_workout))
                    }
                    Box {
                        IconButton(onClick = { showsMenu = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more_options))
                        }
                        DropdownMenu(expanded = showsMenu, onDismissRequest = { showsMenu = false }) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.template_from_session)) },
                                enabled = session.orderedExercises.any { !it.isRemoved },
                                onClick = {
                                    showsMenu = false
                                    newTemplateId = TemplateEngine(store).createTemplate(session).id
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(formatter.format(session.startedAt), style = MaterialTheme.typography.bodyLarge)
                Text(
                    DurationInput.format(seconds) + " · " + pluralStringResource(R.plurals.completed_sets, completedSets, completedSets) +
                        (if (volume > 0) " · " + weight.string(volume) else ""),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            comparison?.volumeChange?.let { change ->
                Card {
                    Text(
                        stringResource(R.string.volume_vs_previous, signedPercent(change, locale)),
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            exercises.forEach { exercise ->
                Card {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(exercise.exerciseName, style = MaterialTheme.typography.titleMedium)
                        var number = 0
                        exercise.orderedSets.filter { it.isCompleted }.forEach { set ->
                            val label = if (set.kind == SetKind.WARM_UP) {
                                stringResource(R.string.warm_up_short)
                            } else {
                                number += 1
                                number.toString()
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Text(
                                    label,
                                    modifier = Modifier.widthIn(min = 24.dp),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(setText(set, exercise.inputType, weight), modifier = Modifier.weight(1f))
                                set.rpe?.let { Text("RPE " + NumberInput.format(it), style = MaterialTheme.typography.bodySmall) }
                            }
                        }
                    }
                }
            }

            if (session.notes.isNotBlank()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.notes), style = MaterialTheme.typography.titleSmall)
                    Text(session.notes, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_workout_title)) },
            text = { Text(stringResource(R.string.delete_workout_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    HistoryQueries(store).delete(session)
                    onClose()
                }) { Text(stringResource(R.string.delete_workout), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Vrijednosti serije kao na iOS-u: "80 kg × 8", "× 12", "+10 kg × 6", "−20 kg × 8", "25:00 · 5 km". */
private fun setText(set: SetLog, inputType: ExerciseInputType, weight: WeightFormatter): String = when (inputType) {
    ExerciseInputType.WEIGHT_REPS -> "${weight.string(set.weightKg ?: 0.0)} × ${set.reps ?: 0}"
    ExerciseInputType.BODYWEIGHT -> "× ${set.reps ?: 0}"
    ExerciseInputType.WEIGHTED_BODYWEIGHT -> "+${weight.string(set.extraWeightKg ?: 0.0)} × ${set.reps ?: 0}"
    ExerciseInputType.ASSISTED -> "−${weight.string(set.extraWeightKg ?: 0.0)} × ${set.reps ?: 0}"
    ExerciseInputType.DURATION -> DurationInput.format(set.durationSeconds ?: 0)
    ExerciseInputType.DURATION_DISTANCE -> {
        val time = DurationInput.format(set.durationSeconds ?: 0)
        set.distanceMeters?.let { "$time · ${NumberInput.format(it / 1000)} km" } ?: time
    }
}

/** Promjena kao postotak s predznakom, u zapisu jezika ("+5 %" na hrvatskom, "+5%" na engleskom). */
private fun signedPercent(change: Double, locale: Locale): String {
    val rounded = (change * 100).roundToInt() / 100.0
    val text = NumberFormat.getPercentInstance(locale).format(rounded)
    return if (rounded > 0) "+$text" else text
}

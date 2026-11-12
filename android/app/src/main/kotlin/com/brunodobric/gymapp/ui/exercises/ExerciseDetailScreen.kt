package com.brunodobric.gymapp.ui.exercises

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.ui.settings.weightStepText
import com.brunodobric.gymapp.ui.settings.ChoiceRow
import com.brunodobric.gymapp.model.weightSteps
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.Level
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.illustration
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.stats.ExerciseHistoryHighlight
import com.brunodobric.gymapp.stats.ExercisePerformance
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.history
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.statistics.ExerciseProgressScreen
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightFormatter
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

/**
 * Detalj vježbe, kao `ExerciseDetailScreen` na iOS-u: mišići, detalji, upute (samo kad su MoveKit tekstovi u
 * buildu) i "Tvoja povijest" sa svim izvođenjima. Dodir izvođenja otvara trening. Vlastita vježba ima "Uredi".
 * "Napredak i rekordi" otvara graf napretka iz Statistike. Na vrhu je MoveKit klip ([ExerciseIllustrationView]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExerciseDetailScreen(
    services: AppServices,
    source: ExerciseSummary.Source,
    onClose: () -> Unit,
    onEdit: (UUID) -> Unit,
    onOpenSession: (UUID) -> Unit,
    /** Usred treninga stranica pokazuje samo klip, mišiće i upute (kao `ExerciseInfoSheet` na iOS-u). */
    showsHistory: Boolean = true,
) {
    BackHandler(onBack = onClose)
    val store = services.store
    val revision = rememberStoreRevision(store)
    val language = catalogLanguage()
    val locale = LocalConfiguration.current.locales[0]
    val catalogExercise = (source as? ExerciseSummary.Source.Catalog)?.let { services.catalog.exercise(it.id) }
    val customExercise = (source as? ExerciseSummary.Source.Custom)?.let { store.customExercise(it.id) }
    val ref = catalogExercise?.let { ExerciseRef.catalog(it.id, it.displayName(language)) } ?: customExercise?.ref
    if (ref == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }
    var showsProgress by rememberSaveable { mutableStateOf(false) }
    if (showsProgress) {
        ExerciseProgressScreen(services, ref, onClose = { showsProgress = false })
        return
    }
    val settings = store.settings()
    val unit = settings.weightUnit
    val weight = remember(unit, locale) { WeightFormatter(unit, locale) }
    val history = remember(revision, ref.key) {
        // Rekord se ne označava kad su rekordi isključeni ili je vježba isključena iz rekorda.
        val kinds = if (ref.key in settings.prExcludedExerciseKeys) emptySet() else PRKind.tracked(settings)
        StatisticsEngine(store).history(ref, kinds)
    }
    val dates = remember(locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(ZoneId.systemDefault())
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(ref.name) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    if (showsHistory) customExercise?.let { exercise ->
                        TextButton(onClick = { onEdit(exercise.id) }) { Text(stringResource(R.string.edit)) }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            catalogExercise?.let { exercise ->
                val context = LocalContext.current
                val illustration = remember(exercise.id) {
                    exercise.illustration { it in MoveKitAssets.available(context) }
                }
                ExerciseIllustrationView(illustration, ref.name, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            }
            customExercise?.imageFile?.let(services.exerciseImages::file)?.let { file ->
                ExerciseImage(file, ref.name, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            }
            val primary = catalogExercise?.primaryMuscles ?: customExercise?.muscles.orEmpty()
            val secondary = catalogExercise?.secondaryMuscles.orEmpty()
            if (primary.isNotEmpty()) {
                Header(stringResource(R.string.muscles))
                InfoRow(stringResource(R.string.primary), muscleList(primary))
                if (secondary.isNotEmpty()) InfoRow(stringResource(R.string.secondary), muscleList(secondary))
            }

            Header(stringResource(R.string.details))
            (catalogExercise?.category ?: customExercise?.category)?.let {
                InfoRow(stringResource(R.string.exercise_category), stringResource(categoryTitle(it)))
            }
            (catalogExercise?.equipment ?: customExercise?.equipment)?.let {
                InfoRow(stringResource(R.string.exercise_equipment), stringResource(equipmentTitle(it)))
            }
            catalogExercise?.level?.let { InfoRow(stringResource(R.string.level), stringResource(levelTitle(it))) }
            (catalogExercise?.inputType ?: customExercise?.inputType)?.let {
                InfoRow(stringResource(R.string.exercise_input), stringResource(inputTypeTitle(it)))
                // Vlastiti korak težine vježbe (`ExerciseWeightStepRow` na iOS-u), samo za vrste unosa s težinom.
                if (it == ExerciseInputType.WEIGHT_REPS || it == ExerciseInputType.WEIGHTED_BODYWEIGHT || it == ExerciseInputType.ASSISTED) {
                    ExerciseWeightStepRow(services, ref, catalogExercise?.equipment ?: customExercise?.equipment)
                }
            }
            customExercise?.details?.takeIf { it.isNotBlank() }?.let { details ->
                Text(details, Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.bodyMedium)
            }

            if (catalogExercise != null) {
                Header(stringResource(R.string.instructions))
                val steps = catalogExercise.displayInstructions(language)
                if (steps.isEmpty()) {
                    Secondary(stringResource(R.string.instructions_unavailable))
                } else {
                    steps.forEachIndexed { index, step ->
                        Text("${index + 1}. $step", Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                    }
                }
            }

            if (showsHistory && !history.isEmpty) {
                Header(stringResource(R.string.your_history))
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Metric(history.count.toString(), stringResource(R.string.in_workouts), Modifier.weight(1f))
                    history.highlights.forEach { highlight ->
                        val (value, label) = highlightText(highlight, weight, locale)
                        Metric(value, label, Modifier.weight(1f))
                    }
                }
                history.performances.forEach { performance ->
                    PerformanceRow(performance, weight, dates.format(performance.date)) { onOpenSession(performance.sessionId) }
                    HorizontalDivider()
                }
                ListItem(
                    headlineContent = { Text(stringResource(R.string.progress_and_records)) },
                    modifier = Modifier.clickable { showsProgress = true },
                )
                HorizontalDivider()
                val usesWeight = history.performances.any { it.inputType in WEIGHTED }
                Secondary(
                    listOfNotNull(
                        if (usesWeight) stringResource(R.string.weights_in, unit.symbol) else null,
                        stringResource(R.string.warm_up_hidden),
                        stringResource(R.string.tap_opens_workout),
                    ).joinToString(" "),
                )
            }
        }
    }
}

private val WEIGHTED = setOf(ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED)

@Composable
private fun Header(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 4.dp),
    )
}

@Composable
private fun InfoRow(title: String, value: String) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = { Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.End) },
    )
}

@Composable
private fun Secondary(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

@Composable
private fun Metric(value: String, label: String, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(value, style = MaterialTheme.typography.titleMedium, maxLines = 1)
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

/** Naziv treninga, datum i radne serije, npr. "85 × 5 · 85 × 5 · 80 × 7". */
@Composable
private fun PerformanceRow(performance: ExercisePerformance, weight: WeightFormatter, date: String, onClick: () -> Unit) {
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(performance.sessionName.ifBlank { stringResource(R.string.workout_fallback) })
                if (performance.hasRecord) {
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = stringResource(R.string.personal_record),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        },
        overlineContent = { Text(date) },
        supportingContent = { Text(performance.sets.joinToString(" · ") { setValuesText(it, performance.inputType, weight) }) },
    )
}

@Composable
private fun muscleList(muscles: List<Muscle>): String = muscles.map { stringResource(muscleTitle(it)) }.joinToString(", ")

@Composable
private fun highlightText(highlight: ExerciseHistoryHighlight, weight: WeightFormatter, locale: java.util.Locale): Pair<String, String> =
    when (highlight) {
        is ExerciseHistoryHighlight.Heaviest -> weight.string(highlight.kg) to stringResource(R.string.heaviest_set)
        is ExerciseHistoryHighlight.OneRepMax -> "≈ " + weight.string(highlight.kg) to stringResource(R.string.estimated_1rm)
        is ExerciseHistoryHighlight.MostReps -> highlight.reps.toString() to stringResource(R.string.most_reps)
        is ExerciseHistoryHighlight.LongestDuration -> DurationInput.format(highlight.seconds) to stringResource(R.string.longest)
        is ExerciseHistoryHighlight.LongestDistance ->
            NumberInput.format(highlight.meters / 1000, locale) + " km" to stringResource(R.string.farthest)
    }

/** Vrijednosti serije bez jedinice (jedinica je u napomeni ispod), kao `ExerciseHistoryFormat` na iOS-u. */
internal fun setValuesText(set: SetValues, type: ExerciseInputType, weight: WeightFormatter): String = when (type) {
    ExerciseInputType.WEIGHT_REPS -> "${weight.number(set.weightKg ?: 0.0)} × ${set.reps ?: 0}"
    ExerciseInputType.WEIGHTED_BODYWEIGHT -> "+${weight.number(set.extraWeightKg ?: 0.0)} × ${set.reps ?: 0}"
    ExerciseInputType.ASSISTED -> "−${weight.number(set.extraWeightKg ?: 0.0)} × ${set.reps ?: 0}"
    ExerciseInputType.BODYWEIGHT -> "× ${set.reps ?: 0}"
    ExerciseInputType.DURATION -> DurationInput.format(set.durationSeconds ?: 0)
    ExerciseInputType.DURATION_DISTANCE -> {
        val time = DurationInput.format(set.durationSeconds ?: 0)
        set.distanceMeters?.let { "$time · ${NumberInput.format(it / 1000)} km" } ?: time
    }
}

private fun levelTitle(level: Level): Int = when (level) {
    Level.BEGINNER -> R.string.catalog_level_beginner
    Level.INTERMEDIATE -> R.string.catalog_level_intermediate
    Level.ADVANCED -> R.string.catalog_level_advanced
}

/** Korak težine vježbe: "Prema opremi" (korak iz Postavki > Trening > Korak težine) ili vlastiti korak. */
@Composable
private fun ExerciseWeightStepRow(services: AppServices, ref: ExerciseRef, equipment: com.brunodobric.gymapp.catalog.Equipment?) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    val unit = settings.weightUnit
    val steps = settings.weightSteps
    val byEquipment = stringResource(R.string.by_equipment_step, weightStepText(steps.step(equipment, unit), unit))
    val current = steps.override(ref.key, unit)
    ChoiceRow(
        title = stringResource(R.string.weight_step),
        value = current?.let { weightStepText(it, unit) } ?: byEquipment,
        options = listOf<Double?>(null) + WeightStepSettings.choices(unit),
        label = { option -> option?.let { weightStepText(it, unit) } ?: byEquipment },
    ) { step ->
        val updated = settings.weightSteps
        updated.setOverride(step, ref.key, unit)
        settings.weightSteps = updated
        store.save()
    }
}

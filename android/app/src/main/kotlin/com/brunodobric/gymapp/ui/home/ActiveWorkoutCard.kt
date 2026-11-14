package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.planning.PlannedWorkout
import com.brunodobric.gymapp.training.LiveSetEditor
import com.brunodobric.gymapp.training.LiveSetValue
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.liveStatus
import com.brunodobric.gymapp.training.nextSet
import com.brunodobric.gymapp.training.previousSetValues
import com.brunodobric.gymapp.training.restDefaults
import com.brunodobric.gymapp.ui.rememberTicker
import com.brunodobric.gymapp.ui.theme.success
import com.brunodobric.gymapp.units.DurationInput
import java.time.Duration

/**
 * Trening u tijeku sažet u karticu na Početnoj (`ActiveWorkoutCard` na iOS-u, isti raspored kao obavijest):
 * gore trajanje, vježba i broj serije; ispod prošli put, vrijednosti s − i + i velika zelena kvačica, a za
 * vrijeme odmora umjesto kvačice odbrojavanje. Pozadina je traka odmora koja se prazni kako odmor teče.
 * Gumbi rade isto što i gumbi obavijesti; dodir izvan gumba otvara cijeli ekran treninga.
 */
@Composable
internal fun ActiveWorkoutCard(services: AppServices, revision: Long, onOpen: () -> Unit) {
    val store = services.store
    val session = store.activeSession() ?: return
    val engine = remember(store) { WorkoutEngine(store) }
    val settings = store.settings()
    val unit = settings.weightUnit
    val locale = LocalConfiguration.current.locales[0]
    val now = rememberTicker()
    val status = remember(revision) { engine.liveStatus(session) }
    val next = remember(revision) { engine.nextSet(session) }
    val exercise = next?.exercise
    val values = remember(revision, unit, locale) {
        if (next != null && exercise != null) LiveSetEditor.values(next, exercise.inputType, unit, locale) else emptyList()
    }
    val previous = remember(exercise?.id) { exercise?.let { store.previousSetValues(it.exercise, it.session?.templateId) }.orEmpty() }
    val previousText = if (next != null && exercise != null) {
        LiveSetEditor.previousText(next, exercise.inputType, previous, unit, locale)
    } else {
        null
    }
    val rest = status.rest?.takeIf { it.remaining(now) > 0 }

    val accent = MaterialTheme.colorScheme.primary
    Box(
        Modifier.fillMaxWidth()
            .workoutCardBackground()
            .clickable(onClick = onOpen),
    ) {
        // Traka odmora: obojeni dio se s desna na lijevo smanjuje kako odmor teče.
        rest?.let { timer ->
            val fraction = (timer.remaining(now) / timer.totalSeconds.coerceAtLeast(1.0)).toFloat().coerceIn(0f, 1f)
            Box(Modifier.matchParentSize()) {
                Box(Modifier.fillMaxHeight().fillMaxWidth(fraction).background(accent.copy(alpha = 0.22f)))
            }
        }
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                val seconds = Duration.between(session.startedAt, now).seconds.coerceAtLeast(0).toInt()
                Text(
                    DurationInput.format(seconds),
                    Modifier.width(64.dp),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    status.currentExerciseName ?: if (status.totalSets > 0) stringResource(R.string.all_sets_done) else session.name,
                    Modifier.weight(1f),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    if (status.currentExerciseName != null) "${status.setNumber}/${status.setCount}" else "",
                    Modifier.width(64.dp),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.End,
                )
            }
            if (next != null && exercise != null && values.isNotEmpty()) {
                Row(Modifier.height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        previousText.orEmpty(),
                        Modifier.width(70.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        values.forEach { value ->
                            ValueStepper(value) { steps ->
                                val step = WeightStepSettings.resolver(settings, services.catalog, store.customExercises)(exercise.exercise)
                                if (LiveSetEditor.adjust(next, value.field, steps, unit, step)) engine.touch(session)
                            }
                        }
                    }
                    Box(Modifier.width(68.dp).fillMaxHeight().heightIn(min = 52.dp), contentAlignment = Alignment.Center) {
                        when {
                            rest != null -> Text(
                                DurationInput.format(rest.remaining(now).toInt()),
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.ExtraBold,
                            )
                            status.canConfirmNextSet -> {
                                val success = MaterialTheme.colorScheme.success
                                Box(
                                    Modifier.fillMaxWidth().fillMaxHeight()
                                        .clip(RoundedCornerShape(14.dp))
                                        .background(success.copy(alpha = 0.16f))
                                        .clickable {
                                            val isCompound: (String) -> Boolean? = { key ->
                                                if (key.startsWith("c:")) {
                                                    services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND }
                                                } else {
                                                    null
                                                }
                                            }
                                            runCatching { engine.completeSet(next, settings.restDefaults, isCompound) }
                                        },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.confirm_set), tint = success, modifier = Modifier.size(32.dp))
                                }
                            }
                        }
                    }
                }
            } else {
                Text(
                    if (status.totalSets > 0) {
                        stringResource(R.string.sets_progress, status.completedSets, status.totalSets)
                    } else {
                        stringResource(R.string.add_exercise)
                    },
                    Modifier.fillMaxWidth(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/** Vrijednost serije između gumba − i +; jedan dodir je jedan korak, kao u obavijesti. */
@Composable
private fun ValueStepper(value: LiveSetValue, onStep: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest).padding(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepButton("−", stringResource(R.string.decrease), value.canDecrease) { onStep(-1) }
        Text(
            if (value.unitSymbol.isEmpty()) value.text else "${value.text} ${value.unitSymbol}",
            Modifier.weight(1f),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.ExtraBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
        StepButton("+", stringResource(R.string.increase), value.canIncrease) { onStep(1) }
    }
}

@Composable
private fun StepButton(symbol: String, label: String, enabled: Boolean, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Box(
        Modifier.size(width = 42.dp, height = 34.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(accent.copy(alpha = if (enabled) 0.18f else 0.07f))
            .clickable(enabled = enabled, onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(symbol, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = accent.copy(alpha = if (enabled) 1f else 0.4f))
    }
}

/**
 * Sljedeći trening kao plava kartica iz prijedloga dizajna: raspored i ciklus, naziv, vježbe s planom
 * (npr. "3 × 8–10") i bijeli gumb "Započni". Ostali načini početka su u kartici ispod.
 */
@Composable
internal fun NextWorkoutHero(workout: PlannedWorkout, onStart: () -> Unit) {
    val onAccent = Color.White
    Column(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(MaterialTheme.colorScheme.primary)
            .clickable(onClick = onStart)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val cycles = workout.schedule.cycleCount
        val chip = if (cycles != null) {
            "${workout.schedule.name} · ${stringResource(R.string.cycle_of, workout.cycle, cycles)}"
        } else {
            workout.schedule.name
        }
        Text(
            chip,
            Modifier.clip(RoundedCornerShape(12.dp)).background(onAccent.copy(alpha = 0.18f)).padding(horizontal = 10.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = onAccent,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                stringResource(R.string.next_workout).uppercase(LocalConfiguration.current.locales[0]),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = onAccent.copy(alpha = 0.75f),
            )
            Text(workout.template.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold, color = onAccent)
        }
        val template = workout.template.orderedExercises
        val shown = workout.exercises.take(4)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            shown.forEach { planned ->
                Row {
                    Text(planned.ref.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = onAccent, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val sets = template.firstOrNull { it.id == planned.source }?.orderedSets?.filter { it.kind == SetKind.WORKING }.orEmpty()
                    if (sets.isNotEmpty() && !planned.isReplacement) {
                        val low = sets.first().targetReps
                        val high = sets.first().targetRepsMax
                        val reps = when {
                            low != null && high != null && high > low -> " × $low–$high"
                            low != null -> " × $low"
                            else -> ""
                        }
                        Text("${sets.size}$reps", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = onAccent.copy(alpha = 0.85f))
                    }
                }
            }
            if (workout.exercises.size > shown.size) {
                Text(
                    stringResource(R.string.more_exercises, workout.exercises.size - shown.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = onAccent.copy(alpha = 0.75f),
                )
            }
        }
        Row(
            Modifier.clip(RoundedCornerShape(24.dp)).background(onAccent).clickable(onClick = onStart).padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.start_short), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        }
    }
}


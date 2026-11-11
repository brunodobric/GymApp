package com.brunodobric.gymapp.ui.workout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.EffortScale
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.ui.exercises.ExercisePosterTile
import com.brunodobric.gymapp.ui.theme.success
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.units.WeightUnit

/** Radnje kartice vježbe na ekranu treninga. */
internal class ExerciseCardActions(
    val onToggleOpen: () -> Unit,
    val onChange: () -> Unit,
    val onToggle: (SetLog) -> Unit,
    val onEditSet: (SetLog) -> Unit,
    val onChangeKind: (SetLog, SetKind) -> Unit,
    val onAddSet: (SetKind) -> Unit,
    val onDeleteSet: (SetLog) -> Unit,
    val onRemove: () -> Unit,
    val onPlates: (String) -> Unit,
    val onSuperset: () -> Unit,
    val onLeaveSuperset: () -> Unit,
    val onShowInfo: (() -> Unit)?,
)

/**
 * Kartica vježbe (`ExerciseCard` na iOS-u, u novom dizajnu): sličica, naslov s napretkom, a kad je otvorena
 * tablica serija SERIJA | PROŠLI PUT | vrijednosti | kvačica. Trenutna serija je označena, a završene su
 * prigušene. Težina i ponavljanja otvaraju donji list s kotačićem ([SetSheet]).
 */
@Composable
internal fun WorkoutExerciseCard(
    exercise: SessionExercise,
    posterPath: String?,
    isOpen: Boolean,
    previousText: (SetLog) -> String?,
    unit: WeightUnit,
    effortScale: EffortScale,
    actions: ExerciseCardActions,
) {
    val sets = exercise.orderedSets
    val done = sets.count { it.isCompleted }
    val allDone = sets.isNotEmpty() && done == sets.size
    val current = sets.firstOrNull { !it.isCompleted }
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Column(Modifier.padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = if (isOpen) 8.dp else 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ExerciseThumbnail(exercise.exerciseName, posterPath, onClick = actions.onShowInfo)
                Column(Modifier.weight(1f).clickable(onClick = actions.onToggleOpen)) {
                    if (exercise.supersetGroupId != null) {
                        Text(
                            stringResource(R.string.superset).uppercase(LocalConfiguration.current.locales[0]),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Text(exercise.exerciseName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (allDone) {
                            Icon(Icons.Filled.Check, contentDescription = null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.success)
                        }
                        Text(
                            stringResource(R.string.sets_progress, done, sets.size),
                            style = MaterialTheme.typography.bodySmall,
                            color = if (allDone) MaterialTheme.colorScheme.success else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                IconButton(onClick = actions.onToggleOpen) {
                    Icon(
                        if (isOpen) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                        contentDescription = stringResource(if (isOpen) R.string.collapse_exercise else R.string.expand_exercise),
                    )
                }
                ExerciseMenu(exercise, actions)
            }
            if (isOpen) {
                Column(Modifier.padding(top = 12.dp, end = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SetTableHeader(exercise.inputType, unit)
                    var working = 0
                    for (set in sets) {
                        val label = if (set.kind == SetKind.WARM_UP) stringResource(R.string.warm_up_short) else (++working).toString()
                        WorkoutSetRow(
                            label = label,
                            set = set,
                            inputType = exercise.inputType,
                            unit = unit,
                            effortScale = effortScale,
                            previousText = previousText(set),
                            isCurrent = set.id == current?.id,
                            actions = actions,
                        )
                    }
                    HorizontalDivider(Modifier.padding(top = 4.dp), color = MaterialTheme.colorScheme.outlineVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { actions.onAddSet(SetKind.WORKING) }) {
                            Icon(Icons.Filled.Add, contentDescription = null, Modifier.size(18.dp))
                            Text(stringResource(R.string.add_set), Modifier.padding(start = 4.dp))
                        }
                        TextButton(onClick = { actions.onAddSet(SetKind.WARM_UP) }) {
                            Icon(Icons.Filled.Add, contentDescription = null, Modifier.size(18.dp))
                            Text(stringResource(R.string.add_warm_up), Modifier.padding(start = 4.dp))
                        }
                    }
                }
            }
        }
    }
}

/** Sličica vježbe: poster iz MoveKita ili početno slovo. Dodir otvara stranicu vježbe. */
@Composable
private fun ExerciseThumbnail(name: String, posterPath: String?, onClick: (() -> Unit)?) {
    val shape = RoundedCornerShape(14.dp)
    val modifier = Modifier.size(52.dp).clip(shape).let { if (onClick != null) it.clickable(onClick = onClick) else it }
    if (posterPath != null) {
        ExercisePosterTile(posterPath, modifier)
    } else {
        Box(modifier.background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
            Text(
                name.take(1).uppercase(LocalConfiguration.current.locales[0]),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun ExerciseMenu(exercise: SessionExercise, actions: ExerciseCardActions) {
    var menu by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { menu = true }) {
            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more_options))
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            actions.onShowInfo?.let { show ->
                DropdownMenuItem(text = { Text(stringResource(R.string.show_exercise)) }, onClick = {
                    menu = false
                    show()
                })
            }
            DropdownMenuItem(text = { Text(stringResource(R.string.superset)) }, onClick = {
                menu = false
                actions.onSuperset()
            })
            if (exercise.supersetGroupId != null) {
                DropdownMenuItem(text = { Text(stringResource(R.string.leave_superset)) }, onClick = {
                    menu = false
                    actions.onLeaveSuperset()
                })
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.remove_exercise), color = MaterialTheme.colorScheme.error) },
                onClick = {
                    menu = false
                    actions.onRemove()
                },
            )
        }
    }
}

private val BADGE_WIDTH = 36.dp
private val CHECK_SIZE = 40.dp

/** Nazivi stupaca, isti raspored kao u [WorkoutSetRow]. */
@Composable
private fun SetTableHeader(inputType: ExerciseInputType, unit: WeightUnit) {
    val locale = LocalConfiguration.current.locales[0]
    val style = MaterialTheme.typography.labelSmall
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    @Composable
    fun header(text: String, modifier: Modifier) =
        Text(text.uppercase(locale), modifier, style = style, fontWeight = FontWeight.Bold, color = color, textAlign = TextAlign.Center, maxLines = 1)
    Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        header(stringResource(R.string.set_column), Modifier.width(BADGE_WIDTH))
        header(stringResource(R.string.previous_column), Modifier.weight(1.2f))
        valueColumns(inputType, unit).forEach { header(it, Modifier.weight(1f)) }
        Box(Modifier.width(CHECK_SIZE))
    }
}

/** Nazivi stupaca vrijednosti prema vrsti unosa. */
@Composable
private fun valueColumns(inputType: ExerciseInputType, unit: WeightUnit): List<String> {
    val reps = stringResource(R.string.reps_label)
    val duration = stringResource(R.string.duration_label)
    return when (inputType) {
        ExerciseInputType.WEIGHT_REPS -> listOf(unit.symbol, reps)
        ExerciseInputType.WEIGHTED_BODYWEIGHT -> listOf("+${unit.symbol}", reps)
        ExerciseInputType.ASSISTED -> listOf("−${unit.symbol}", reps)
        ExerciseInputType.BODYWEIGHT -> listOf(reps)
        ExerciseInputType.DURATION -> listOf(duration)
        ExerciseInputType.DURATION_DISTANCE -> listOf(duration, "km")
    }
}

/**
 * Redak serije. Oznaka otvara izbornik (vrsta serije, kalkulator ploča, brisanje), napor ispod prošlog puta
 * izbornik ocjena, a težina i ponavljanja donji list s kotačićem. Trajanje i udaljenost upisuju se tipkovnicom.
 */
@Composable
private fun WorkoutSetRow(
    label: String,
    set: SetLog,
    inputType: ExerciseInputType,
    unit: WeightUnit,
    effortScale: EffortScale,
    previousText: String?,
    isCurrent: Boolean,
    actions: ExerciseCardActions,
) {
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(unit, locale) { WeightFormatter(unit, locale) }
    val dim = if (set.isCompleted) 0.55f else 1f
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(if (isCurrent) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f) else MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(horizontal = 4.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SetBadge(label, set, inputType, formatter, actions, Modifier.width(BADGE_WIDTH).alpha(dim))
        Column(Modifier.weight(1.2f).alpha(dim), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                previousText ?: "–",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                maxLines = 2,
            )
            if (set.rpe != null || isCurrent || !set.isCompleted) EffortMenu(set, effortScale, actions.onChange)
        }
        when (inputType) {
            ExerciseInputType.WEIGHT_REPS, ExerciseInputType.WEIGHTED_BODYWEIGHT, ExerciseInputType.ASSISTED -> {
                val weight = if (inputType == ExerciseInputType.WEIGHT_REPS) set.weightKg else set.extraWeightKg
                ValueCell(weight?.let(formatter::number), Modifier.weight(1f).alpha(dim)) { actions.onEditSet(set) }
                ValueCell(set.reps?.toString(), Modifier.weight(1f).alpha(dim)) { actions.onEditSet(set) }
            }
            ExerciseInputType.BODYWEIGHT -> ValueCell(set.reps?.toString(), Modifier.weight(1f).alpha(dim)) { actions.onEditSet(set) }
            ExerciseInputType.DURATION, ExerciseInputType.DURATION_DISTANCE -> {
                TextCell("${set.id}-duration", DurationInput.format(set.durationSeconds), false, Modifier.weight(1f).alpha(dim)) { text ->
                    set.durationSeconds = DurationInput.parse(text)
                    actions.onChange()
                }
                if (inputType == ExerciseInputType.DURATION_DISTANCE) {
                    val initial = set.distanceMeters?.let { NumberInput.format(it / 1000, locale) } ?: ""
                    TextCell("${set.id}-distance", initial, true, Modifier.weight(1f).alpha(dim)) { text ->
                        set.distanceMeters = NumberInput.parse(text, locale)?.let { it * 1000 }
                        actions.onChange()
                    }
                }
            }
        }
        CheckButton(set.isCompleted, isCurrent) { actions.onToggle(set) }
    }
}

/** Broj serije ili "Z" za zagrijavanje; dodir otvara izbornik serije. */
@Composable
private fun SetBadge(
    label: String,
    set: SetLog,
    inputType: ExerciseInputType,
    formatter: WeightFormatter,
    actions: ExerciseCardActions,
    modifier: Modifier,
) {
    var menu by remember { mutableStateOf(false) }
    Box(modifier, contentAlignment = Alignment.Center) {
        val warmUp = set.kind == SetKind.WARM_UP
        Box(
            Modifier.size(30.dp)
                .clip(CircleShape)
                .background(if (warmUp) MaterialTheme.colorScheme.tertiary.copy(alpha = 0.14f) else MaterialTheme.colorScheme.surfaceContainer)
                .clickable { menu = true },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                label,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = if (warmUp) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.working_set)) },
                leadingIcon = { if (!warmUp) Icon(Icons.Filled.Check, contentDescription = null) },
                onClick = {
                    menu = false
                    actions.onChangeKind(set, SetKind.WORKING)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.kind_warm_up)) },
                leadingIcon = { if (warmUp) Icon(Icons.Filled.Check, contentDescription = null) },
                onClick = {
                    menu = false
                    actions.onChangeKind(set, SetKind.WARM_UP)
                },
            )
            if (inputType == ExerciseInputType.WEIGHT_REPS) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.plate_calculator)) },
                    onClick = {
                        menu = false
                        actions.onPlates(set.weightKg?.let(formatter::number) ?: "")
                    },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete_set), color = MaterialTheme.colorScheme.error) },
                onClick = {
                    menu = false
                    actions.onDeleteSet(set)
                },
            )
        }
    }
}

/** Napor serije (RPE ili RIR) s izbornikom ocjena, kao `effortMenu` na iOS-u. */
@Composable
private fun EffortMenu(set: SetLog, scale: EffortScale, onChange: () -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    var menu by remember { mutableStateOf(false) }
    fun label(rpe: Double): String =
        if (scale == EffortScale.RPE) "RPE ${NumberInput.format(rpe, locale)}" else "RIR ${NumberInput.format(10 - rpe, locale)}"
    Box {
        val rpe = set.rpe
        Text(
            rpe?.let(::label) ?: if (scale == EffortScale.RPE) "RPE" else "RIR",
            Modifier.padding(top = 2.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable { menu = true }
                .padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = if (rpe != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
            DropdownMenuItem(text = { Text(stringResource(R.string.no_rating)) }, onClick = {
                menu = false
                set.rpe = null
                onChange()
            })
            // RPE od 10 do 1 u koracima od 0,5; uz RIR do 5 ponavljanja u rezervi (RPE 5).
            val lowest = if (scale == EffortScale.RPE) 1.0 else 5.0
            generateSequence(10.0) { it - 0.5 }.takeWhile { it >= lowest }.forEach { option ->
                DropdownMenuItem(text = { Text(label(option)) }, onClick = {
                    menu = false
                    set.rpe = option
                    onChange()
                })
            }
        }
    }
}

/** Vrijednost koja se mijenja kotačićem; prazna vrijednost je crtica. */
@Composable
private fun ValueCell(text: String?, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.height(44.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text ?: "–",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.ExtraBold,
            color = if (text == null) MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f) else MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
        )
    }
}

/** Polje za tipkovnicu: tekst živi u ekranu, a vrijednost se pretvara i sprema pri svakoj izmjeni. */
@Composable
private fun TextCell(key: String, initial: String, decimal: Boolean, modifier: Modifier, onValue: (String) -> Unit) {
    var text by rememberSaveable(key) { mutableStateOf(initial) }
    OutlinedTextField(
        value = text,
        onValueChange = {
            text = it
            onValue(it)
        },
        modifier = modifier,
        singleLine = true,
        textStyle = MaterialTheme.typography.titleMedium.copy(textAlign = TextAlign.Center, fontWeight = FontWeight.Bold),
        keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number),
    )
}

/** Okrugla kvačica: puna zelena kad je serija gotova, obrubljena zelena za trenutnu seriju. */
@Composable
private fun CheckButton(completed: Boolean, isCurrent: Boolean, onClick: () -> Unit) {
    val success = MaterialTheme.colorScheme.success
    val modifier = Modifier.size(CHECK_SIZE).clip(CircleShape)
    Box(
        when {
            completed -> modifier.background(success)
            isCurrent -> modifier.border(2.dp, success, CircleShape)
            else -> modifier.border(1.5.dp, MaterialTheme.colorScheme.outlineVariant, CircleShape)
        }.clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Filled.Check,
            contentDescription = stringResource(R.string.complete_set),
            tint = when {
                completed -> Color.White
                isCurrent -> success
                else -> MaterialTheme.colorScheme.outline
            },
        )
    }
}

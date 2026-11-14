package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.planning.PlannedWorkout
import java.util.UUID

/**
 * Kartica za početak treninga (`StartWorkoutCard` na iOS-u). Svaki red je jedan način početka: sljedeći
 * trening svakog rasporeda, ispod svih njih jedan red za izbor drugog treninga (iz bilo kojeg aktivnog
 * rasporeda ili spremljenog), i prazan trening. Bez aktivnog rasporeda,
 * a sa spremljenim treninzima, prvi red otvara njihov popis.
 */
@Composable
fun StartWorkoutCard(
    planned: List<PlannedWorkout>,
    templateCount: Int,
    /** Postoji li trening koji se može pokrenuti umjesto sljedećih (red "Odaberi drugi trening"). */
    offersOtherWorkout: Boolean,
    onStart: (PlannedWorkout) -> Unit,
    /** Izbor treninga: s aktivnim rasporedima njihovi treninzi i ostali spremljeni, bez njih samo spremljeni. */
    onChooseTemplate: (List<Schedule>) -> Unit,
    onStartEmpty: () -> Unit,
    /** Prvi sljedeći trening je već na plavoj kartici iznad, pa se ovdje ne ponavlja. */
    skipsFirst: Boolean = false,
) {
    val offersTemplates = templateCount > 0 && planned.isEmpty()
    // U boji akcenta kao na iOS-u, ista pozadina kao kartica treninga u tijeku.
    Column(Modifier.fillMaxWidth().workoutCardBackground()) {
        planned.drop(if (skipsFirst) 1 else 0).forEach { workout ->
            StartRow(
                icon = Icons.Filled.PlayArrow,
                prominent = true,
                title = stringResource(R.string.start_named, workout.template.name),
                subtitle = plannedSubtitle(workout),
                onClick = { onStart(workout) },
            )
            RowDivider()
        }
        // Jedan red za sve rasporede: s dva aktivna rasporeda red ispod svakog bio bi isti izbor dvaput.
        if (planned.isNotEmpty() && offersOtherWorkout) {
            StartRow(
                icon = Icons.AutoMirrored.Filled.List,
                prominent = false,
                title = stringResource(R.string.choose_other_workout),
                onClick = { onChooseTemplate(planned.map { it.schedule }) },
            )
            RowDivider()
        }
        if (offersTemplates) {
            StartRow(
                icon = Icons.AutoMirrored.Filled.List,
                prominent = true,
                title = stringResource(R.string.choose_workout),
                subtitle = pluralStringResource(R.plurals.saved_workouts, templateCount, templateCount),
                onClick = { onChooseTemplate(emptyList()) },
            )
            RowDivider()
        }
        if (planned.isEmpty() && !offersTemplates) {
            StartRow(Icons.Filled.PlayArrow, prominent = true, title = stringResource(R.string.start_workout), onClick = onStartEmpty)
        } else {
            StartRow(Icons.Filled.Add, prominent = false, title = stringResource(R.string.empty_workout), onClick = onStartEmpty)
        }
    }
}

/** Podnaslov sljedećeg treninga: raspored i broj vježbi, npr. "Push / Pull / Legs · 6 vježbi". */
@Composable
private fun plannedSubtitle(workout: PlannedWorkout): String {
    val count = workout.exercises.size
    if (count == 0) return workout.schedule.name
    return workout.schedule.name + " · " + pluralStringResource(R.plurals.exercise_count, count, count)
}

/** Razdjelnik između redova, uvučen do teksta kao na iOS-u (iza ikone u krugu). */
@Composable
private fun RowDivider() {
    HorizontalDivider(Modifier.padding(start = 70.dp), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f))
}

/** Red kartice za početak: ikona u krugu akcenta, naslov i (po potrebi) raspored, strelica desno. */
@Composable
private fun StartRow(
    icon: ImageVector,
    prominent: Boolean,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        leadingContent = {
            // Glavni način početka ima bijelu ikonu na punom akcentu, ostali akcent na blagom akcentu.
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(if (prominent) accent else accent.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = if (prominent) Color.White else accent)
            }
        },
        headlineContent = {
            Text(
                title,
                style = if (prominent) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge,
                fontWeight = if (prominent) FontWeight.SemiBold else null,
            )
        },
        supportingContent = subtitle?.let { { Text(it) } },
        trailingContent = {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        },
    )
}

/** Treninzi jednog aktivnog rasporeda u izboru, sa sljedećim označenim (`ScheduleChoices` na iOS-u). */
data class ScheduleChoices(val schedule: Schedule, val workouts: List<PlannedWorkout>, val nextItemId: UUID?)

/**
 * Izbor treninga (`TemplatePickerSheet`): uz rasporede njihovi treninzi, svaki raspored u svom odjeljku,
 * pa ostali spremljeni; bez rasporeda samo spremljeni.
 */
@Composable
fun TemplatePickerDialog(
    groups: List<ScheduleChoices>,
    templates: List<WorkoutTemplate>,
    onPlanned: (PlannedWorkout) -> Unit,
    onTemplate: (WorkoutTemplate) -> Unit,
    onDismiss: () -> Unit,
) {
    val inSchedules = groups.flatMap { group -> group.workouts.map { it.template.id } }.toSet()
    val others = templates.filter { it.id !in inSchedules }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.choose_workout)) },
        text = {
            Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState())) {
                groups.forEach { group ->
                    SectionLabel(group.schedule.name)
                    group.workouts.forEach { planned ->
                        PickerRow(
                            planned.template,
                            note = if (planned.item.id == group.nextItemId) stringResource(R.string.next_workout) else null,
                        ) { onPlanned(planned) }
                    }
                }
                if (groups.isNotEmpty() && others.isNotEmpty()) SectionLabel(stringResource(R.string.other_workouts))
                others.forEach { template -> PickerRow(template, note = null) { onTemplate(template) } }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
    )
}

@Composable
private fun PickerRow(template: WorkoutTemplate, note: String?, onClick: () -> Unit) {
    val count = template.exercises.size
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = { Text(template.name) },
        supportingContent = {
            val exercises = pluralStringResource(R.plurals.exercise_count, count, count)
            Text(if (note != null) "$note · $exercises" else exercises)
        },
    )
}

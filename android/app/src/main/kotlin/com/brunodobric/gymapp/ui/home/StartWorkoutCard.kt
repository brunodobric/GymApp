package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.planning.PlannedWorkout
import java.util.UUID

/**
 * Kartica za početak treninga (`StartWorkoutCard` na iOS-u). Svaki red je jedan način početka: sljedeći
 * trening svakog rasporeda, ispod njega izbor drugog treninga, i prazan trening. Bez aktivnog rasporeda,
 * a sa spremljenim treninzima, prvi red otvara njihov popis.
 */
@Composable
fun StartWorkoutCard(
    planned: List<PlannedWorkout>,
    templateCount: Int,
    offersOtherWorkout: (PlannedWorkout) -> Boolean,
    onStart: (PlannedWorkout) -> Unit,
    onChooseTemplate: (Schedule?) -> Unit,
    onStartEmpty: () -> Unit,
) {
    val offersTemplates = templateCount > 0 && planned.isEmpty()
    Card(Modifier.fillMaxWidth()) {
        planned.forEach { workout ->
            StartRow(
                icon = Icons.Filled.PlayArrow,
                prominent = true,
                title = stringResource(R.string.start_named, workout.template.name),
                subtitle = plannedSubtitle(workout),
                onClick = { onStart(workout) },
            )
            HorizontalDivider()
            if (offersOtherWorkout(workout)) {
                StartRow(
                    icon = Icons.AutoMirrored.Filled.List,
                    prominent = false,
                    title = stringResource(R.string.choose_other_workout),
                    onClick = { onChooseTemplate(workout.schedule) },
                )
                HorizontalDivider()
            }
        }
        if (offersTemplates) {
            StartRow(
                icon = Icons.AutoMirrored.Filled.List,
                prominent = true,
                title = stringResource(R.string.choose_workout),
                subtitle = pluralStringResource(R.plurals.saved_workouts, templateCount, templateCount),
                onClick = { onChooseTemplate(null) },
            )
            HorizontalDivider()
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

@Composable
private fun StartRow(
    icon: ImageVector,
    prominent: Boolean,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        leadingContent = {
            Icon(icon, contentDescription = null, tint = if (prominent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        },
        headlineContent = {
            Text(title, style = if (prominent) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge)
        },
        supportingContent = subtitle?.let { { Text(it) } },
    )
}

/** Izbor treninga (`TemplatePickerSheet`): s rasporedom njegovi treninzi pa ostali spremljeni, bez njega samo spremljeni. */
@Composable
fun TemplatePickerDialog(
    scheduled: List<PlannedWorkout>,
    nextItemId: UUID?,
    templates: List<WorkoutTemplate>,
    onPlanned: (PlannedWorkout) -> Unit,
    onTemplate: (WorkoutTemplate) -> Unit,
    onDismiss: () -> Unit,
) {
    val inSchedule = scheduled.map { it.template.id }.toSet()
    val others = templates.filter { it.id !in inSchedule }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.choose_workout)) },
        text = {
            Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState())) {
                if (scheduled.isNotEmpty()) {
                    SectionLabel(scheduled.first().schedule.name)
                    scheduled.forEach { planned ->
                        PickerRow(
                            planned.template,
                            note = if (planned.item.id == nextItemId) stringResource(R.string.next_workout) else null,
                        ) { onPlanned(planned) }
                    }
                    if (others.isNotEmpty()) SectionLabel(stringResource(R.string.other_workouts))
                }
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

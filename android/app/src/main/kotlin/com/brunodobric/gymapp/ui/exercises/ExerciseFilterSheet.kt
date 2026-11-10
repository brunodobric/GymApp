package com.brunodobric.gymapp.ui.exercises

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseFilter
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.Muscle

/**
 * Filteri popisa vježbi (`ExerciseFilterSheet` na iOS-u): izvor, arhivirane, kategorija, oprema i mišić.
 * "Poništi filtere" vraća početni filter ([base]) i zadržava upit.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExerciseFilterSheet(
    filter: ExerciseFilter,
    onChange: (ExerciseFilter) -> Unit,
    onDismiss: () -> Unit,
    base: ExerciseFilter = ExerciseFilter(),
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        LazyColumn {
            item {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.filters), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    if (filter.differs(base)) {
                        TextButton(onClick = { onChange(filter.reset(base)) }) { Text(stringResource(R.string.reset_filters)) }
                    }
                    TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
                }
            }
            item { SectionTitle(stringResource(R.string.filter_source)) }
            item {
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ExerciseFilter.Origin.entries.forEach { origin ->
                        FilterChip(
                            selected = filter.origin == origin,
                            onClick = { onChange(filter.copy(origin = origin)) },
                            label = { Text(stringResource(originTitle(origin))) },
                        )
                    }
                }
            }
            item {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.show_archived)) },
                    trailingContent = {
                        Switch(checked = filter.includeArchived, onCheckedChange = { onChange(filter.copy(includeArchived = it)) })
                    },
                )
            }
            item { SectionTitle(stringResource(R.string.exercise_category)) }
            items(ExerciseCategory.entries.size) { index ->
                val category = ExerciseCategory.entries[index]
                SelectionRow(stringResource(categoryTitle(category)), category in filter.categories) {
                    onChange(filter.copy(categories = filter.categories.toggled(category)))
                }
            }
            item { SectionTitle(stringResource(R.string.exercise_equipment)) }
            items(Equipment.entries.size) { index ->
                val equipment = Equipment.entries[index]
                SelectionRow(stringResource(equipmentTitle(equipment)), equipment in filter.equipment) {
                    onChange(filter.copy(equipment = filter.equipment.toggled(equipment)))
                }
            }
            item { SectionTitle(stringResource(R.string.filter_muscle)) }
            items(Muscle.entries.size) { index ->
                val muscle = Muscle.entries[index]
                SelectionRow(stringResource(muscleTitle(muscle)), muscle in filter.muscles) {
                    onChange(filter.copy(muscles = filter.muscles.toggled(muscle)))
                }
            }
        }
    }
}

/** Broj aktivnih filtera iz lista (bez upita i vrste), za oznaku na gumbu. */
internal fun ExerciseFilter.activeCount(): Int =
    categories.size + muscles.size + equipment.size +
        (if (origin != ExerciseFilter.Origin.ALL) 1 else 0) + (if (includeArchived) 1 else 0)

private fun originTitle(origin: ExerciseFilter.Origin): Int = when (origin) {
    ExerciseFilter.Origin.ALL -> R.string.filter_all
    ExerciseFilter.Origin.OFFICIAL -> R.string.filter_official
    ExerciseFilter.Origin.CUSTOM -> R.string.filter_custom
}

private fun <T> Set<T>.toggled(value: T): Set<T> = if (value in this) this - value else this + value

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun SelectionRow(title: String, selected: Boolean, onToggle: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        leadingContent = { Checkbox(checked = selected, onCheckedChange = { onToggle() }) },
        modifier = Modifier.clickable(onClick = onToggle),
    )
}

/** Čuva filter kroz rotaciju i povratak na ekran: skupovi se spremaju kao sirove vrijednosti. */
internal val ExerciseFilterSaver = listSaver<ExerciseFilter, String>(
    save = { filter ->
        listOf(
            filter.query,
            filter.origin.name,
            filter.includeArchived.toString(),
            filter.kinds.joinToString(",") { it.raw },
            filter.categories.joinToString(",") { it.raw },
            filter.muscles.joinToString(",") { it.raw },
            filter.equipment.joinToString(",") { it.raw },
        )
    },
    restore = { values ->
        fun raws(index: Int): Set<String> = values[index].split(",").filter { it.isNotEmpty() }.toSet()
        ExerciseFilter(
            query = values[0],
            origin = ExerciseFilter.Origin.entries.firstOrNull { it.name == values[1] } ?: ExerciseFilter.Origin.ALL,
            includeArchived = values[2].toBoolean(),
            kinds = ExerciseKind.entries.filter { it.raw in raws(3) }.toSet(),
            categories = ExerciseCategory.entries.filter { it.raw in raws(4) }.toSet(),
            muscles = Muscle.entries.filter { it.raw in raws(5) }.toSet(),
            equipment = Equipment.entries.filter { it.raw in raws(6) }.toSet(),
        )
    },
)

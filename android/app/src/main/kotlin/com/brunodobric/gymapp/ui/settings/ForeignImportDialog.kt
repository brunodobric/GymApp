package com.brunodobric.gymapp.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Person
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.backup.ForeignWorkoutImport
import java.text.NumberFormat
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Pregled prije uvoza treninga iz druge aplikacije, kao `ForeignImportSheet` na iOS-u: koliko je novih
 * treninga, razdoblje i serije, te za svaku vježbu iz datoteke kamo ide (katalog, vlastita ili nova vlastita).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ForeignImportDialog(preview: ForeignWorkoutImport.Preview, onImport: () -> Unit, onDismiss: () -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    val numbers = remember(locale) { NumberFormat.getIntegerInstance(locale) }
    val dates = remember(locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(ZoneId.systemDefault())
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.foreign_import_title)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel))
                        }
                    },
                    actions = {
                        TextButton(enabled = preview.newWorkouts.isNotEmpty(), onClick = onImport) {
                            Text(stringResource(R.string.import_action))
                        }
                    },
                )
            },
        ) { padding ->
            LazyColumn(Modifier.padding(padding).fillMaxSize()) {
                item { Header(stringResource(R.string.import_workouts_header)) }
                item { Value(stringResource(R.string.import_new_workouts), numbers.format(preview.newWorkouts.size)) }
                if (preview.alreadyImported > 0) {
                    item { Value(stringResource(R.string.import_already_imported), numbers.format(preview.alreadyImported)) }
                }
                val first = preview.firstDate
                val last = preview.lastDate
                if (first != null && last != null) {
                    val period = if (dates.format(first) == dates.format(last)) {
                        dates.format(first)
                    } else {
                        dates.format(first) + " – " + dates.format(last)
                    }
                    item { Value(stringResource(R.string.import_period), period) }
                }
                item { Value(stringResource(R.string.import_sets), numbers.format(preview.setCount)) }
                if (preview.newWorkouts.isEmpty()) {
                    item { Footer(stringResource(R.string.import_all_imported)) }
                }
                if (preview.exercises.isNotEmpty()) {
                    item { Header(stringResource(R.string.import_exercises_header)) }
                    items(preview.exercises, key = { it.id }) { mapping ->
                        MappingRow(mapping)
                        HorizontalDivider()
                    }
                    item { Footer(stringResource(R.string.import_exercises_footer)) }
                }
            }
        }
    }
}

@Composable
private fun Value(label: String, value: String) {
    ListItem(
        headlineContent = { Text(label) },
        trailingContent = { Text(value, style = MaterialTheme.typography.bodyLarge) },
    )
}

/** Vježba iz datoteke (naziv i oprema) i vježba u koju se uvozi. */
@Composable
private fun MappingRow(mapping: ForeignWorkoutImport.ExerciseMapping) {
    ListItem(
        headlineContent = { Text(mapping.sourceName) },
        supportingContent = {
            Column {
                if (mapping.sourceEquipment.isNotEmpty()) Text(mapping.sourceEquipment)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val target = mapping.target
                    when (target) {
                        is ForeignWorkoutImport.Target.Catalog ->
                            Icon(painterResource(R.drawable.ic_kind_strength), contentDescription = null, Modifier.padding(end = 6.dp).size(16.dp))
                        is ForeignWorkoutImport.Target.ExistingCustom ->
                            Icon(Icons.Filled.Person, contentDescription = null, Modifier.padding(end = 6.dp).size(16.dp))
                        is ForeignWorkoutImport.Target.NewCustom ->
                            Icon(Icons.Filled.Add, contentDescription = null, Modifier.padding(end = 6.dp).size(16.dp))
                    }
                    Text(
                        if (target is ForeignWorkoutImport.Target.NewCustom) stringResource(R.string.import_new_custom) else target.name,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        },
    )
}

@Composable
private fun Header(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun Footer(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

package com.brunodobric.gymapp.ui.statistics

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
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
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.stats.RecordEntry
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecord
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightFormatter
import com.brunodobric.gymapp.units.WeightUnit
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Naziv vrste rekorda, isti kao na iOS-u. */
internal fun prKindTitle(kind: PRKind): Int = when (kind) {
    PRKind.ESTIMATED_ONE_REP_MAX -> R.string.estimated_one_rep_max
    PRKind.REP_MAX -> R.string.pr_rep_max
    PRKind.MAX_WEIGHT -> R.string.heaviest_weight
    PRKind.EXERCISE_VOLUME -> R.string.pr_exercise_volume
    PRKind.MAX_REPS -> R.string.pr_max_reps
    PRKind.LOWEST_ASSISTANCE -> R.string.pr_lowest_assistance
    PRKind.LONGEST_DURATION -> R.string.pr_longest_duration
    PRKind.LONGEST_DISTANCE -> R.string.pr_longest_distance
}

/** Vrijednost rekorda za prikaz: težina, "80 kg × 5", ponavljanja, trajanje ili udaljenost. */
@Composable
internal fun recordValue(record: PersonalRecord, weight: WeightFormatter): String = when (record.kind) {
    PRKind.ESTIMATED_ONE_REP_MAX, PRKind.MAX_WEIGHT, PRKind.EXERCISE_VOLUME, PRKind.LOWEST_ASSISTANCE ->
        weight.string(record.value)
    PRKind.REP_MAX -> "${weight.string(record.value)} × ${record.reps ?: 1}"
    PRKind.MAX_REPS -> stringResource(R.string.reps_short, record.value.toInt())
    PRKind.LONGEST_DURATION -> DurationInput.format(record.value.toInt())
    PRKind.LONGEST_DISTANCE ->
        if (record.value >= 1000) "${NumberInput.format(record.value / 1000)} km" else "${record.value.toInt()} m"
}

@Composable
private fun RecordRow(entry: RecordEntry, weight: WeightFormatter, dates: DateTimeFormatter) {
    ListItem(
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = { Text(entry.exerciseName) },
        supportingContent = { Text(stringResource(prKindTitle(entry.record.kind)) + " · " + dates.format(entry.date)) },
        trailingContent = { Text(recordValue(entry.record, weight), style = MaterialTheme.typography.titleSmall) },
    )
}

@Composable
private fun rememberRecordFormats(unit: WeightUnit): Pair<WeightFormatter, DateTimeFormatter> {
    val locale = LocalConfiguration.current.locales[0]
    val weight = remember(unit, locale) { WeightFormatter(unit, locale) }
    val dates = remember(locale) {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(ZoneId.systemDefault())
    }
    return weight to dates
}

/** Kartica u Statistici: tri najnovija rekorda i ulaz u sve rekorde. */
@Composable
internal fun RecordsCard(records: List<RecordEntry>, unit: WeightUnit, onShowAll: () -> Unit) {
    val (weight, dates) = rememberRecordFormats(unit)
    Text(stringResource(R.string.personal_records), style = MaterialTheme.typography.titleMedium)
    Card(Modifier.fillMaxWidth()) {
        if (records.isEmpty()) {
            Text(
                stringResource(R.string.records_empty),
                modifier = Modifier.padding(16.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        records.take(3).forEach { RecordRow(it, weight, dates) }
        if (records.isNotEmpty()) {
            HorizontalDivider()
            ListItem(
                modifier = Modifier.clickable(onClick = onShowAll),
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                headlineContent = { Text(stringResource(R.string.all_records), color = MaterialTheme.colorScheme.primary) },
            )
        }
    }
}

/** Svi rekordi, od najnovijeg, s pretragom po vježbi i filtrom po vrsti. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RecordsScreen(records: List<RecordEntry>, unit: WeightUnit, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val (weight, dates) = rememberRecordFormats(unit)
    var search by rememberSaveable { mutableStateOf("") }
    var kindsRaw by rememberSaveable { mutableStateOf(listOf<String>()) }
    val kinds = PRKind.entries.filter { it.raw in kindsRaw }.toSet()
    val shownKinds = PRKind.entries.filter { kind -> records.any { it.record.kind == kind } }
    val filtered = records.filter { entry ->
        (kinds.isEmpty() || entry.record.kind in kinds) &&
            (search.isBlank() || entry.exerciseName.contains(search.trim(), ignoreCase = true))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.records)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            item {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = search,
                        onValueChange = { search = it },
                        label = { Text(stringResource(R.string.exercise)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        shownKinds.forEach { kind ->
                            FilterChip(
                                selected = kind in kinds,
                                onClick = { kindsRaw = if (kind.raw in kindsRaw) kindsRaw - kind.raw else kindsRaw + kind.raw },
                                label = { Text(stringResource(prKindTitle(kind))) },
                            )
                        }
                    }
                }
            }
            if (filtered.isEmpty()) {
                item {
                    Text(
                        stringResource(R.string.records_no_match),
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            itemsIndexed(filtered) { _, entry -> RecordRow(entry, weight, dates) }
        }
    }
}

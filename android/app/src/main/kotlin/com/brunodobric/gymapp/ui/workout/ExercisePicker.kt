package com.brunodobric.gymapp.ui.workout

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseFilter
import com.brunodobric.gymapp.catalog.ExerciseSearch
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.exercises.ExerciseRowThumbnail
import com.brunodobric.gymapp.ui.exercises.MoveKitAssets
import com.brunodobric.gymapp.ui.exercises.categoryTitle
import com.brunodobric.gymapp.ui.exercises.equipmentTitle
import com.brunodobric.gymapp.ui.rememberStoreRevision

/**
 * Odabir vježbe za trening: katalog i vlastite vježbe s pretragom i filterom dijela tijela, kao
 * `ExercisePickerSheet` na iOS-u. Bez upita na vrhu su prijedlozi ([suggested], zamjena vježbe) i nedavne
 * vježbe ([recentKeys]). S [allowsMultiple] se odabire više vježbi, a [onPick] se zove za svaku redom odabira.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExercisePicker(
    services: AppServices,
    onPick: (ExerciseSummary) -> Unit,
    onClose: () -> Unit,
    title: String = stringResource(R.string.add_exercise),
    allowsMultiple: Boolean = false,
    suggested: List<ExerciseSummary> = emptyList(),
    recentKeys: List<String> = emptyList(),
    excludedKeys: Set<String> = emptySet(),
) {
    val language = catalogLanguage()
    val context = LocalContext.current
    val revision = rememberStoreRevision(services.store)
    val catalog = remember(language) { services.catalog.summaries(language) }
    val summaries = remember(revision, catalog) { services.store.customExercises.map { it.summary } + catalog }
    var query by rememberSaveable { mutableStateOf("") }
    var categories by rememberSaveable { mutableStateOf(listOf<String>()) }
    var selected by rememberSaveable { mutableStateOf(listOf<String>()) }
    val chosen = categories.mapNotNull { raw -> ExerciseCategory.entries.firstOrNull { it.raw == raw } }.toSet()
    val results = remember(query, chosen, summaries) {
        ExerciseSearch.apply(ExerciseFilter(query = query, categories = chosen), summaries)
    }
    val showsShortcuts = query.isEmpty() && chosen.isEmpty()
    val suggestions = if (showsShortcuts) suggested else emptyList()
    val recent = if (showsShortcuts) {
        ExerciseSearch.recent(recentKeys, summaries, excludedKeys + suggestions.map { it.id })
    } else {
        emptyList()
    }

    @Composable
    fun PickerRow(item: ExerciseSummary) {
        val source = item.source
        val poster = if (source is ExerciseSummary.Source.Catalog) {
            MoveKitAssets.posterPath(context, services.catalog.exercise(source.id))
        } else {
            null
        }
        val isSelected = item.id in selected
        val details = listOfNotNull(
            item.category?.let { stringResource(categoryTitle(it)) },
            item.equipment?.let { stringResource(equipmentTitle(it)) },
        ).joinToString(" · ")
        ListItem(
            leadingContent = { ExerciseRowThumbnail(item.name, poster, size = 48.dp) },
            headlineContent = { Text(item.name) },
            supportingContent = if (details.isEmpty()) null else ({ Text(details) }),
            trailingContent = if (allowsMultiple) ({ Checkbox(checked = isSelected, onCheckedChange = null) }) else null,
            modifier = Modifier.clickable {
                if (allowsMultiple) {
                    selected = if (isSelected) selected - item.id else selected + item.id
                } else {
                    onPick(item)
                }
            },
        )
        HorizontalDivider()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                    }
                },
                actions = {
                    if (allowsMultiple) {
                        TextButton(
                            enabled = selected.isNotEmpty(),
                            onClick = {
                                val byId = summaries.associateBy { it.id }
                                selected.mapNotNull { byId[it] }.forEach(onPick)
                                onClose()
                            },
                        ) { Text(stringResource(R.string.add_count, selected.size)) }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text(stringResource(R.string.search_exercises)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            )
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(ExerciseCategory.entries.toList(), key = { it.raw }) { category ->
                    val isOn = category in chosen
                    FilterChip(
                        selected = isOn,
                        onClick = { categories = if (isOn) categories - category.raw else categories + category.raw },
                        label = { Text(stringResource(categoryTitle(category))) },
                    )
                }
            }
            LazyColumn {
                if (suggestions.isNotEmpty()) {
                    item(key = "h:suggested") { SectionHeader(stringResource(R.string.suggestions)) }
                    items(suggestions, key = { "s:" + it.id }) { PickerRow(it) }
                }
                if (recent.isNotEmpty()) {
                    item(key = "h:recent") { SectionHeader(stringResource(R.string.recent)) }
                    items(recent, key = { "r:" + it.id }) { PickerRow(it) }
                }
                if (suggestions.isNotEmpty() || recent.isNotEmpty()) {
                    item(key = "h:all") { SectionHeader(stringResource(R.string.all_exercises)) }
                }
                items(results, key = { it.id }) { PickerRow(it) }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

/** Vrsta unosa odabrane vježbe: iz kataloga ili iz vlastite vježbe. */
internal fun inputTypeOf(services: AppServices, summary: ExerciseSummary): ExerciseInputType = when (val source = summary.source) {
    is ExerciseSummary.Source.Catalog -> services.catalog.exercise(source.id)?.inputType
    is ExerciseSummary.Source.Custom -> services.store.customExercise(source.id)?.inputType
} ?: ExerciseInputType.WEIGHT_REPS

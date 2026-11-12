package com.brunodobric.gymapp.ui.workout

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseFilter
import com.brunodobric.gymapp.catalog.ExerciseSearch
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.exercises.ExerciseRowThumbnail
import com.brunodobric.gymapp.ui.exercises.MoveKitAssets
import com.brunodobric.gymapp.ui.rememberStoreRevision

/** Odabir vježbe za trening: katalog s pretragom. Vlastite vježbe i filteri dolaze s tabom Vježbe. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExercisePicker(
    services: AppServices,
    onPick: (ExerciseSummary) -> Unit,
    onClose: () -> Unit,
    title: String = stringResource(R.string.add_exercise),
) {
    val language = catalogLanguage()
    val context = LocalContext.current
    val revision = rememberStoreRevision(services.store)
    val catalog = remember(language) { services.catalog.summaries(language) }
    val summaries = remember(revision, catalog) { services.store.customExercises.map { it.summary } + catalog }
    var query by rememberSaveable { mutableStateOf("") }
    val results = remember(query, summaries) { ExerciseSearch.apply(ExerciseFilter(query = query), summaries) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
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
            LazyColumn {
                items(results, key = { it.id }) { item ->
                    val source = item.source
                    val poster = if (source is ExerciseSummary.Source.Catalog) {
                        MoveKitAssets.posterPath(context, services.catalog.exercise(source.id))
                    } else {
                        null
                    }
                    ListItem(
                        leadingContent = { ExerciseRowThumbnail(item.name, poster, size = 48.dp) },
                        headlineContent = { Text(item.name) },
                        modifier = Modifier.clickable { onPick(item) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

/** Vrsta unosa odabrane vježbe: iz kataloga ili iz vlastite vježbe. */
internal fun inputTypeOf(services: AppServices, summary: ExerciseSummary): ExerciseInputType = when (val source = summary.source) {
    is ExerciseSummary.Source.Catalog -> services.catalog.exercise(source.id)?.inputType
    is ExerciseSummary.Source.Custom -> services.store.customExercise(source.id)?.inputType
} ?: ExerciseInputType.WEIGHT_REPS

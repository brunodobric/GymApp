package com.brunodobric.gymapp.ui.exercises

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseFilter
import com.brunodobric.gymapp.catalog.ExerciseSearch
import com.brunodobric.gymapp.catalog.ExerciseSummary
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.rememberStoreRevision
import java.util.UUID

/** Uređivač otvoren s popisa: nova vježba ili postojeća vlastita vježba. */
private const val NEW_EXERCISE = "new"

/**
 * Popis vježbi kataloga i vlastitih vježbi s pretragom i filterom "Moje vježbe". Vlastita vježba se otvara
 * u uređivaču. Kartice vrsta, filteri po mišićima i detalj vježbe kataloga dolaze kasnije.
 */
@Composable
fun ExercisesScreen(services: AppServices) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val language = catalogLanguage()
    val catalog = remember(language) { services.catalog.summaries(language) }
    var query by rememberSaveable { mutableStateOf("") }
    var onlyCustom by rememberSaveable { mutableStateOf(false) }
    var editing by rememberSaveable { mutableStateOf<String?>(null) }

    editing?.let { target ->
        CustomExerciseEditorScreen(
            services = services,
            exerciseId = if (target == NEW_EXERCISE) null else UUID.fromString(target),
            onClose = { editing = null },
        )
        return
    }

    val summaries = remember(revision, catalog) { store.customExercises.map { it.summary } + catalog }
    val filter = ExerciseFilter(query = query, origin = if (onlyCustom) ExerciseFilter.Origin.CUSTOM else ExerciseFilter.Origin.ALL)
    val results = remember(filter, summaries) { ExerciseSearch.apply(filter, summaries) }

    Box(Modifier.fillMaxSize()) {
        Column {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text(stringResource(R.string.search_exercises)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            )
            FilterChip(
                selected = onlyCustom,
                onClick = { onlyCustom = !onlyCustom },
                label = { Text(stringResource(R.string.my_exercises)) },
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            if (results.isEmpty()) {
                ListItem(headlineContent = { Text(stringResource(R.string.no_results)) })
            }
            LazyColumn {
                items(results, key = { it.id }) { item ->
                    val custom = item.source as? ExerciseSummary.Source.Custom
                    val category = item.category
                    ListItem(
                        headlineContent = { Text(item.name) },
                        supportingContent = if (category != null) {
                            { Text(stringResource(categoryTitle(category))) }
                        } else {
                            null
                        },
                        modifier = if (custom != null) Modifier.clickable { editing = custom.id.toString() } else Modifier,
                    )
                    HorizontalDivider()
                }
            }
        }
        ExtendedFloatingActionButton(
            onClick = { editing = NEW_EXERCISE },
            icon = { Icon(Icons.Filled.Add, contentDescription = null) },
            text = { Text(stringResource(R.string.custom_exercise_new)) },
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
        )
    }
}

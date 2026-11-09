package com.brunodobric.gymapp.ui.exercises

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseFilter
import com.brunodobric.gymapp.catalog.ExerciseSearch

/** Popis vježbi kataloga s pretragom. Prvi korak taba Vježbe; kartice vrsta i filteri dolaze u fazi 3. */
@Composable
fun ExercisesScreen(services: AppServices) {
    val language = LocalConfiguration.current.locales[0].language.let { if (it == "hr") "hr" else "en" }
    val summaries = remember(language) { services.catalog.summaries(language) }
    var query by rememberSaveable { mutableStateOf("") }
    val results = remember(query, summaries) { ExerciseSearch.apply(ExerciseFilter(query = query), summaries) }

    Column {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            placeholder = { Text(stringResource(R.string.search_exercises)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        )
        if (results.isEmpty()) {
            ListItem(headlineContent = { Text(stringResource(R.string.no_results)) })
        }
        LazyColumn {
            items(results, key = { it.id }) { item ->
                ListItem(headlineContent = { Text(item.name) })
                HorizontalDivider()
            }
        }
    }
}

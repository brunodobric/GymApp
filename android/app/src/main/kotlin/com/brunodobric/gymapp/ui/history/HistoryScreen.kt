package com.brunodobric.gymapp.ui.history

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.OpenRequest
import com.brunodobric.gymapp.stats.HistoryFilter
import com.brunodobric.gymapp.stats.HistoryQueries
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.DurationInput
import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

/**
 * Povijest: završeni treninzi od najnovijeg, s pretragom po nazivu treninga i vježbama ([HistoryFilter.query]).
 * Dodir otvara detalj; filteri i kalendar dolaze kasnije.
 */
@Composable
fun HistoryScreen(services: AppServices, openRequest: OpenRequest? = null, onRequestHandled: () -> Unit = {}) {
    var openedId by rememberSaveable { mutableStateOf<String?>(null) }
    // Dodir na widget (zadnji trening ili trening s rekordom) otvara detalj treninga.
    LaunchedEffect(openRequest) {
        openRequest?.let {
            openedId = it.value
            onRequestHandled()
        }
    }
    openedId?.let { id ->
        SessionDetailScreen(services, UUID.fromString(id), onClose = { openedId = null })
        return
    }
    val revision = rememberStoreRevision(services.store)
    val sessions = remember(revision) { HistoryQueries(services.store).sessions() }
    var query by rememberSaveable { mutableStateOf("") }
    val listed = remember(sessions, query) { HistoryFilter(query = query.trim()).apply(sessions) }
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(locale) {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale)
            .withZone(ZoneId.systemDefault())
    }

    if (sessions.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.history_empty), style = MaterialTheme.typography.bodyLarge)
        }
        return
    }
    Column {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            placeholder = { Text(stringResource(R.string.history_search)) },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        )
        if (listed.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.history_no_match), style = MaterialTheme.typography.bodyLarge)
            }
            return@Column
        }
        LazyColumn {
            items(listed, key = { it.id.toString() }) { session ->
                val sets = session.exercises.sumOf { exercise -> exercise.sets.count { it.isCompleted } }
                val seconds = session.endedAt?.let { Duration.between(session.startedAt, it).seconds.toInt() } ?: 0
                ListItem(
                    modifier = Modifier.clickable { openedId = session.id.toString() },
                    headlineContent = { Text(session.name) },
                    supportingContent = {
                        // Uvezeni kardio trening nema serija: umjesto njih piše odakle je.
                        val detail = if (session.isImportedFromWorkoutsApp) {
                            stringResource(R.string.from_health_connect)
                        } else {
                            pluralStringResource(R.plurals.completed_sets, sets, sets)
                        }
                        Text(formatter.format(session.startedAt) + " · " + DurationInput.format(seconds) + " · " + detail)
                    },
                )
                HorizontalDivider()
            }
        }
    }
}

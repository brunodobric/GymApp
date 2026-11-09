package com.brunodobric.gymapp.ui.history

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.stats.HistoryQueries
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.DurationInput
import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Povijest, prvi korak: završeni treninzi od najnovijeg. Filteri, kalendar i detalj dolaze kasnije. */
@Composable
fun HistoryScreen(services: AppServices) {
    val revision = rememberStoreRevision(services.store)
    val sessions = remember(revision) { HistoryQueries(services.store).sessions() }
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
    LazyColumn {
        items(sessions, key = { it.id.toString() }) { session ->
            val sets = session.exercises.sumOf { exercise -> exercise.sets.count { it.isCompleted } }
            val seconds = session.endedAt?.let { Duration.between(session.startedAt, it).seconds.toInt() } ?: 0
            ListItem(
                headlineContent = { Text(session.name) },
                supportingContent = {
                    Text(
                        formatter.format(session.startedAt) + " · " + DurationInput.format(seconds) + " · " +
                            pluralStringResource(R.plurals.completed_sets, sets, sets),
                    )
                },
            )
            HorizontalDivider()
        }
    }
}

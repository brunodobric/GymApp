package com.brunodobric.gymapp.ui.history

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.FilterChip
import androidx.compose.material3.IconButton
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.HistorySort
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.training.SessionCardio
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.ui.MonthCalendar
import com.brunodobric.gymapp.ui.MonthHeader
import java.time.LocalDate
import java.time.YearMonth
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
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.ui.TabScaffold
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
 * Povijest: završeni treninzi s pretragom po nazivu treninga i vježbama ([HistoryFilter.query]), filterom po
 * vrsti (snaga, kardio) i redoslijedom, kao na iOS-u. Gumb u traci prebacuje na kalendar mjeseca s točkicama
 * na danima s treningom; ispod kalendara su treninzi mjeseca ili odabranog dana. Dodir otvara detalj.
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
    val locale = LocalConfiguration.current.locales[0]
    val calendar = remember(locale) { StatsCalendar.system(locale) }
    val sessions = remember(revision) { HistoryQueries(services.store).sessions() }
    val isCardio = remember(revision) {
        ExerciseInfoBuilder.isCardio(ExerciseInfoBuilder.provider(services.catalog, services.store.customExercises))
    }
    // Vrsta treninga iz vježbi: trening snage s kardiom je i pod snagom i pod kardiom (`SessionMix.kinds`).
    val mixes = remember(sessions, isCardio) { sessions.associate { it.id to SessionCardio.mix(it, isCardio) } }
    var query by rememberSaveable { mutableStateOf("") }
    var kindsRaw by rememberSaveable { mutableStateOf(listOf<String>()) }
    var oldestFirst by rememberSaveable { mutableStateOf(false) }
    var showsCalendar by rememberSaveable { mutableStateOf(false) }
    var monthText by rememberSaveable { mutableStateOf(YearMonth.now(calendar.zone).toString()) }
    var selectedDayText by rememberSaveable { mutableStateOf<String?>(null) }
    val month = YearMonth.parse(monthText)
    val selectedDay = selectedDayText?.let(LocalDate::parse)
    val kinds = WorkoutKind.entries.filter { it.name in kindsRaw }.toSet()
    val filter = HistoryFilter(kinds = kinds, sort = if (oldestFirst) HistorySort.OLDEST_FIRST else HistorySort.NEWEST_FIRST, query = query.trim())
    val kindsOf: (Session) -> Set<WorkoutKind> = { session -> mixes[session.id]?.kinds ?: setOf(session.kind) }
    val visible = remember(sessions, filter, mixes) { filter.apply(sessions, kindsOf) }
    val listed = remember(visible, showsCalendar, month, selectedDay) {
        if (!showsCalendar) {
            visible
        } else {
            val day = selectedDay ?: month.atDay(1)
            val interval = if (selectedDay != null) calendar.dayInterval(calendar.startOfDay(day)) else calendar.monthInterval(calendar.startOfDay(day))
            visible.filter { it.startedAt >= interval.start && it.startedAt < interval.end }
        }
    }
    val workoutDays = remember(visible, calendar) { visible.map { calendar.date(it.startedAt) }.toSet() }
    val formatter = remember(locale) {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale)
            .withZone(ZoneId.systemDefault())
    }

    TabScaffold(
        stringResource(R.string.tab_history),
        actions = {
            if (sessions.isNotEmpty()) {
                IconButton(onClick = {
                    showsCalendar = !showsCalendar
                    if (!showsCalendar) selectedDayText = null
                }) {
                    if (showsCalendar) {
                        Icon(Icons.AutoMirrored.Filled.List, contentDescription = stringResource(R.string.history_list))
                    } else {
                        Icon(Icons.Filled.DateRange, contentDescription = stringResource(R.string.history_calendar))
                    }
                }
            }
        },
    ) { padding ->
        if (sessions.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.history_empty), style = MaterialTheme.typography.bodyLarge)
            }
            return@TabScaffold
        }
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            item(key = "search") {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    placeholder = { Text(stringResource(R.string.history_search)) },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                )
            }
            item(key = "filters") {
                Row(
                    Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    WorkoutKind.entries.forEach { kind ->
                        FilterChip(
                            selected = kind in kinds,
                            onClick = { kindsRaw = if (kind.name in kindsRaw) kindsRaw - kind.name else kindsRaw + kind.name },
                            label = { Text(stringResource(workoutKindTitle(kind))) },
                        )
                    }
                    FilterChip(
                        selected = oldestFirst,
                        onClick = { oldestFirst = !oldestFirst },
                        label = { Text(stringResource(if (oldestFirst) R.string.history_oldest_first else R.string.history_newest_first)) },
                    )
                }
            }
            if (showsCalendar) {
                item(key = "calendar") {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                        MonthHeader(month, onShift = { step ->
                            monthText = month.plusMonths(step.toLong()).toString()
                            selectedDayText = null
                        })
                        MonthCalendar(
                            month = month,
                            firstDayOfWeek = calendar.firstDayOfWeek,
                            hasWorkout = { it in workoutDays },
                            selected = selectedDay,
                            onSelect = { selectedDayText = it?.toString() },
                        )
                    }
                    HorizontalDivider()
                }
            }
            if (listed.isEmpty()) {
                item(key = "empty") {
                    val text = when {
                        !showsCalendar && query.isNotBlank() && kinds.isEmpty() -> R.string.history_no_match
                        !showsCalendar -> R.string.history_no_filter_match
                        selectedDay == null -> R.string.history_month_empty
                        else -> R.string.history_day_empty
                    }
                    Text(
                        stringResource(text),
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            items(listed, key = { it.id.toString() }) { session ->
                SessionRow(session, mixes[session.id], isCardio, formatter, onOpen = { openedId = session.id.toString() })
                HorizontalDivider()
            }
        }
    }
}

/** Naziv vrste treninga u filteru (Snaga, Kardio). */
internal fun workoutKindTitle(kind: WorkoutKind): Int = when (kind) {
    WorkoutKind.STRENGTH -> R.string.kind_strength
    WorkoutKind.CARDIO -> R.string.kind_cardio
}

@Composable
private fun SessionRow(
    session: Session,
    mix: SessionMix?,
    isCardio: (String) -> Boolean,
    formatter: DateTimeFormatter,
    onOpen: () -> Unit,
) {
    val sets = session.exercises.sumOf { exercise -> exercise.sets.count { it.isCompleted } }
    val seconds = session.endedAt?.let { Duration.between(session.startedAt, it).seconds.toInt() } ?: 0
    ListItem(
        modifier = Modifier.clickable(onClick = onOpen),
        headlineContent = { Text(session.name) },
        supportingContent = {
            Column {
                // Uvezeni kardio trening nema serija: umjesto njih piše odakle je.
                val detail = if (session.isImportedFromWorkoutsApp) {
                    stringResource(R.string.from_health_connect)
                } else {
                    pluralStringResource(R.plurals.completed_sets, sets, sets)
                }
                Text(formatter.format(session.startedAt) + " · " + DurationInput.format(seconds) + " · " + detail)
                // Trening snage s kardio vježbama: kardio dio u drugom retku, kao na iOS-u.
                if (mix == SessionMix.MIXED) {
                    SessionCardio.part(session, isCardio)?.let { part ->
                        val minutes = Math.round(part.seconds / 60.0).toInt()
                        Text(if (minutes > 0) stringResource(R.string.history_cardio_part, minutes) else stringResource(R.string.kind_cardio))
                    }
                }
            }
        },
    )
}

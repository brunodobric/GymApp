package com.brunodobric.gymapp.ui.statistics

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.StatsDetail
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.FrequencyPoint
import com.brunodobric.gymapp.stats.OverviewNavigation
import com.brunodobric.gymapp.stats.OverviewPeriod
import com.brunodobric.gymapp.stats.PeriodChange
import com.brunodobric.gymapp.stats.PeriodSummary
import com.brunodobric.gymapp.stats.RecordEntry
import com.brunodobric.gymapp.stats.RegionLoad
import com.brunodobric.gymapp.stats.SessionFigures
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.stats.VolumeComparison
import com.brunodobric.gymapp.stats.WeekProgress
import com.brunodobric.gymapp.stats.periodSummary
import com.brunodobric.gymapp.stats.periodVolume
import com.brunodobric.gymapp.stats.sessions
import com.brunodobric.gymapp.training.CardioText
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.ui.MonthCalendar
import com.brunodobric.gymapp.ui.history.SessionDetailScreen
import com.brunodobric.gymapp.ui.home.PeriodFigures
import com.brunodobric.gymapp.ui.home.WeekDaysStrip
import com.brunodobric.gymapp.ui.home.WeekHeader
import com.brunodobric.gymapp.ui.home.durationText
import com.brunodobric.gymapp.ui.home.perWeekText
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.NumberInput
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID

/** Sve što ekran Pregled prikazuje, učitano odjednom (`OverviewData` na iOS-u). */
private class OverviewData(
    val summary: PeriodSummary,
    val previous: PeriodSummary?,
    /** Treninzi po danu (ključ je početak dana), svaki dan od ranijeg prema kasnijem. */
    val days: Map<Instant, List<Session>>,
    val figures: Map<UUID, SessionFigures>,
    val comparison: VolumeComparison?,
    val heatmap: Map<String, RegionLoad>,
    /** Rekordi postavljeni u razdoblju, od najnovijeg. */
    val records: List<RecordEntry>,
) {
    fun sessions(day: Instant): List<Session> = days[day].orEmpty()

    /** Broj rekorda postavljenih u treningu (rekord nosi početak svog treninga). */
    fun recordCount(session: Session): Int = records.count { it.date == session.startedAt }
}

/**
 * Pregled tjedna, mjeseca ili godine, kao `OverviewScreen` na iOS-u: sažetak s promjenom prema razdoblju prije,
 * dani tjedna s treninzima, kalendar mjeseca ili treninzi po mjesecima i aktivnost godine, mišići razdoblja
 * (u detaljnom prikazu) i rekordi razdoblja. Strelice idu do deset godina unatrag i najdalje do danas.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OverviewScreen(services: AppServices, initialPeriod: OverviewPeriod, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val store = services.store
    val revision = rememberStoreRevision(store)
    val locale = LocalConfiguration.current.locales[0]
    val calendar = remember(locale) { StatsCalendar.system(locale) }
    var period by rememberSaveable { mutableStateOf(initialPeriod) }
    // Datum u prikazanom razdoblju; pri promjeni razdoblja ostaje, pa tjedan prelazi u svoj mjesec i godinu.
    var anchorMillis by rememberSaveable { mutableLongStateOf(Instant.now().toEpochMilli()) }
    var openedSession by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedRegion by rememberSaveable { mutableStateOf<String?>(null) }
    val anchor = Instant.ofEpochMilli(anchorMillis)
    val now = Instant.now()
    val interval = period.interval(anchor, calendar)
    LaunchedEffect(period, interval.start) { selectedRegion = null }

    openedSession?.let { id ->
        SessionDetailScreen(services, UUID.fromString(id), onClose = { openedSession = null })
        return
    }

    val settings = store.settings()
    val isPro = settings.statsDetail == StatsDetail.PRO
    val goal = settings.trainingDaysPerWeek
    val data = remember(revision, period, interval.start, calendar, isPro, goal) {
        loadOverview(services, period, anchor, Instant.now(), calendar, goal, isPro)
    }
    val isCurrent = OverviewNavigation.isCurrent(period, anchor, now, calendar)
    val unit = settings.weightUnit

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.overview)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    if (!isCurrent) {
                        TextButton(onClick = { anchorMillis = Instant.now().toEpochMilli() }) { Text(stringResource(R.string.today)) }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OverviewPeriod.entries.forEach { option ->
                    FilterChip(
                        selected = option == period,
                        onClick = { period = option },
                        label = { Text(stringResource(periodTitle(option))) },
                    )
                }
            }
            PeriodPicker(
                period = period,
                rangeText = rangeText(period, data.summary, locale),
                canGoBack = OverviewNavigation.canGoBack(period, anchor, now, calendar),
                canGoForward = !isCurrent,
                onShift = { step -> anchorMillis = OverviewNavigation.shift(period, anchor, step, Instant.now(), calendar).toEpochMilli() },
            )
            SummaryCard(data.summary, data.previous, locale)
            when (period) {
                OverviewPeriod.WEEK -> WeekDaysCard(data, calendar, locale, onOpen = { openedSession = it.toString() })
                OverviewPeriod.MONTH -> MonthCalendarCard(data, calendar, locale, onOpen = { openedSession = it.toString() })
                OverviewPeriod.YEAR -> YearCard(data.summary, locale, onSelectMonth = { month ->
                    anchorMillis = month.toEpochMilli()
                    period = OverviewPeriod.MONTH
                })
            }
            if (isPro) {
                OverviewMusclesCard(
                    period = period,
                    comparison = data.comparison,
                    heatmap = data.heatmap,
                    isCurrent = isCurrent,
                    services = services,
                    female = settings.bodyMapFemale,
                    selected = selectedRegion,
                    onSelect = { selectedRegion = it },
                    locale = locale,
                )
            }
            if (data.records.isNotEmpty()) {
                val (weight, dates) = rememberRecordFormats(unit)
                OverviewCardFrame(stringResource(recordsTitle(period))) {
                    data.records.forEach { RecordRow(it, weight, dates) }
                }
            }
        }
    }
}

private fun loadOverview(
    services: AppServices,
    period: OverviewPeriod,
    anchor: Instant,
    now: Instant,
    calendar: StatsCalendar,
    goal: Int?,
    isPro: Boolean,
): OverviewData {
    val store = services.store
    val engine = StatisticsEngine(store)
    val info = ExerciseInfoBuilder.provider(services.catalog, store.customExercises)
    val isCardio = ExerciseInfoBuilder.isCardio(info)
    val current = engine.periodSummary(period, anchor, now, goal, calendar, isCardio)
    val previous = engine.periodSummary(period, period.shift(current.interval.start, -1, calendar), now, goal, calendar, isCardio)
    val sessions = engine.sessions(current.interval)
    val settings = store.settings()
    val records = engine.personalRecords(PRKind.tracked(settings), settings.prExcludedExerciseKeys)
    // Tekuće razdoblje se za prosjek serija tjedno broji do sada, ne do kraja.
    val heatmapEnd = minOf(current.interval.end, now.plusSeconds(1))
    return OverviewData(
        summary = current,
        previous = previous,
        days = current.sessionsByDay(sessions, calendar),
        figures = sessions.associate { it.id to SessionFigures.of(it, isCardio) },
        comparison = if (isPro) engine.periodVolume(period, anchor, now, calendar, info) else null,
        heatmap = if (isPro) engine.heatmap(current.interval.start, heatmapEnd, info) else emptyMap(),
        records = OverviewNavigation.records(records, current.interval),
    )
}

private fun periodTitle(period: OverviewPeriod): Int = when (period) {
    OverviewPeriod.WEEK -> R.string.period_week
    OverviewPeriod.MONTH -> R.string.period_month
    OverviewPeriod.YEAR -> R.string.period_year
}

private fun recordsTitle(period: OverviewPeriod): Int = when (period) {
    OverviewPeriod.WEEK -> R.string.overview_records_week
    OverviewPeriod.MONTH -> R.string.overview_records_month
    OverviewPeriod.YEAR -> R.string.overview_records_year
}

/** Npr. "2. stu 2026. – 8. stu 2026.", "Studeni 2026." ili "2026." */
private fun rangeText(period: OverviewPeriod, summary: PeriodSummary, locale: Locale): String {
    val zone = java.time.ZoneId.systemDefault()
    val start = summary.interval.start.atZone(zone).toLocalDate()
    return when (period) {
        OverviewPeriod.WEEK -> {
            val formatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
            formatter.format(start) + " – " + formatter.format(start.plusDays(6))
        }
        OverviewPeriod.MONTH -> start.format(DateTimeFormatter.ofPattern("LLLL yyyy", locale)).replaceFirstChar { it.titlecase(locale) }
        OverviewPeriod.YEAR -> start.year.toString()
    }
}

/** Kartica s naslovom, kao `StatisticsCard` na iOS-u. */
@Composable
private fun OverviewCardFrame(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

/** Strelice za prethodno i sljedeće razdoblje te njegov naziv. */
@Composable
private fun PeriodPicker(period: OverviewPeriod, rangeText: String, canGoBack: Boolean, canGoForward: Boolean, onShift: (Int) -> Unit) {
    val previous = when (period) {
        OverviewPeriod.WEEK -> R.string.previous_week
        OverviewPeriod.MONTH -> R.string.previous_month
        OverviewPeriod.YEAR -> R.string.previous_year
    }
    val next = when (period) {
        OverviewPeriod.WEEK -> R.string.next_week
        OverviewPeriod.MONTH -> R.string.next_month
        OverviewPeriod.YEAR -> R.string.next_year
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onShift(-1) }, enabled = canGoBack) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(previous))
        }
        Text(
            rangeText,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        IconButton(onClick = { onShift(1) }, enabled = canGoForward) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = stringResource(next))
        }
    }
}

// Sažetak

private class Change(val text: String, val isUp: Boolean)

private class Tile(val value: String, val label: String, val change: Change?)

/**
 * Treninzi, ukupno vrijeme, tvrde serije i kardio, s promjenom prema razdoblju prije. Za mjesec i godinu
 * i prosjek treninga tjedno.
 */
@Composable
private fun SummaryCard(current: PeriodSummary, previous: PeriodSummary?, locale: Locale) {
    val showsCardio = current.cardioSeconds >= 60 || (previous?.cardioSeconds ?: 0) >= 60
    val sessionsText = current.weeklyGoal?.takeIf { current.period == OverviewPeriod.WEEK }
        ?.let { stringResource(R.string.value_of_goal, current.sessions.toString(), it) }
        ?: current.sessions.toString()
    val perWeek = NumberInput.format(Math.round(current.sessionsPerWeek * 10) / 10.0, locale)
    val perWeekText = current.weeklyGoal?.let { stringResource(R.string.value_of_goal, perWeek, it) } ?: perWeek
    val cardioText = durationText(current.cardioSeconds.toDouble()) +
        if (current.cardioMeters > 0) " · " + CardioText.distance(current.cardioMeters, locale) else ""

    val tiles = buildList {
        add(Tile(sessionsText, stringResource(R.string.overview_workouts), PeriodChange.count(current.sessions, previous?.sessions)?.let(::countChange)))
        if (current.period != OverviewPeriod.WEEK) add(Tile(perWeekText, stringResource(R.string.overview_weekly_average), null))
        add(
            Tile(
                durationText(current.totalSeconds),
                stringResource(R.string.total_label),
                PeriodChange.duration(current.totalSeconds, previous?.totalSeconds)?.let(::durationChange),
            ),
        )
        add(
            Tile(
                current.hardSets.toString(),
                stringResource(R.string.stat_hard_sets),
                PeriodChange.percent(current.hardSets, previous?.hardSets)?.let { Change(signedPercent(it, locale), it > 0) },
            ),
        )
        if (showsCardio) {
            add(
                Tile(
                    cardioText,
                    stringResource(R.string.stat_cardio),
                    PeriodChange.duration(current.cardioSeconds.toDouble(), previous?.cardioSeconds?.toDouble())?.let(::durationChange),
                ),
            )
        }
    }
    val footnote = when (current.period) {
        OverviewPeriod.WEEK -> R.string.overview_change_week
        OverviewPeriod.MONTH -> R.string.overview_change_month
        OverviewPeriod.YEAR -> R.string.overview_change_year
    }
    OverviewCardFrame(stringResource(R.string.overview_summary)) {
        tiles.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { SummaryTile(it, Modifier.weight(1f)) }
                if (row.size == 1) Box(Modifier.weight(1f))
            }
        }
        if (previous != null) {
            Text(stringResource(footnote), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun countChange(delta: Int): Change = Change((if (delta > 0) "+" else "−") + kotlin.math.abs(delta), delta > 0)

private fun durationChange(delta: Double): Change =
    Change((if (delta > 0) "+" else "−") + durationText(kotlin.math.abs(delta)), delta > 0)

@Composable
private fun SummaryTile(tile: Tile, modifier: Modifier) {
    Column(
        modifier.heightIn(min = 64.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(10.dp)
            .semantics(mergeDescendants = true) {},
    ) {
        Text(tile.value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 2)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(tile.label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            tile.change?.let { change ->
                Text(
                    change.text,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (change.isUp) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// Trening u popisu

/** Redak treninga s trajanjem, serijama, kardiom i rekordima; dodir otvara detalje. */
@Composable
private fun OverviewSessionRow(session: Session, data: OverviewData, locale: Locale, onOpen: (UUID) -> Unit) {
    val parts = mutableListOf<String>()
    data.figures[session.id]?.let { figures ->
        parts += durationText(figures.durationSeconds)
        if (figures.hardSets > 0) parts += pluralStringResource(R.plurals.completed_sets, figures.hardSets, figures.hardSets)
        figures.cardioMeters?.let { parts += CardioText.distance(it, locale) }
    }
    val records = data.recordCount(session)
    if (records > 0) parts += pluralStringResource(R.plurals.records_count, records, records)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp)).clickable { onOpen(session.id) }
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(session.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
    }
}

// Tjedan po danima

/** Dani tjedna s treninzima; dan bez treninga je odmor, a dani koji još nisu došli se ne prikazuju. */
@Composable
private fun WeekDaysCard(data: OverviewData, calendar: StatsCalendar, locale: Locale, onOpen: (UUID) -> Unit) {
    val today = calendar.startOfDay(Instant.now())
    val shown = data.summary.days.map { it.date }.filter { it <= today }
    val weekday = DateTimeFormatter.ofPattern("EEE", locale)
    val full = DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale)
    OverviewCardFrame(stringResource(R.string.overview_by_day)) {
        shown.forEachIndexed { index, day ->
            if (index > 0) HorizontalDivider()
            val date = calendar.zoned(day)
            val description = full.format(date)
            Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(
                    Modifier.width(40.dp).clearAndSetSemantics { contentDescription = description },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(weekday.format(date), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(date.dayOfMonth.toString(), style = MaterialTheme.typography.titleMedium)
                }
                Column(Modifier.weight(1f)) {
                    val sessions = data.sessions(day)
                    if (sessions.isEmpty()) {
                        Text(
                            stringResource(R.string.overview_rest),
                            modifier = Modifier.heightIn(min = 40.dp).padding(top = 8.dp),
                            color = MaterialTheme.colorScheme.outline,
                        )
                    }
                    sessions.forEach { OverviewSessionRow(it, data, locale, onOpen) }
                }
            }
        }
    }
}

// Mjesec u kalendaru

/** Kalendar mjeseca s označenim danima treninga. Dodir na dan pokazuje njegove treninge ispod kalendara. */
@Composable
private fun MonthCalendarCard(data: OverviewData, calendar: StatsCalendar, locale: Locale, onOpen: (UUID) -> Unit) {
    val start = calendar.date(data.summary.interval.start)
    var selectedText by rememberSaveable(start.toString()) { mutableStateOf<String?>(null) }
    val selected = selectedText?.let(LocalDate::parse)
    val trained = data.summary.days.filter { it.isTrained }.map { calendar.date(it.date) }.toSet()
    val full = DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale)
    OverviewCardFrame(stringResource(R.string.history_calendar)) {
        MonthCalendar(
            month = YearMonth.from(start),
            firstDayOfWeek = calendar.firstDayOfWeek,
            hasWorkout = { it in trained },
            selected = selected,
            onSelect = { selectedText = it?.toString() },
            lastEnabled = calendar.date(Instant.now()),
        )
        if (selected != null) {
            val sessions = data.sessions(calendar.startOfDay(selected))
            HorizontalDivider()
            Text(full.format(selected).replaceFirstChar { it.titlecase(locale) }, style = MaterialTheme.typography.titleSmall)
            if (sessions.isEmpty()) Text(stringResource(R.string.overview_rest), color = MaterialTheme.colorScheme.outline)
            sessions.forEach { OverviewSessionRow(it, data, locale, onOpen) }
        } else if (data.summary.sessions > 0) {
            Text(stringResource(R.string.overview_tap_day), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// Godina

/** Treninzi po mjesecima (dodir na mjesec otvara njegov pregled) i aktivnost cijele godine po danima. */
@Composable
private fun YearCard(summary: PeriodSummary, locale: Locale, onSelectMonth: (Instant) -> Unit) {
    val zone = java.time.ZoneId.systemDefault()
    val now = Instant.now()
    val highest = summary.months.maxOfOrNull { it.sessions }?.coerceAtLeast(1) ?: 1
    val chartLabel = stringResource(R.string.overview_months_chart)
    OverviewCardFrame(stringResource(R.string.overview_by_month)) {
        Row(
            Modifier.fillMaxWidth().height(160.dp).semantics { contentDescription = chartLabel },
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            summary.months.forEach { month ->
                val enabled = month.start <= now
                Column(
                    Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(4.dp)).clickable(enabled = enabled) { onSelectMonth(month.start) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (month.sessions > 0) month.sessions.toString() else "",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                        val fraction = month.sessions.toFloat() / highest
                        Box(
                            Modifier.fillMaxWidth()
                                .fillMaxHeight(fraction.coerceAtLeast(0.03f))
                                .clip(RoundedCornerShape(4.dp))
                                .background(if (month.sessions > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant),
                        )
                    }
                    Text(
                        month.start.atZone(zone).month.getDisplayName(TextStyle.NARROW, locale),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        Text(stringResource(R.string.overview_tap_month), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.overview_activity), style = MaterialTheme.typography.titleSmall)
        val trainedText = stringResource(R.string.overview_trained_days, summary.trainedDays)
        YearActivityGrid(summary, Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = trainedText })
        Text(trainedText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Dani godine u stupcima po tjednima, kao kvadratići: obojen je dan s treningom. */
@Composable
private fun YearActivityGrid(summary: PeriodSummary, modifier: Modifier) {
    val locale = LocalConfiguration.current.locales[0]
    val firstDay = remember(locale) { StatsCalendar.system(locale).firstDayOfWeek }
    val zone = java.time.ZoneId.systemDefault()
    val days = summary.days
    val leading = days.firstOrNull()?.let { (it.date.atZone(zone).dayOfWeek.value - firstDay.value + 7) % 7 } ?: 0
    val columns = maxOf((leading + days.size + 6) / 7, 1)
    val accent = MaterialTheme.colorScheme.primary
    val idle = MaterialTheme.colorScheme.surfaceVariant
    val now = Instant.now()
    Canvas(modifier.aspectRatio(columns / 7f)) {
        val spacing = 1.5.dp.toPx()
        val cell = minOf((size.width + spacing) / columns, (size.height + spacing) / 7) - spacing
        days.forEachIndexed { index, day ->
            val position = index + leading
            val color = when {
                day.isTrained -> accent
                day.date > now -> Color.Transparent
                else -> idle
            }
            drawRoundRect(
                color,
                topLeft = Offset((position / 7) * (cell + spacing), (position % 7) * (cell + spacing)),
                size = Size(cell, cell),
                cornerRadius = CornerRadius(cell / 4, cell / 4),
            )
        }
    }
}

// Serije po mišiću

/**
 * Mapa tijela s opterećenjem razdoblja i tvrde serije po mišiću uz razdoblje prije (šest mišića s najviše
 * serija). Za mjesec i godinu prosjek serija tjedno.
 */
@Composable
private fun OverviewMusclesCard(
    period: OverviewPeriod,
    comparison: VolumeComparison?,
    heatmap: Map<String, RegionLoad>,
    isCurrent: Boolean,
    services: AppServices,
    female: Boolean,
    selected: String?,
    onSelect: (String?) -> Unit,
    locale: Locale,
) {
    val number = NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 1 }
    val currentTitle = stringResource(
        when (period) {
            OverviewPeriod.WEEK -> if (isCurrent) R.string.card_this_week else R.string.overview_selected_week
            OverviewPeriod.MONTH -> if (isCurrent) R.string.card_this_month else R.string.overview_selected_month
            OverviewPeriod.YEAR -> if (isCurrent) R.string.card_this_year else R.string.overview_selected_year
        },
    )
    val previousTitle = stringResource(
        when (period) {
            OverviewPeriod.WEEK -> if (isCurrent) R.string.overview_last_week else R.string.overview_week_before
            OverviewPeriod.MONTH -> if (isCurrent) R.string.overview_last_month else R.string.overview_month_before
            OverviewPeriod.YEAR -> if (isCurrent) R.string.overview_last_year else R.string.overview_year_before
        },
    )
    val emptyText = when (period) {
        OverviewPeriod.WEEK -> R.string.overview_no_sets_week
        OverviewPeriod.MONTH -> R.string.overview_no_sets_month
        OverviewPeriod.YEAR -> R.string.overview_no_sets_year
    }
    val title = if (period == OverviewPeriod.WEEK) R.string.overview_muscle_sets else R.string.overview_muscle_sets_weekly
    val muscles = comparison?.muscles.orEmpty().take(6)
    val diagrams = services.bodyMap
    OverviewCardFrame(stringResource(title)) {
        if (heatmap.isEmpty()) {
            Text(stringResource(emptyText), color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            if (diagrams.isNotEmpty()) {
                Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(false, true).forEach { back ->
                        BodyFigure(diagrams, female, back, heatmap, selected, onSelect = onSelect, modifier = Modifier.weight(1f))
                    }
                }
                HeatmapLegend()
            }
            selected?.let { region ->
                val load = heatmap[region]
                val name = stringResource(regionTitle(region))
                Text(
                    if (period == OverviewPeriod.WEEK) {
                        stringResource(R.string.overview_region_sets, name, number.format(load?.sets ?: 0.0))
                    } else {
                        stringResource(R.string.overview_region_weekly_sets, name, number.format(load?.weeklySets ?: 0.0))
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        if (muscles.isNotEmpty()) {
            val accent = MaterialTheme.colorScheme.primary
            val muted = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                LegendDot(currentTitle, accent)
                LegendDot(previousTitle, muted)
            }
            val scaleMax = muscles.maxOf { maxOf(it.currentSets, it.previousSets) }.coerceAtLeast(1.0)
            muscles.forEach { item ->
                val name = stringResource(regionTitle(item.region))
                val description = "$name: $currentTitle ${number.format(item.currentSets)}, $previousTitle ${number.format(item.previousSets)}"
                Row(
                    Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = description },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(name, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(110.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        ComparisonBar(item.currentSets / scaleMax, accent, number.format(item.currentSets))
                        ComparisonBar(item.previousSets / scaleMax, muted, number.format(item.previousSets))
                    }
                }
            }
            Text(stringResource(R.string.overview_muscles_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun LegendDot(label: String, color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(10.dp)) { drawRoundRect(color, cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx())) }
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun ComparisonBar(fraction: Double, color: Color, value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.weight(1f).height(10.dp)) {
            val width = (fraction * size.width).toFloat().coerceIn(0f, size.width)
            if (width > 0f) drawRoundRect(color, size = Size(width, size.height), cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx()))
        }
        Text(value, style = MaterialTheme.typography.labelSmall, modifier = Modifier.width(32.dp))
    }
}

// Kartica u Statistici

/**
 * Kartica Pregled na vrhu Statistike, kao `OverviewCard` na iOS-u: tekući tjedan (treninzi prema cilju, dani,
 * serije i vrijeme), mjesec i godina ukratko te graf treninga po tjednu za zadnjih 12 tjedana. Tjedan otvara
 * Pregled na tjednu, a retci mjeseca i godine na svom razdoblju.
 */
@Composable
internal fun OverviewCard(
    week: WeekProgress,
    month: PeriodSummary,
    year: PeriodSummary,
    frequency: List<FrequencyPoint>,
    locale: Locale,
    onOpen: (OverviewPeriod) -> Unit,
) {
    OverviewCardFrame(stringResource(R.string.overview)) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { onOpen(OverviewPeriod.WEEK) }.padding(vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.card_this_week), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
            }
            WeekHeader(week)
            week.goalFraction?.let { fraction ->
                LinearProgressIndicator(progress = { fraction.toFloat() }, modifier = Modifier.fillMaxWidth(), strokeCap = StrokeCap.Round)
            }
            WeekDaysStrip(week.days, locale)
            if (week.sessions > 0) PeriodFigures(week.hardSets, week.cardioSeconds, week.totalSeconds)
        }
        HorizontalDivider()
        PeriodRow(stringResource(R.string.card_this_month), month, locale) { onOpen(OverviewPeriod.MONTH) }
        HorizontalDivider()
        PeriodRow(stringResource(R.string.card_this_year), year, locale) { onOpen(OverviewPeriod.YEAR) }
        if (frequency.isNotEmpty()) {
            HorizontalDivider()
            FrequencyChart(frequency, locale)
        }
    }
}

/** Npr. "12 treninga · 2,8 tjedno · 140 tvrdih serija"; dodir otvara Pregled na tom razdoblju. */
@Composable
private fun PeriodRow(title: String, summary: PeriodSummary, locale: Locale, onClick: () -> Unit) {
    val parts = mutableListOf(stringResource(R.string.workouts_n, summary.sessions), perWeekText(summary, locale))
    if (summary.hardSets > 0) parts += pluralStringResource(R.plurals.hard_sets_count, summary.hardSets, summary.hardSets)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
    }
}

/** Treninga tjedno, zadnjih 12 tjedana, s prosjekom. */
@Composable
private fun FrequencyChart(frequency: List<FrequencyPoint>, locale: Locale) {
    val average = frequency.sumOf { it.sessions }.toDouble() / maxOf(frequency.size, 1)
    val highest = frequency.maxOf { it.sessions }.coerceAtLeast(1)
    val label = stringResource(R.string.overview_frequency_chart)
    val accent = MaterialTheme.colorScheme.primary
    val idle = MaterialTheme.colorScheme.surfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(stringResource(R.string.overview_frequency), style = MaterialTheme.typography.titleSmall)
        Text(
            stringResource(R.string.overview_frequency_average, NumberInput.format(Math.round(average * 10) / 10.0, locale)),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    Canvas(Modifier.fillMaxWidth().height(100.dp).semantics { contentDescription = label }) {
        val gap = 4.dp.toPx()
        val width = (size.width - gap * (frequency.size - 1)) / frequency.size
        frequency.forEachIndexed { index, point ->
            val fraction = point.sessions.toFloat() / highest
            val height = maxOf(fraction * size.height, 2.dp.toPx())
            drawRoundRect(
                if (point.sessions > 0) accent else idle,
                topLeft = Offset(index * (width + gap), size.height - height),
                size = Size(width, height),
                cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx()),
            )
        }
    }
}

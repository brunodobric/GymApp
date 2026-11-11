package com.brunodobric.gymapp.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Mechanic
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.DashboardCardKind
import com.brunodobric.gymapp.model.DashboardLayout
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.kind
import com.brunodobric.gymapp.stats.BodyTracking
import com.brunodobric.gymapp.stats.ExerciseInfoBuilder
import com.brunodobric.gymapp.stats.OverviewPeriod
import com.brunodobric.gymapp.stats.PeriodSummary
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.stats.TrainingDay
import com.brunodobric.gymapp.stats.WeekProgress
import com.brunodobric.gymapp.stats.periodSummary
import com.brunodobric.gymapp.stats.weekProgress
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.ui.body.BodyFormat
import com.brunodobric.gymapp.ui.theme.success
import com.brunodobric.gymapp.ui.workout.RecordItem
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightFormatter
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

/** Naslov kartice na Početnoj. */
internal fun DashboardCardKind.title(): Int = when (this) {
    DashboardCardKind.THIS_WEEK -> R.string.card_this_week
    DashboardCardKind.THIS_MONTH -> R.string.card_this_month
    DashboardCardKind.THIS_YEAR -> R.string.card_this_year
    DashboardCardKind.LAST_WORKOUT -> R.string.card_last_workout
    DashboardCardKind.BODY_WEIGHT -> R.string.card_body_weight
    DashboardCardKind.PLATE_CALCULATOR -> R.string.plate_calculator
}

/** Radnje kartica: kamo vodi dodir. */
internal class DashboardActions(
    val onOpenStatistics: () -> Unit,
    val onOpenSession: (Session) -> Unit,
    val onOpenBody: () -> Unit,
    val onOpenPlates: () -> Unit,
)

/** Kartica Početne prema vrsti (`cardView` na iOS-u). */
@Composable
internal fun DashboardCardView(services: AppServices, kind: DashboardCardKind, revision: Long, actions: DashboardActions, modifier: Modifier) {
    when (kind) {
        DashboardCardKind.THIS_WEEK -> ThisWeekCard(services, revision, actions.onOpenStatistics, modifier)
        DashboardCardKind.THIS_MONTH -> PeriodCard(services, OverviewPeriod.MONTH, revision, actions.onOpenStatistics, modifier)
        DashboardCardKind.THIS_YEAR -> PeriodCard(services, OverviewPeriod.YEAR, revision, actions.onOpenStatistics, modifier)
        DashboardCardKind.LAST_WORKOUT -> LastWorkoutCard(services, revision, actions.onOpenSession, modifier)
        DashboardCardKind.BODY_WEIGHT -> BodyWeightCard(services, revision, actions.onOpenBody, modifier)
        DashboardCardKind.PLATE_CALCULATOR -> HomeCard(stringResource(R.string.plates), actions.onOpenPlates, modifier) {
            Text(stringResource(R.string.plate_calculator), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Okvir kartice: naslov malim slovima iznad sadržaja (`HomeCard` na iOS-u). */
@Composable
internal fun HomeCard(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(onClick = onClick, modifier = modifier) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                title.uppercase(LocalConfiguration.current.locales[0]),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            content()
        }
    }
}

@Composable
private fun rememberIsCardio(services: AppServices, revision: Long): (String) -> Boolean {
    val info = remember(revision) { ExerciseInfoBuilder.provider(services.catalog, services.store.customExercises) }
    return remember(info) { ExerciseInfoBuilder.isCardio(info) }
}

/** Ovaj tjedan: broj treninga prema cilju, traka cilja, dani tjedna, niz tjedana i brojke. */
@Composable
private fun ThisWeekCard(services: AppServices, revision: Long, onClick: () -> Unit, modifier: Modifier) {
    val locale = LocalConfiguration.current.locales[0]
    val isCardio = rememberIsCardio(services, revision)
    val goal = services.store.settings().trainingDaysPerWeek
    val today = LocalDate.now()
    val progress = remember(revision, goal, today, locale) {
        StatisticsEngine(services.store).weekProgress(goal = goal, calendar = StatsCalendar.system(locale), isCardio = isCardio)
    }
    HomeCard(stringResource(R.string.card_this_week), onClick, modifier) {
        WeekHeader(progress)
        progress.goalFraction?.let { fraction ->
            LinearProgressIndicator(progress = { fraction.toFloat() }, modifier = Modifier.fillMaxWidth(), strokeCap = StrokeCap.Round)
        }
        WeekDaysStrip(progress.days, locale)
        if (progress.sessions > 0) PeriodFigures(progress.hardSets, progress.cardioSeconds, progress.totalSeconds)
    }
}

@Composable
private fun WeekHeader(progress: WeekProgress) {
    Row(verticalAlignment = Alignment.Bottom) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val goal = progress.goal
            if (goal != null) {
                Text(progress.sessions.toString(), style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.ExtraBold)
                Text(
                    stringResource(R.string.of_goal_workouts, goal),
                    Modifier.padding(bottom = 6.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(stringResource(R.string.workouts_n, progress.sessions), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold)
            }
        }
        if (progress.streakWeeks >= 2) {
            Text(
                "🔥 " + stringResource(R.string.weeks_streak, progress.streakWeeks),
                Modifier.padding(bottom = 6.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Sedam dana tjedna: pun krug za dan s treningom, obrub za današnji dan. */
@Composable
private fun WeekDaysStrip(days: List<TrainingDay>, locale: Locale) {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    Row(Modifier.fillMaxWidth()) {
        days.forEach { day ->
            val date = day.date.atZone(zone).toLocalDate()
            val isToday = date == today
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val circle = Modifier.size(30.dp).clip(CircleShape)
                Box(
                    when {
                        day.isTrained -> circle.background(MaterialTheme.colorScheme.primary)
                        isToday -> circle.background(MaterialTheme.colorScheme.surfaceContainer).border(2.dp, MaterialTheme.colorScheme.primary, CircleShape)
                        else -> circle.background(MaterialTheme.colorScheme.surfaceContainer)
                    },
                )
                Text(
                    date.dayOfWeek.getDisplayName(TextStyle.NARROW, locale),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isToday) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Tvrde serije, kardio i ukupno vrijeme u malim poljima (`PeriodFigures` na iOS-u). */
@Composable
private fun PeriodFigures(hardSets: Int, cardioSeconds: Int, totalSeconds: Double) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (hardSets > 0) Figure(hardSets.toString(), stringResource(R.string.stat_hard_sets), Modifier.weight(1f))
        if (cardioSeconds >= 60) Figure(durationText(cardioSeconds.toDouble()), stringResource(R.string.stat_cardio), Modifier.weight(1f))
        Figure(durationText(totalSeconds), stringResource(R.string.total_label), Modifier.weight(1f))
    }
}

@Composable
private fun Figure(value: String, label: String, modifier: Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
    }
}

/** "1 h 4 min" ili "45 min". */
private fun durationText(seconds: Double): String {
    val minutes = (seconds / 60).toInt()
    return if (minutes >= 60) "${minutes / 60} h ${minutes % 60} min" else "$minutes min"
}

/** Ovaj mjesec (dani mjeseca) ili Ova godina (treninzi po mjesecima). */
@Composable
private fun PeriodCard(services: AppServices, period: OverviewPeriod, revision: Long, onClick: () -> Unit, modifier: Modifier) {
    val locale = LocalConfiguration.current.locales[0]
    val isCardio = rememberIsCardio(services, revision)
    val goal = services.store.settings().trainingDaysPerWeek
    val today = LocalDate.now()
    val summary = remember(revision, goal, today, locale, period) {
        StatisticsEngine(services.store).periodSummary(period, Instant.now(), goal = goal, calendar = StatsCalendar.system(locale), isCardio = isCardio)
    }
    val title = if (period == OverviewPeriod.YEAR) R.string.card_this_year else R.string.card_this_month
    HomeCard(stringResource(title), onClick, modifier) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                stringResource(R.string.workouts_n, summary.sessions),
                Modifier.weight(1f),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.ExtraBold,
            )
            Text(perWeekText(summary, locale), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (period == OverviewPeriod.YEAR) YearBars(summary, locale) else MonthDays(summary.days)
        if (summary.sessions > 0) PeriodFigures(summary.hardSets, summary.cardioSeconds, summary.totalSeconds)
    }
}

@Composable
private fun perWeekText(summary: PeriodSummary, locale: Locale): String {
    val value = NumberInput.format(Math.round(summary.sessionsPerWeek * 10) / 10.0, locale)
    return summary.weeklyGoal?.let { stringResource(R.string.per_week_goal, value, it) } ?: stringResource(R.string.per_week, value)
}

/** Dani mjeseca u redovima po sedam: pun kvadrat za dan s treningom. */
@Composable
private fun MonthDays(days: List<TrainingDay>) {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        days.chunked(7).forEach { week ->
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                week.forEach { day ->
                    val isToday = day.date.atZone(zone).toLocalDate() == today
                    val shape = RoundedCornerShape(5.dp)
                    Box(
                        Modifier.weight(1f).height(14.dp).clip(shape).background(
                            if (day.isTrained) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer,
                        ).let { if (isToday && !day.isTrained) it.border(1.5.dp, MaterialTheme.colorScheme.primary, shape) else it },
                    )
                }
                repeat(7 - week.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

/** Treninzi po mjesecima kao stupci s početnim slovom mjeseca. */
@Composable
private fun YearBars(summary: PeriodSummary, locale: Locale) {
    val zone = ZoneId.systemDefault()
    val highest = summary.months.maxOfOrNull { it.sessions }?.coerceAtLeast(1) ?: 1
    Row(Modifier.fillMaxWidth().height(80.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        summary.months.forEach { month ->
            Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                    val fraction = month.sessions.toFloat() / highest
                    Box(
                        Modifier.fillMaxWidth()
                            .fillMaxHeight(fraction.coerceAtLeast(0.04f))
                            .clip(RoundedCornerShape(4.dp))
                            .background(if (month.sessions > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainer),
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
}

/** Zadnji trening: kad, trajanje, tvrde serije i najviše dva istaknuta rekorda. Dodir otvara detalj. */
@Composable
private fun LastWorkoutCard(services: AppServices, revision: Long, onOpen: (Session) -> Unit, modifier: Modifier) {
    val store = services.store
    val session = remember(revision) { store.finishedSessions().firstOrNull() }
    val locale = LocalConfiguration.current.locales[0]
    val settings = store.settings()
    val isCardio = rememberIsCardio(services, revision)
    HomeCard(stringResource(R.string.card_last_workout), onClick = { session?.let(onOpen) }, modifier) {
        if (session == null) {
            Text(stringResource(R.string.history_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
            return@HomeCard
        }
        val summary = remember(revision, session.id) {
            WorkoutEngine(store).summary(
                session,
                trackedKinds = PRKind.tracked(settings),
                excludedExercises = settings.prExcludedExerciseKeys,
                isCompound = { key ->
                    if (key.startsWith("c:")) services.catalog.exercise(key.drop(2))?.mechanic?.let { it == Mechanic.COMPOUND } else null
                },
                isCardio = isCardio,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(session.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(dateText(session.startedAt, locale), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val parts = listOfNotNull(
                session.endedAt?.let { durationText(Duration.between(session.startedAt, it).seconds.coerceAtLeast(0).toDouble()) },
                summary.hardSets.takeIf { it > 0 }?.let { stringResource(R.string.sets_n, it) },
            )
            if (parts.isNotEmpty()) {
                Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val highlights = summary.highlights.take(2)
        if (highlights.isNotEmpty()) {
            val weight = remember(settings.weightUnit, locale) { WeightFormatter(settings.weightUnit, locale) }
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.success.copy(alpha = 0.10f)),
            ) {
                highlights.forEach { RecordItem(it.exerciseName, it.record, weight) }
            }
        }
    }
}

/** "Jučer · subota, 7. studenoga": dan prema kalendaru i datum bez godine. */
@Composable
private fun dateText(date: Instant, locale: Locale): String {
    val zone = ZoneId.systemDefault()
    val day = date.atZone(zone).toLocalDate()
    val days = ChronoUnit.DAYS.between(day, LocalDate.now(zone)).coerceAtLeast(0).toInt()
    val relative = when (days) {
        0 -> stringResource(R.string.today)
        1 -> stringResource(R.string.yesterday)
        else -> stringResource(R.string.days_ago, days)
    }
    val formatter = remember(locale) { DateTimeFormatter.ofPattern("EEEE, d. MMMM", locale) }
    return "$relative · ${formatter.format(day)}"
}

/** Tjelesna težina: zadnja vrijednost i promjena u 30 dana, ili poziv na upis. */
@Composable
private fun BodyWeightCard(services: AppServices, revision: Long, onClick: () -> Unit, modifier: Modifier) {
    val unit = services.store.settings().weightUnit
    val tracking = remember(revision) { BodyTracking(services.store) }
    val latest = remember(revision) { tracking.latest(BodyMeasurementKind.WEIGHT)?.value }
    val change = remember(revision) { tracking.recentChange(BodyMeasurementKind.WEIGHT) }
    HomeCard(stringResource(R.string.card_body_weight), onClick, modifier) {
        if (latest != null) {
            Text(BodyFormat.text(latest, BodyMeasurementKind.WEIGHT, unit), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold, maxLines = 1)
            change?.let {
                Text(
                    stringResource(R.string.change_30_days, BodyFormat.change(it, BodyMeasurementKind.WEIGHT, unit)),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            Text(stringResource(R.string.enter_weight), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Kartice na Početnoj: redoslijed strelicama, uklanjanje i dodavanje (`DashboardEditor` na iOS-u). */
@Composable
internal fun DashboardEditorDialog(services: AppServices, revision: Long, onDismiss: () -> Unit) {
    val layout = remember(services.store) { DashboardLayout(services.store) }
    val shown = remember(revision) { layout.cards() }
    val available = remember(revision) { layout.availableKinds() }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.cards_title)) },
        text = {
            Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState())) {
                Text(stringResource(R.string.on_home), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                if (shown.isEmpty()) {
                    Text(stringResource(R.string.no_cards), Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                shown.forEachIndexed { index, card ->
                    val kind = card.kind ?: return@forEachIndexed
                    ListItem(
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(stringResource(kind.title())) },
                        trailingContent = {
                            Row {
                                IconButton(onClick = { layout.move(listOf(index), index - 1) }, enabled = index > 0) {
                                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = stringResource(R.string.move_up))
                                }
                                IconButton(onClick = { layout.move(listOf(index), index + 2) }, enabled = index < shown.lastIndex) {
                                    Icon(Icons.Filled.KeyboardArrowDown, contentDescription = stringResource(R.string.move_down))
                                }
                                IconButton(onClick = { layout.remove(card) }) {
                                    Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove_card))
                                }
                            }
                        },
                    )
                }
                if (available.isNotEmpty()) {
                    HorizontalDivider(Modifier.padding(vertical = 8.dp))
                    Text(stringResource(R.string.add_card_section), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                    available.forEach { kind ->
                        ListItem(
                            modifier = Modifier.padding(0.dp),
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(stringResource(kind.title())) },
                            trailingContent = {
                                IconButton(onClick = { layout.add(kind) }) {
                                    Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_card_section))
                                }
                            },
                        )
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
    )
}

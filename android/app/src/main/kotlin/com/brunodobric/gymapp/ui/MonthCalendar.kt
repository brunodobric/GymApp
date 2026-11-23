package com.brunodobric.gymapp.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle

/**
 * Mjesec u mreži po tjednima, s točkicom ispod dana u kojem je odrađen trening (kao `CalendarMonthView` i
 * `MonthCalendarCard` na iOS-u). Dodir na dan ga odabire, ponovni dodir poništava odabir. Dani poslije
 * [lastEnabled] su sivi i ne mogu se odabrati.
 */
@Composable
fun MonthCalendar(
    month: YearMonth,
    firstDayOfWeek: DayOfWeek,
    hasWorkout: (LocalDate) -> Boolean,
    selected: LocalDate?,
    onSelect: (LocalDate?) -> Unit,
    modifier: Modifier = Modifier,
    lastEnabled: LocalDate? = null,
) {
    val locale = LocalConfiguration.current.locales[0]
    val fullDate = DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale)
    val hasWorkoutText = stringResource(R.string.has_workout)
    val first = month.atDay(1)
    // Prazna mjesta ispred prvog dana, da stupci odgovaraju danima u tjednu.
    val leading = (first.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
    val cells: List<LocalDate?> = List(leading) { null } + (1..month.lengthOfMonth()).map { month.atDay(it) }
    val weekdays = (0L until 7).map { firstDayOfWeek.plus(it) }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth()) {
            weekdays.forEach { day ->
                Text(
                    day.getDisplayName(TextStyle.NARROW_STANDALONE, locale),
                    modifier = Modifier.weight(1f).clearAndSetSemantics {},
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
        cells.chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                week.forEach { day ->
                    if (day == null) {
                        Box(Modifier.weight(1f))
                        return@forEach
                    }
                    val isSelected = day == selected
                    val isEnabled = lastEnabled == null || !day.isAfter(lastEnabled)
                    val trained = hasWorkout(day)
                    val shape = RoundedCornerShape(8.dp)
                    Column(
                        Modifier.weight(1f).heightIn(min = 44.dp).clip(shape)
                            .background(if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.2f) else Color.Transparent)
                            .clickable(enabled = isEnabled) { onSelect(if (isSelected) null else day) }
                            .clearAndSetSemantics {
                                contentDescription = fullDate.format(day)
                                if (trained) stateDescription = hasWorkoutText
                                this.selected = isSelected
                            },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            day.dayOfMonth.toString(),
                            style = MaterialTheme.typography.bodyLarge,
                            color = if (isEnabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline,
                        )
                        Box(
                            Modifier.size(6.dp).clip(CircleShape)
                                .background(if (trained) MaterialTheme.colorScheme.primary else Color.Transparent),
                        )
                    }
                }
                repeat(7 - week.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

/** Naziv mjeseca sa strelicama za prethodni i sljedeći mjesec (iznad [MonthCalendar] u Povijesti). */
@Composable
fun MonthHeader(month: YearMonth, onShift: (Int) -> Unit, modifier: Modifier = Modifier, canGoForward: Boolean = true) {
    val locale = LocalConfiguration.current.locales[0]
    val title = month.atDay(1).format(DateTimeFormatter.ofPattern("LLLL yyyy", locale))
        .replaceFirstChar { it.titlecase(locale) }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onShift(-1) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = stringResource(R.string.previous_month))
        }
        Text(
            title,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        IconButton(onClick = { onShift(1) }, enabled = canGoForward) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = stringResource(R.string.next_month))
        }
    }
}

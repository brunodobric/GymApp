package com.brunodobric.gymapp.ui.planning

import android.Manifest
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.ReminderMode
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.notifications.RestNotifications
import com.brunodobric.gymapp.planning.ReminderTime
import java.time.DayOfWeek
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale

/** Zadano vrijeme podsjetnika kad se uključi, kao na iOS-u (18:00). */
private const val DEFAULT_REMINDER_MINUTES = 18 * 60

/**
 * Podsjetnici rasporeda (odjeljak "Aktivnost i podsjetnici" na iOS-u): uključivanje, vrijeme, način
 * (fleksibilno ili fiksni dani) i dani u tjednu ili razmak u danima. Promjene se spremaju odmah, a
 * spremanje ponovno zakazuje podsjetnike.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ScheduleReminderCard(store: GymStore, schedule: Schedule) {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    var pickingTime by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    val minutes = schedule.reminderMinutes

    Card(Modifier.fillMaxWidth()) {
        ListItem(
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            headlineContent = { Text(stringResource(R.string.reminders)) },
            trailingContent = {
                Switch(checked = minutes != null, onCheckedChange = { on ->
                    schedule.reminderMinutes = if (on) (schedule.reminderMinutes ?: DEFAULT_REMINDER_MINUTES) else null
                    store.save()
                    if (on && RestNotifications.needsPermission(context)) {
                        permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                })
            },
        )
        if (minutes != null) {
            HorizontalDivider()
            val time = LocalTime.of(minutes / 60, minutes % 60)
            ListItem(
                modifier = Modifier.clickable { pickingTime = true },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                headlineContent = { Text(stringResource(R.string.time)) },
                trailingContent = {
                    Text(time.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale)))
                },
            )
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                val modes = listOf(ReminderMode.FLEXIBLE to R.string.reminder_flexible, ReminderMode.FIXED_DAYS to R.string.reminder_fixed_days)
                modes.forEachIndexed { index, (mode, label) ->
                    SegmentedButton(
                        selected = schedule.reminderMode == mode,
                        onClick = {
                            schedule.reminderMode = mode
                            store.save()
                        },
                        shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                    ) { Text(stringResource(label)) }
                }
            }
            if (schedule.reminderMode == ReminderMode.FIXED_DAYS) {
                WeekdayPicker(schedule.weekdays, locale) { weekday ->
                    schedule.weekdays = ReminderTime.toggling(weekday, schedule.weekdays)
                    store.save()
                }
            } else {
                val gap = schedule.reminderGapDays
                ListItem(
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    headlineContent = { Text(pluralStringResource(R.plurals.reminder_gap_days, gap, gap)) },
                    trailingContent = {
                        Row {
                            TextButton(enabled = gap > 1, onClick = {
                                schedule.reminderGapDays = gap - 1
                                store.save()
                            }) { Text("−") }
                            TextButton(enabled = gap < 7, onClick = {
                                schedule.reminderGapDays = gap + 1
                                store.save()
                            }) { Text("+") }
                        }
                    },
                )
            }
        }
    }
    Text(
        stringResource(R.string.reminder_footer),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp),
    )

    if (pickingTime && minutes != null) {
        val state = rememberTimePickerState(minutes / 60, minutes % 60, DateFormat.is24HourFormat(context))
        AlertDialog(
            onDismissRequest = { pickingTime = false },
            text = { TimePicker(state) },
            confirmButton = {
                TextButton(onClick = {
                    schedule.reminderMinutes = state.hour * 60 + state.minute
                    store.save()
                    pickingTime = false
                }) { Text(stringResource(R.string.ok)) }
            },
            dismissButton = { TextButton(onClick = { pickingTime = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Krugovi s prvim slovom dana, od ponedjeljka; čitač zaslona izgovara cijeli naziv dana. */
@Composable
private fun WeekdayPicker(selected: List<Int>, locale: Locale, onToggle: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ReminderTime.weekdaysFromMonday.forEach { weekday ->
            // Dan kao Calendar.weekday na iOS-u: 1 = nedjelja, 2 = ponedjeljak.
            val day = if (weekday == 1) DayOfWeek.SUNDAY else DayOfWeek.of(weekday - 1)
            val isOn = weekday in selected
            val fullName = day.getDisplayName(TextStyle.FULL_STANDALONE, locale)
            Box(
                Modifier
                    .weight(1f)
                    .aspectRatio(1f)
                    .clip(CircleShape)
                    .background(if (isOn) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant)
                    .clickable(role = Role.Checkbox) { onToggle(weekday) }
                    .semantics {
                        contentDescription = fullName
                        this.selected = isOn
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    day.getDisplayName(TextStyle.NARROW_STANDALONE, locale),
                    style = MaterialTheme.typography.titleSmall,
                    color = if (isOn) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

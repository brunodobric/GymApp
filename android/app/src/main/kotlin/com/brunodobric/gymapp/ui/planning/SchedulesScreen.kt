package com.brunodobric.gymapp.ui.planning

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateEngine
import com.brunodobric.gymapp.ui.rememberStoreRevision
import java.text.Collator
import java.util.UUID

/**
 * Rasporedi, prvi korak: popis rasporeda i spremljenih treninga, novi raspored ili trening te njihovi
 * uređivači te gotovi programi.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SchedulesScreen(services: AppServices) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    var openedTemplate by rememberSaveable { mutableStateOf<String?>(null) }
    var openedSchedule by rememberSaveable { mutableStateOf<String?>(null) }
    // Upravo stvorena stavka: izlazak bez spremanja je briše.
    var openedIsNew by rememberSaveable { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    var showsPrograms by rememberSaveable { mutableStateOf(false) }
    if (showsPrograms) {
        ProgramsScreen(services, onClose = { showsPrograms = false })
        return
    }
    openedSchedule?.let { id ->
        ScheduleEditorScreen(services, UUID.fromString(id), isNew = openedIsNew, onClose = {
            openedSchedule = null
            openedIsNew = false
        })
        return
    }
    openedTemplate?.let { id ->
        TemplateEditorScreen(services, UUID.fromString(id), isNew = openedIsNew, onClose = {
            openedTemplate = null
            openedIsNew = false
        })
        return
    }

    val locale = LocalConfiguration.current.locales[0]
    val schedules = remember(revision) { store.schedules.sortedBy { it.createdAt } }
    val templates = remember(revision, locale) {
        val collator = Collator.getInstance(locale)
        store.templates.sortedWith { a, b -> collator.compare(a.name, b.name) }
    }
    val newName = stringResource(R.string.new_workout_name)
    val newScheduleName = stringResource(R.string.new_schedule)

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.tab_plans)) }) },
        floatingActionButton = {
            Box {
                SmallFloatingActionButton(onClick = { creating = true }) {
                    Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add))
                }
                DropdownMenu(expanded = creating, onDismissRequest = { creating = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.new_schedule)) },
                        onClick = {
                            creating = false
                            openedIsNew = true
                            openedSchedule = ScheduleEngine(store).createSchedule(newScheduleName).id.toString()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.ready_programs)) },
                        onClick = {
                            creating = false
                            showsPrograms = true
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.new_workout)) },
                        onClick = {
                            creating = false
                            openedIsNew = true
                            openedTemplate = TemplateEngine(store).createTemplate(newName).id.toString()
                        },
                    )
                }
            }
        },
    ) { padding ->
        val scheduleItems: LazyListScope.() -> Unit = {
            item { Header(stringResource(R.string.schedules_section)) }
            if (schedules.isEmpty()) item { Empty(stringResource(R.string.schedules_empty)) }
            items(schedules, key = { "s" + it.id }) { schedule ->
                ListItem(
                    modifier = Modifier.clickable { openedSchedule = schedule.id.toString() },
                    headlineContent = { Text(schedule.name) },
                    supportingContent = { Text(scheduleSummary(schedule)) },
                    trailingContent = if (schedule.isActive) null else {
                        { AssistChip(onClick = {}, enabled = false, label = { Text(stringResource(R.string.inactive)) }) }
                    },
                )
                HorizontalDivider()
            }
        }
        val templateItems: LazyListScope.() -> Unit = {
            item { Header(stringResource(R.string.workouts_section)) }
            if (templates.isEmpty()) item { Empty(stringResource(R.string.workouts_empty)) }
            items(templates, key = { "t" + it.id }) { template ->
                val count = template.exercises.size
                ListItem(
                    modifier = Modifier.clickable { openedTemplate = template.id.toString() },
                    headlineContent = { Text(template.name) },
                    supportingContent = { Text(pluralStringResource(R.plurals.exercise_count, count, count)) },
                )
                HorizontalDivider()
            }
        }
        LazyColumn(Modifier.padding(padding).fillMaxSize()) {
            // Bez rasporeda je glavno ono što korisnik ima: treninzi idu prvi.
            if (schedules.isEmpty()) {
                templateItems()
                scheduleItems()
            } else {
                scheduleItems()
                templateItems()
            }
        }
    }
}

/** "4 treninga, ciklus 2 od 8" ili "4 treninga, ciklus 2" (isto kao na iOS-u). */
@Composable
private fun scheduleSummary(schedule: Schedule): String {
    val workouts = schedule.items.count { it.kind == ScheduleItemKind.WORKOUT }
    val count = pluralStringResource(R.plurals.workout_count, workouts, workouts)
    val cycles = schedule.cycleCount
    return if (cycles != null) {
        stringResource(R.string.schedule_cycle_of, count, minOf(schedule.currentCycle, cycles), cycles)
    } else {
        stringResource(R.string.schedule_cycle, count, schedule.currentCycle)
    }
}

@Composable
private fun Header(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun Empty(text: String) {
    Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

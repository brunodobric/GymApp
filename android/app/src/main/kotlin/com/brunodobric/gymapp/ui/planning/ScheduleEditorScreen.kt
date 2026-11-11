package com.brunodobric.gymapp.ui.planning

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.ScheduleSnapshot
import com.brunodobric.gymapp.ui.rememberStoreRevision
import java.text.Collator
import java.util.UUID

/**
 * Uređivač rasporeda: naziv, aktivnost, broj ciklusa, podsjetnici, niz treninga i dana odmora (dodavanje,
 * redoslijed strelicama, uklanjanje, novi trening iz niza), preskočeni treninzi s Vrati, pokretanje ispočetka i brisanje. Podsjetnici su u [ScheduleReminderCard].
 * Kao na iOS-u, ✓ sprema, a natrag s promjenama pita Spremi ili Izađi bez spremanja: novi raspored ([isNew])
 * se tada briše, a postojeći vraća iz [ScheduleSnapshot] (polja, niz i izmjene ciklusa).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleEditorScreen(services: AppServices, scheduleId: UUID, isNew: Boolean = false, onClose: () -> Unit) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val schedule = remember(revision, scheduleId) { store.schedules.firstOrNull { it.id == scheduleId } }
    val engine = remember(store) { ScheduleEngine(store) }
    var name by rememberSaveable(scheduleId) { mutableStateOf(schedule?.name ?: "") }
    var picking by rememberSaveable { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var asksToSave by remember { mutableStateOf(false) }
    // Novi trening stvoren iz niza: otvara se u uređivaču, a izlazak bez spremanja ga uklanja i iz niza.
    var createdTemplate by rememberSaveable { mutableStateOf<String?>(null) }
    // Stanje pri otvaranju: snimka za "Izađi bez spremanja" i brojač spremanja za pitanje ima li promjena.
    val snapshot = remember(scheduleId) {
        store.schedules.firstOrNull { it.id == scheduleId }?.let { ScheduleSnapshot(it, store) }
    }
    val openedRevision = remember(scheduleId) { store.revision }
    val openedName = remember(scheduleId) { store.schedules.firstOrNull { it.id == scheduleId }?.name ?: "" }

    if (schedule == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }

    fun save() {
        val trimmed = name.trim()
        if (trimmed.isNotEmpty() && trimmed != schedule.name) schedule.name = trimmed
        store.save()
        onClose()
    }

    fun discard() {
        if (isNew) engine.delete(schedule) else snapshot?.restore(schedule, store)
        onClose()
    }

    fun leave() {
        val changed = isNew || revision != openedRevision || name.trim() != openedName
        if (changed) asksToSave = true else onClose()
    }

    createdTemplate?.let { id ->
        TemplateEditorScreen(
            services,
            UUID.fromString(id),
            isNew = true,
            discardNew = { engine.discardNewWorkout(it, schedule) },
            onClose = { createdTemplate = null },
        )
        return
    }
    BackHandler { leave() }

    val items = schedule.orderedItems
    val deletedName = stringResource(R.string.deleted_workout)
    val restDay = stringResource(R.string.rest_day)
    val newWorkoutName = stringResource(R.string.new_workout_name)
    val skipped = remember(revision) { engine.skippedWorkouts(schedule) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(name.ifBlank { schedule.name }) },
                navigationIcon = {
                    IconButton(onClick = { leave() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    IconButton(onClick = { confirmDelete = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete_schedule))
                    }
                    IconButton(onClick = { save() }) {
                        Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.save))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.schedule_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Card(Modifier.fillMaxWidth()) {
                ListItem(
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    headlineContent = { Text(stringResource(R.string.active)) },
                    trailingContent = {
                        Switch(checked = schedule.isActive, onCheckedChange = { engine.setActive(it, schedule) })
                    },
                )
                HorizontalDivider()
                ListItem(
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    headlineContent = { Text(stringResource(R.string.runs_until_off)) },
                    trailingContent = {
                        Switch(checked = schedule.cycleCount == null, onCheckedChange = { unlimited ->
                            schedule.cycleCount = if (unlimited) null else maxOf(schedule.currentCycle, 4)
                            store.save()
                        })
                    },
                )
                schedule.cycleCount?.let { cycles ->
                    val range = ScheduleEngine.cycleCountRange(schedule.currentCycle)
                    ListItem(
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(stringResource(R.string.cycle_count, cycles)) },
                        trailingContent = {
                            Row {
                                TextButton(enabled = cycles > range.first, onClick = {
                                    schedule.cycleCount = cycles - 1
                                    store.save()
                                }) { Text("−") }
                                TextButton(enabled = cycles < range.last, onClick = {
                                    schedule.cycleCount = cycles + 1
                                    store.save()
                                }) { Text("+") }
                            }
                        },
                    )
                }
            }

            ScheduleReminderCard(store, schedule)

            Text(stringResource(R.string.sequence), style = MaterialTheme.typography.titleMedium)
            if (items.none { it.kind == ScheduleItemKind.WORKOUT }) {
                Text(stringResource(R.string.sequence_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (items.isNotEmpty()) {
                Card(Modifier.fillMaxWidth()) {
                    items.forEachIndexed { index, item ->
                        if (index > 0) HorizontalDivider()
                        val title = when (item.kind) {
                            ScheduleItemKind.REST_DAY -> restDay
                            else -> store.templates.firstOrNull { it.id == item.workoutTemplateId }?.name ?: deletedName
                        }
                        Row(Modifier.padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                title,
                                modifier = Modifier.weight(1f),
                                color = if (item.kind == ScheduleItemKind.REST_DAY) MaterialTheme.colorScheme.onSurfaceVariant else Color.Unspecified,
                            )
                            // Preskočeni trening se može vratiti dok je ciklus u tijeku, kao na iOS-u.
                            skipped.firstOrNull { it.change.scheduleItemId == item.id }?.let { skip ->
                                Text(
                                    stringResource(R.string.skipped),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                TextButton(onClick = { engine.unskip(skip.change, schedule) }) {
                                    Text(stringResource(R.string.restore_skipped))
                                }
                            }
                            IconButton(enabled = index > 0, onClick = { engine.moveItems(schedule, listOf(index), index - 1) }) {
                                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = stringResource(R.string.move_up))
                            }
                            IconButton(enabled = index < items.lastIndex, onClick = { engine.moveItems(schedule, listOf(index), index + 2) }) {
                                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = stringResource(R.string.move_down))
                            }
                            IconButton(onClick = { engine.removeItem(item) }) {
                                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.remove))
                            }
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { picking = true }, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.add_workout)) }
                OutlinedButton(onClick = { engine.addRestDay(schedule) }, modifier = Modifier.weight(1f)) { Text(stringResource(R.string.add_rest_day)) }
            }
            TextButton(onClick = { engine.restart(schedule) }) { Text(stringResource(R.string.start_over)) }
        }
    }

    if (picking) {
        val locale = LocalConfiguration.current.locales[0]
        val templates = remember(revision, locale) {
            val collator = Collator.getInstance(locale)
            store.templates.sortedWith { a, b -> collator.compare(a.name, b.name) }
        }
        AlertDialog(
            onDismissRequest = { picking = false },
            title = { Text(stringResource(R.string.add_workout)) },
            text = {
                Column(Modifier.heightIn(max = 400.dp).verticalScroll(rememberScrollState())) {
                    ListItem(
                        modifier = Modifier.clickable {
                            picking = false
                            createdTemplate = engine.addNewWorkout(newWorkoutName, schedule).id.toString()
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        headlineContent = { Text(stringResource(R.string.new_workout)) },
                        leadingContent = { Icon(Icons.Filled.Add, contentDescription = null) },
                    )
                    templates.forEach { template ->
                        ListItem(
                            modifier = Modifier.clickable {
                                picking = false
                                engine.addWorkout(template, schedule)
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(template.name) },
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { picking = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    if (asksToSave) {
        SaveChangesDialog(
            item = EditedItem.SCHEDULE,
            isNew = isNew,
            onSave = {
                asksToSave = false
                save()
            },
            onDiscard = {
                asksToSave = false
                discard()
            },
            onDismiss = { asksToSave = false },
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_schedule_title)) },
            text = { Text(stringResource(R.string.delete_schedule_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    engine.delete(schedule)
                    onClose()
                }) { Text(stringResource(R.string.delete_schedule), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

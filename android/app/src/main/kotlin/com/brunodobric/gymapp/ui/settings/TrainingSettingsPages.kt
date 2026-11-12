package com.brunodobric.gymapp.ui.settings

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.model.UserSettings
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.model.weightSteps
import com.brunodobric.gymapp.stats.DoneExercises
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.exercises.equipmentTitle
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightUnit
import java.util.UUID

/** Vrste rekorda koje korisnik uključuje pojedinačno (`PRSettingOption` na iOS-u, vidi `PRKind.kindsFromSettings`). */
internal enum class PRSettingOption(val raw: String, val title: Int) {
    MAX_WEIGHT("maxWeight", R.string.pr_option_strength),
    MAX_VOLUME("maxVolume", R.string.pr_option_volume),
    MAX_REPS("maxReps", R.string.pr_option_reps);

    fun isOn(settings: UserSettings): Boolean = raw in settings.trackedPRKinds

    /** Uključuje ili isključuje vrstu; redoslijed u zapisu je stalan, da se postavke ne mijenjaju bez potrebe. */
    fun set(settings: UserSettings, on: Boolean) {
        val kinds = settings.trackedPRKinds.filter { it != raw } + if (on) listOf(raw) else emptyList()
        settings.trackedPRKinds = entries.map { it.raw }.filter { it in kinds }
    }
}

/** Korak s jedinicom za prikaz, npr. "2,5 kg" ili "5 lbs" (`WeightStepText` na iOS-u). */
internal fun weightStepText(step: Double, unit: WeightUnit): String = NumberInput.format(step) + " " + unit.symbol

/**
 * Postavke > Trening > Korak težine (`WeightStepsScreen` na iOS-u): korak po opremi i popis vježbi s vlastitim
 * korakom. Korak vrijedi za kotačić, gumbe + i − u obavijesti i na Početnoj.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WeightStepsPage(services: AppServices, onClose: () -> Unit) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    val unit = settings.weightUnit
    val language = catalogLanguage()
    val steps = settings.weightSteps
    val overrides = steps.overrides(unit).map { (key, step) -> Triple(key, exerciseName(services, key, language), step) }
        .sortedBy { it.second?.lowercase() ?: "" }
    val unknown = stringResource(R.string.unknown_exercise)

    fun change(edit: WeightStepSettings.() -> Unit) {
        val updated = settings.weightSteps
        updated.edit()
        settings.weightSteps = updated
        store.save()
    }

    FullScreenPage(stringResource(R.string.weight_step), onClose) {
        item { SectionHeader(stringResource(R.string.equipment)) }
        items(Equipment.entries) { equipment ->
            ChoiceRow(
                title = stringResource(equipmentTitle(equipment)),
                value = weightStepText(steps.step(equipment, unit), unit),
                options = WeightStepSettings.choices(unit),
                label = { weightStepText(it, unit) },
            ) { step -> change { setStep(step, equipment, unit) } }
        }
        item { Footer(stringResource(R.string.weight_step_footer, unit.symbol)) }
        if (overrides.isNotEmpty()) {
            item { SectionHeader(stringResource(R.string.exercises_with_own_step)) }
            items(overrides, key = { it.first }) { (key, name, step) ->
                ListItem(
                    headlineContent = { Text(name ?: unknown) },
                    supportingContent = { Text(weightStepText(step, unit)) },
                    trailingContent = {
                        TextButton(onClick = { change { setOverride(null, key, unit) } }) { Text(stringResource(R.string.by_equipment)) }
                    },
                )
            }
            item { Footer(stringResource(R.string.exercises_with_own_step_footer)) }
        }
        item {
            TextButton(
                enabled = steps.hasEquipmentSteps(unit),
                onClick = { change { Equipment.entries.forEach { setStep(null, it, unit) } } },
                modifier = Modifier.padding(horizontal = 8.dp),
            ) { Text(stringResource(R.string.restore_default_steps)) }
        }
    }
}

/** Naziv vježbe po ključu ("c:<id>" ili "u:<UUID>"); null kad vježbe više nema. */
private fun exerciseName(services: AppServices, key: String, language: String): String? = when {
    key.startsWith("c:") -> services.catalog.exercise(key.drop(2))?.displayName(language)
    key.startsWith("u:") -> runCatching { UUID.fromString(key.drop(2)) }.getOrNull()
        ?.let { id -> services.store.customExercises.firstOrNull { it.id == id }?.name }
    else -> null
}

/**
 * Postavke > Trening > Vježbe u rekordima (`RecordExercisesScreen` na iOS-u): vježbe iz odrađenih treninga, svaka
 * s prekidačem. Isključena vježba nema rekorda ni u sažetku ni u statistici, a povijest ostaje.
 */
@Composable
internal fun RecordExercisesPage(services: AppServices, onClose: () -> Unit) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    val locale = LocalConfiguration.current.locales[0]
    val done = remember(locale) { DoneExercises.fetch(store, locale) }
    var search by rememberSaveable { mutableStateOf("") }
    val items = if (search.isBlank()) done else done.filter { it.name.contains(search.trim(), ignoreCase = true) }

    FullScreenPage(stringResource(R.string.exercises_in_records), onClose) {
        item {
            OutlinedTextField(
                value = search,
                onValueChange = { search = it },
                placeholder = { Text(stringResource(R.string.exercise)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
        if (items.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.no_exercises_to_show),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp),
                )
            }
        }
        items(items, key = { it.key }) { item ->
            ListItem(
                headlineContent = { Text(item.name) },
                trailingContent = {
                    Switch(checked = item.key !in settings.prExcludedExerciseKeys, onCheckedChange = { on ->
                        settings.setRecordsEnabled(on, item.key)
                        store.save()
                    })
                },
            )
        }
        item { Footer(stringResource(R.string.exercises_in_records_footer)) }
    }
}

/**
 * Uputa za način Ne ometaj tijekom treninga (`FocusTipScreen` na iOS-u). Aplikacija ne može utišati obavijesti
 * drugih aplikacija, pa samo objašnjava kako to napraviti u Androidu.
 */
@Composable
internal fun FocusTipPage(onClose: () -> Unit) {
    FullScreenPage(stringResource(R.string.focus_title), onClose) {
        item { Footer(stringResource(R.string.focus_intro)) }
        item { SectionHeader(stringResource(R.string.focus_setup)) }
        listOf(R.string.focus_step_1, R.string.focus_step_2, R.string.focus_step_3).forEachIndexed { index, text ->
            item { ListItem(headlineContent = { Text("${index + 1}. " + stringResource(text)) }) }
        }
        item { Footer(stringResource(R.string.focus_footer)) }
    }
}

/** Podstranica postavki preko cijelog ekrana, s povratkom (sustavska gesta zatvara dijalog). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FullScreenPage(title: String, onClose: () -> Unit, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(title) },
                    navigationIcon = {
                        IconButton(onClick = onClose) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                        }
                    },
                )
            },
        ) { padding ->
            LazyColumn(Modifier.fillMaxSize().padding(padding), content = content)
        }
    }
}

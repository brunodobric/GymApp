package com.brunodobric.gymapp.ui.settings

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.brunodobric.gymapp.model.StatsDetail
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.EffortScale
import com.brunodobric.gymapp.model.EquipmentPreset
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.OnboardingAnswers
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.ui.onboarding.sexTitle
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.training.PlateCalculator
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightUnit

/**
 * Postavke > Profil: cilj, dani tjedno, iskustvo i oprema, isti podaci kao u onboardingu. Gotovi programi
 * prema njima biraju ponavljanja i vježbe. Spol i prijedlog rasporeda su kao na iOS-u.
 */
@Composable
fun ProfileSettingsSection(services: AppServices, onSuggestSchedule: () -> Unit) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    val none = stringResource(R.string.no_answer)

    ChoiceRow(
        title = stringResource(R.string.goal),
        value = settings.goal?.let { stringResource(goalTitle(it)) } ?: none,
        options = listOf(null) + TrainingGoal.entries,
        label = { it?.let { goal -> stringResource(goalTitle(goal)) } ?: none },
    ) {
        settings.goal = it
        store.save()
    }
    ChoiceRow(
        title = stringResource(R.string.days_per_week),
        value = settings.trainingDaysPerWeek?.toString() ?: none,
        options = listOf(null) + OnboardingAnswers.DAYS_PER_WEEK_RANGE.toList(),
        label = { it?.toString() ?: none },
    ) {
        settings.trainingDaysPerWeek = it
        store.save()
    }
    ChoiceRow(
        title = stringResource(R.string.experience),
        value = settings.experience?.let { stringResource(experienceTitle(it)) } ?: none,
        options = listOf(null) + ExperienceLevel.entries,
        label = { it?.let { level -> stringResource(experienceTitle(level)) } ?: none },
    ) {
        settings.experience = it
        store.save()
    }
    Footer(stringResource(R.string.experience_footer))

    SectionHeader(stringResource(R.string.where_you_train))
    val selected = EquipmentPreset.matching(settings.equipment)
    EquipmentPreset.entries.forEach { preset ->
        ListItem(
            modifier = Modifier.clickable {
                settings.equipment = preset.equipment
                store.save()
            },
            headlineContent = { Text(stringResource(presetTitle(preset))) },
            supportingContent = { Text(stringResource(presetDetail(preset))) },
            trailingContent = if (selected == preset) {
                { Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
            } else {
                null
            },
        )
    }
    Footer(stringResource(R.string.equipment_footer))

    ChoiceRow(
        title = stringResource(R.string.sex),
        value = settings.sex?.let { stringResource(sexTitle(it)) } ?: none,
        options = listOf(null) + Sex.entries,
        label = { it?.let { sex -> stringResource(sexTitle(sex)) } ?: none },
    ) {
        settings.sex = it
        store.save()
    }
    Footer(stringResource(R.string.sex_footer))
    ListItem(
        modifier = Modifier.clickable(onClick = onSuggestSchedule),
        headlineContent = { Text(stringResource(R.string.suggest_schedule)) },
    )
    Footer(stringResource(R.string.suggest_schedule_footer))
}

/** Postavke > Trening: jedinice, korak težine, napor, zadana pauza, rekordi i prikaz statistike (kao na iOS-u). */
@Composable
fun TrainingSettingsSection(services: AppServices) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    var page by rememberSaveable { mutableStateOf<String?>(null) }
    when (page) {
        PAGE_WEIGHT_STEPS -> WeightStepsPage(services, onClose = { page = null })
        PAGE_RECORD_EXERCISES -> RecordExercisesPage(services, onClose = { page = null })
    }

    ChoiceRow(
        title = stringResource(R.string.units),
        value = stringResource(unitTitle(settings.weightUnit)),
        options = WeightUnit.entries,
        label = { stringResource(unitTitle(it)) },
    ) {
        settings.weightUnit = it
        store.save()
    }
    ListItem(
        modifier = Modifier.clickable { page = PAGE_WEIGHT_STEPS },
        headlineContent = { Text(stringResource(R.string.weight_step)) },
    )
    // Napor serije kao RPE ili RIR (RIR = 10 − RPE), kao na iOS-u. Sprema se uvijek kao RPE.
    ChoiceRow(
        title = stringResource(R.string.effort),
        value = effortTitle(settings.effortScale),
        options = EffortScale.entries,
        label = { effortTitle(it) },
    ) {
        settings.effortScale = it
        store.save()
    }
    RestRow(stringResource(R.string.compound_exercises), settings.compoundRestSeconds) {
        settings.compoundRestSeconds = it
        store.save()
    }
    RestRow(stringResource(R.string.other_exercises), settings.defaultRestSeconds) {
        settings.defaultRestSeconds = it
        store.save()
    }
    Footer(stringResource(R.string.rest_footer))
    ListItem(
        headlineContent = { Text(stringResource(R.string.rest_end_sound)) },
        trailingContent = {
            Switch(checked = settings.restEndSoundEnabled, onCheckedChange = {
                settings.restEndSoundEnabled = it
                store.save()
            })
        },
    )
    SectionHeader(stringResource(R.string.records))
    ListItem(
        headlineContent = { Text(stringResource(R.string.records_pr)) },
        trailingContent = {
            Switch(checked = settings.prEnabled, onCheckedChange = {
                settings.prEnabled = it
                store.save()
            })
        },
    )
    if (settings.prEnabled) {
        PRSettingOption.entries.forEach { option ->
            ListItem(
                modifier = Modifier.padding(start = 16.dp),
                headlineContent = { Text(stringResource(option.title)) },
                trailingContent = {
                    Switch(checked = option.isOn(settings), onCheckedChange = { on ->
                        option.set(settings, on)
                        store.save()
                    })
                },
            )
        }
        val excluded = settings.prExcludedExerciseKeys.size
        ListItem(
            modifier = Modifier.clickable { page = PAGE_RECORD_EXERCISES },
            headlineContent = { Text(stringResource(R.string.exercises_in_records)) },
            trailingContent = {
                Text(
                    if (excluded == 0) stringResource(R.string.filter_all) else stringResource(R.string.excluded_count, excluded),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
        )
    }
    Footer(stringResource(R.string.records_footer))

    SectionHeader(stringResource(R.string.tab_statistics))
    ChoiceRow(
        title = stringResource(R.string.stats_detail),
        value = stringResource(statsDetailTitle(settings.statsDetail)),
        options = StatsDetail.entries,
        label = { stringResource(statsDetailTitle(it)) },
    ) {
        settings.statsDetail = it
        store.save()
    }
    Footer(stringResource(R.string.stats_detail_footer))
}

private const val PAGE_WEIGHT_STEPS = "weightSteps"
private const val PAGE_RECORD_EXERCISES = "recordExercises"

@StringRes
private fun statsDetailTitle(detail: StatsDetail): Int = when (detail) {
    StatsDetail.BASIC -> R.string.stats_basic
    StatsDetail.PRO -> R.string.stats_detailed
}

/** Šipka (5 do 30 kg, korak 2,5 kg) i ploče koje korisnik ima, za kalkulator ploča. Sve u kg, kao na iOS-u. */
@Composable
internal fun PlatesSettingsSection(services: AppServices) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    val barbell = settings.barbellWeightKg
    ListItem(
        headlineContent = { Text(stringResource(R.string.barbell)) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = barbell > 5.0, onClick = {
                    settings.barbellWeightKg = maxOf(5.0, barbell - 2.5)
                    store.save()
                }) { Text("−") }
                Text(NumberInput.format(barbell) + " kg")
                TextButton(enabled = barbell < 30.0, onClick = {
                    settings.barbellWeightKg = minOf(30.0, barbell + 2.5)
                    store.save()
                }) { Text("+") }
            }
        },
    )
    val available = settings.availablePlatesKg
    PLATE_OPTIONS.forEach { plate ->
        ListItem(
            headlineContent = { Text(NumberInput.format(plate) + " kg") },
            trailingContent = {
                Switch(checked = available.any { it == plate }, onCheckedChange = { enabled ->
                    settings.availablePlatesKg = PlateCalculator.setting(plate, enabled, settings.availablePlatesKg)
                    store.save()
                })
            },
        )
    }
    Footer(stringResource(R.string.plates_footer))
}

private val PLATE_OPTIONS = listOf(0.5, 1.25, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0)

/** Red s trenutnom vrijednošću; dodir otvara izbornik s ponuđenim vrijednostima. */
@Composable
internal fun <T> ChoiceRow(title: String, value: String, options: List<T>, label: @Composable (T) -> String, onSelect: (T) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ListItem(
            modifier = Modifier.clickable { expanded = true },
            headlineContent = { Text(title) },
            trailingContent = { Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant) },
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(label(option)) },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                )
            }
        }
    }
}

/** Pauza u koracima od 15 s, od 15 s do 10 min. */
@Composable
private fun RestRow(title: String, seconds: Int, onChange: (Int) -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = seconds > 15, onClick = { onChange(seconds - 15) }) { Text("−") }
                Text(DurationInput.format(seconds))
                TextButton(enabled = seconds < 600, onClick = { onChange(seconds + 15) }) { Text("+") }
            }
        },
    )
}

@Composable
internal fun Footer(text: String) {
    Column {
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }
}

@StringRes
internal fun goalTitle(goal: TrainingGoal): Int = when (goal) {
    TrainingGoal.HYPERTROPHY -> R.string.goal_hypertrophy
    TrainingGoal.STRENGTH -> R.string.goal_strength
    TrainingGoal.RECOMPOSITION -> R.string.goal_recomposition
    TrainingGoal.GENERAL_FITNESS -> R.string.goal_general_fitness
}

@StringRes
internal fun experienceTitle(level: ExperienceLevel): Int = when (level) {
    ExperienceLevel.BEGINNER -> R.string.level_beginner
    ExperienceLevel.INTERMEDIATE -> R.string.level_intermediate
    ExperienceLevel.ADVANCED -> R.string.level_advanced
}

@StringRes
internal fun presetTitle(preset: EquipmentPreset): Int = when (preset) {
    EquipmentPreset.GYM -> R.string.preset_gym
    EquipmentPreset.HOME_GYM -> R.string.preset_home_gym
    EquipmentPreset.DUMBBELLS -> R.string.preset_dumbbells
    EquipmentPreset.BODYWEIGHT_ONLY -> R.string.preset_bodyweight
}

@StringRes
internal fun presetDetail(preset: EquipmentPreset): Int = when (preset) {
    EquipmentPreset.GYM -> R.string.preset_gym_detail
    EquipmentPreset.HOME_GYM -> R.string.preset_home_gym_detail
    EquipmentPreset.DUMBBELLS -> R.string.preset_dumbbells_detail
    EquipmentPreset.BODYWEIGHT_ONLY -> R.string.preset_bodyweight_detail
}

@StringRes
internal fun unitTitle(unit: WeightUnit): Int = when (unit) {
    WeightUnit.KILOGRAMS -> R.string.kilograms
    WeightUnit.POUNDS -> R.string.pounds
}

/** Obavijest o kraju odmora (`NotificationSettingsSection` na iOS-u). Podsjetnici rasporeda dolaze kasnije. */
@Composable
internal fun NotificationSettingsSection(services: AppServices) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()
    ListItem(
        headlineContent = { Text(stringResource(R.string.schedule_reminders)) },
        trailingContent = {
            Switch(checked = settings.notificationsEnabled, onCheckedChange = {
                settings.notificationsEnabled = it
                store.save()
            })
        },
    )
    ListItem(
        headlineContent = { Text(stringResource(R.string.rest_end)) },
        trailingContent = {
            Switch(checked = settings.restNotificationEnabled, onCheckedChange = {
                settings.restNotificationEnabled = it
                store.save()
            })
        },
    )
    var showsFocusTip by rememberSaveable { mutableStateOf(false) }
    ListItem(
        modifier = Modifier.clickable { showsFocusTip = true },
        headlineContent = { Text(stringResource(R.string.focus_during_workout)) },
    )
    Footer(stringResource(R.string.rest_notification_footer))
    if (showsFocusTip) FocusTipPage(onClose = { showsFocusTip = false })
}

private fun effortTitle(scale: EffortScale): String = if (scale == EffortScale.RPE) "RPE" else "RIR"

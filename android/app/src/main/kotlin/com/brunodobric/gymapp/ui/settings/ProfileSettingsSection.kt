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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.EquipmentPreset
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.OnboardingAnswers
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.units.DurationInput
import com.brunodobric.gymapp.units.WeightUnit

/**
 * Postavke > Profil: cilj, dani tjedno, iskustvo i oprema, isti podaci kao u onboardingu. Gotovi programi
 * prema njima biraju ponavljanja i vježbe. Spol i prijedlog rasporeda s iOS-a dolaze kasnije.
 */
@Composable
fun ProfileSettingsSection(services: AppServices) {
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
}

/** Postavke > Trening: jedinice, zadana pauza i rekordi. */
@Composable
fun TrainingSettingsSection(services: AppServices) {
    val store = services.store
    rememberStoreRevision(store)
    val settings = store.settings()

    ChoiceRow(
        title = stringResource(R.string.units),
        value = stringResource(unitTitle(settings.weightUnit)),
        options = WeightUnit.entries,
        label = { stringResource(unitTitle(it)) },
    ) {
        settings.weightUnit = it
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
        headlineContent = { Text(stringResource(R.string.records_pr)) },
        trailingContent = {
            Switch(checked = settings.prEnabled, onCheckedChange = {
                settings.prEnabled = it
                store.save()
            })
        },
    )
}

/** Red s trenutnom vrijednošću; dodir otvara izbornik s ponuđenim vrijednostima. */
@Composable
private fun <T> ChoiceRow(title: String, value: String, options: List<T>, label: @Composable (T) -> String, onSelect: (T) -> Unit) {
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
private fun Footer(text: String) {
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
private fun goalTitle(goal: TrainingGoal): Int = when (goal) {
    TrainingGoal.HYPERTROPHY -> R.string.goal_hypertrophy
    TrainingGoal.STRENGTH -> R.string.goal_strength
    TrainingGoal.RECOMPOSITION -> R.string.goal_recomposition
    TrainingGoal.GENERAL_FITNESS -> R.string.goal_general_fitness
}

@StringRes
private fun experienceTitle(level: ExperienceLevel): Int = when (level) {
    ExperienceLevel.BEGINNER -> R.string.level_beginner
    ExperienceLevel.INTERMEDIATE -> R.string.level_intermediate
    ExperienceLevel.ADVANCED -> R.string.level_advanced
}

@StringRes
private fun presetTitle(preset: EquipmentPreset): Int = when (preset) {
    EquipmentPreset.GYM -> R.string.preset_gym
    EquipmentPreset.HOME_GYM -> R.string.preset_home_gym
    EquipmentPreset.DUMBBELLS -> R.string.preset_dumbbells
    EquipmentPreset.BODYWEIGHT_ONLY -> R.string.preset_bodyweight
}

@StringRes
private fun presetDetail(preset: EquipmentPreset): Int = when (preset) {
    EquipmentPreset.GYM -> R.string.preset_gym_detail
    EquipmentPreset.HOME_GYM -> R.string.preset_home_gym_detail
    EquipmentPreset.DUMBBELLS -> R.string.preset_dumbbells_detail
    EquipmentPreset.BODYWEIGHT_ONLY -> R.string.preset_bodyweight_detail
}

@StringRes
private fun unitTitle(unit: WeightUnit): Int = when (unit) {
    WeightUnit.KILOGRAMS -> R.string.kilograms
    WeightUnit.POUNDS -> R.string.pounds
}

package com.brunodobric.gymapp.ui.onboarding

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.annotation.StringRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.PermissionController
import com.brunodobric.gymapp.ApolonApplication
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.rawValueOf
import com.brunodobric.gymapp.health.HealthConnect
import com.brunodobric.gymapp.model.EquipmentPreset
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.OnboardingAnswers
import com.brunodobric.gymapp.model.OnboardingApplier
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.planning.Program
import com.brunodobric.gymapp.planning.ProgramLibrary
import com.brunodobric.gymapp.planning.ProgramRecommender
import com.brunodobric.gymapp.planning.RecommendationReason
import com.brunodobric.gymapp.planning.TrainingProfile
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.planning.installProgram
import com.brunodobric.gymapp.ui.planning.programDetails
import com.brunodobric.gymapp.ui.planning.programTitle
import com.brunodobric.gymapp.ui.settings.experienceTitle
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightUnit

private enum class Step { TRAINING, ABOUT, RECOMMENDATION }

/**
 * Onboarding kao donji list preko Početne (`OnboardingScreen` na iOS-u), u dva kratka koraka: "Kako treniraš?"
 * (cilj, dani, oprema) i "Još malo o tebi" (iskustvo, težina, spol, Health Connect). Sve je neobavezno i bira se
 * dodirom. Ako je korisnik odgovorio o treningu, isti list nudi gotov raspored.
 *
 * Isti list otvara i kartica "Postavi profil" na Početnoj ([initial] su tada odgovori iz postavki).
 * "Preskoči" i zatvaranje lista spremaju samo da je onboarding obavljen i odgovor o zdravstvenim podacima.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingSheet(services: AppServices, initial: OnboardingAnswers = OnboardingAnswers(), onClose: () -> Unit = {}) {
    val store = services.store
    val context = LocalContext.current
    val language = catalogLanguage()
    val locale = LocalConfiguration.current.locales[0]
    // Odgovori su sirove vrijednosti, da prežive okretanje ekrana.
    var stepName by rememberSaveable { mutableStateOf(Step.TRAINING.name) }
    var goalRaw by rememberSaveable { mutableStateOf(initial.goal?.raw) }
    var days by rememberSaveable { mutableStateOf(initial.daysPerWeek) }
    var experienceRaw by rememberSaveable { mutableStateOf(initial.experience?.raw) }
    var equipmentRaw by rememberSaveable { mutableStateOf(initial.equipment.joinToString(",") { it.raw }) }
    var unitRaw by rememberSaveable { mutableStateOf(initial.unit.raw) }
    var weightText by rememberSaveable { mutableStateOf("") }
    var sexRaw by rememberSaveable { mutableStateOf(initial.sex?.raw) }
    var wantsHealth by rememberSaveable { mutableStateOf(initial.wantsHealthKit) }
    var pendingProgramId by rememberSaveable { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    var finished by remember { mutableStateOf(false) }
    val step = Step.valueOf(stepName)

    val unit = WeightUnit.entries.firstOrNull { it.raw == unitRaw } ?: WeightUnit.KILOGRAMS
    val equipment = equipmentRaw.split(",").mapNotNull { rawValueOf<com.brunodobric.gymapp.catalog.Equipment>(it) }
    val answers = OnboardingAnswers(
        goal = rawValueOf<TrainingGoal>(goalRaw),
        sex = rawValueOf<Sex>(sexRaw),
        unit = unit,
        weight = NumberInput.parse(weightText, locale),
        wantsHealthKit = wantsHealth,
        experience = rawValueOf<ExperienceLevel>(experienceRaw),
        equipment = equipment,
        daysPerWeek = days,
    )
    val profile = TrainingProfile.from(answers)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val healthRequest = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        wantsHealth = granted.containsAll(HealthConnect.WRITE_PERMISSIONS)
    }

    fun finish() {
        finished = true
        if (wantsHealth) (context.applicationContext as ApolonApplication).health.sync()
        onClose()
    }

    /** "Preskoči" i zatvaranje lista: od odgovora se sprema samo onaj o zdravstvenim podacima. */
    fun skip() {
        if (finished) return
        runCatching { OnboardingApplier(store).skip(wantsHealthKit = wantsHealth) }
        finish()
    }

    /** Sprema odgovore (onboarding je time obavljen) i po želji dodaje program. */
    fun complete(program: Program?, newDaysGoal: Int? = null) {
        try {
            val final = if (newDaysGoal != null) answers.copy(daysPerWeek = newDaysGoal) else answers
            OnboardingApplier(store).apply(final)
            program?.let { installProgram(services, context, language, it, TrainingProfile.from(final)) }
            finish()
        } catch (_: Exception) {
            failed = true
        }
    }

    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            text = { Text(stringResource(R.string.answers_failed)) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(stringResource(R.string.ok)) } },
        )
    }

    val pending = pendingProgramId?.let { id -> ProgramLibrary.all.firstOrNull { it.id == id } }
    val lower = pending?.let(profile::lowerDaysGoal)
    val goal = profile.daysPerWeek
    if (pending != null && lower != null && goal != null) {
        AlertDialog(
            onDismissRequest = { pendingProgramId = null },
            title = { Text(stringResource(R.string.days_goal_title)) },
            text = { Text(stringResource(R.string.days_goal_message, lower, goal)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingProgramId = null
                    complete(pending, newDaysGoal = lower)
                }) { Text(stringResource(R.string.days_goal_lower, lower)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    pendingProgramId = null
                    complete(pending)
                }) { Text(stringResource(R.string.days_goal_keep, goal)) }
            },
        )
    }

    ModalBottomSheet(onDismissRequest = { skip() }, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
        ) {
            when (step) {
                Step.TRAINING -> {
                    SheetHeader(progress = 1, onBack = null, onSkip = { skip() })
                    SheetTitle(R.string.onboarding_training_title, R.string.onboarding_training_subtitle)
                    FieldLabel(R.string.goal)
                    ChoiceGrid(TrainingGoal.entries, rawValueOf<TrainingGoal>(goalRaw), { goalRaw = it?.raw }) {
                        stringResource(goalShortTitle(it))
                    }
                    FieldLabel(R.string.days_per_week)
                    DaysPicker(days) { days = it }
                    FieldLabel(R.string.where_you_train)
                    ChoiceGrid(EquipmentPreset.entries, EquipmentPreset.matching(equipment), { preset ->
                        equipmentRaw = preset?.equipment?.joinToString(",") { it.raw } ?: ""
                    }) { stringResource(presetShortTitle(it)) }
                    PrimaryButton(R.string.next) { stepName = Step.ABOUT.name }
                }
                Step.ABOUT -> {
                    SheetHeader(progress = 2, onBack = { stepName = Step.TRAINING.name }, onSkip = { skip() })
                    SheetTitle(R.string.onboarding_about_title, R.string.onboarding_about_subtitle)
                    FieldLabel(R.string.experience)
                    val experience = rawValueOf<ExperienceLevel>(experienceRaw)
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        ExperienceLevel.entries.forEachIndexed { index, level ->
                            SegmentedButton(
                                selected = experience == level,
                                onClick = { experienceRaw = if (experience == level) null else level.raw },
                                shape = SegmentedButtonDefaults.itemShape(index, ExperienceLevel.entries.size),
                                icon = {},
                            ) { Text(stringResource(experienceTitle(level)), maxLines = 1) }
                        }
                    }
                    experience?.let {
                        Text(
                            stringResource(experienceDetail(it)),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 6.dp),
                        )
                    }
                    FieldLabel(R.string.body_weight)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedTextField(
                            value = weightText,
                            onValueChange = { weightText = it },
                            placeholder = { Text(stringResource(R.string.optional)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.weight(1f).semantics { contentDescription = context.getString(R.string.body_weight) },
                        )
                        SingleChoiceSegmentedButtonRow(Modifier.width(140.dp)) {
                            WeightUnit.entries.forEachIndexed { index, option ->
                                SegmentedButton(
                                    selected = unit == option,
                                    onClick = { unitRaw = option.raw },
                                    shape = SegmentedButtonDefaults.itemShape(index, WeightUnit.entries.size),
                                    icon = {},
                                ) { Text(option.symbol) }
                            }
                        }
                    }
                    FieldLabel(R.string.sex)
                    ChoiceGrid(Sex.entries, rawValueOf<Sex>(sexRaw), { sexRaw = it?.raw }) { stringResource(sexTitle(it)) }
                    Text(
                        stringResource(R.string.onboarding_sex_footer),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                    if (HealthConnect.isAvailable(context)) {
                        Spacer(Modifier.height(16.dp))
                        HealthRow(connected = wantsHealth, onConnect = { healthRequest.launch(HealthConnect.PERMISSIONS) })
                    }
                    PrimaryButton(if (profile.hasAnswers) R.string.show_suggestion else R.string.done) {
                        // Prijedlog samo kad ima na temelju čega, inače list odmah završava.
                        if (profile.hasAnswers) stepName = Step.RECOMMENDATION.name else complete(null)
                    }
                }
                Step.RECOMMENDATION -> {
                    SheetHeader(progress = null, onBack = { stepName = Step.ABOUT.name }, onSkip = null)
                    SheetTitle(R.string.your_suggestion, R.string.based_on_your_answers)
                    Spacer(Modifier.height(16.dp))
                    RecommendationCards(profile) { program ->
                        if (profile.lowerDaysGoal(program) != null) pendingProgramId = program.id else complete(program)
                    }
                    TextButton(onClick = { complete(null) }, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 16.dp)) {
                        Text(stringResource(R.string.build_myself))
                    }
                    Text(
                        stringResource(R.string.all_programs_in_schedules),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.align(Alignment.CenterHorizontally),
                    )
                }
            }
        }
    }
}

@Composable
private fun SheetHeader(progress: Int?, onBack: (() -> Unit)?, onSkip: (() -> Unit)?) {
    Box(Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        if (onBack != null) {
            TextButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.back))
            }
        }
        if (progress != null) {
            val description = stringResource(R.string.step_of_two, progress)
            Row(
                Modifier.align(Alignment.Center).semantics { contentDescription = description },
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                (1..2).forEach { index ->
                    Surface(
                        shape = CircleShape,
                        color = if (index <= progress) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.width(20.dp).height(4.dp),
                    ) {}
                }
            }
        }
        if (onSkip != null) {
            TextButton(onClick = onSkip, modifier = Modifier.align(Alignment.CenterEnd)) { Text(stringResource(R.string.skip)) }
        }
    }
}

@Composable
private fun SheetTitle(@StringRes title: Int, @StringRes subtitle: Int) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.headlineSmall,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(top = 8.dp).semantics { heading() },
    )
    Text(stringResource(subtitle), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun FieldLabel(@StringRes text: Int) {
    Text(
        stringResource(text),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 16.dp, bottom = 6.dp),
    )
}

@Composable
private fun PrimaryButton(@StringRes text: Int, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().padding(top = 20.dp).heightIn(min = 52.dp)) {
        Text(stringResource(text))
    }
}

/** Izbor jednog odgovora kao kartice u dva stupca. Ponovni dodir poništava odabir. */
@Composable
private fun <T> ChoiceGrid(items: List<T>, selected: T?, onSelect: (T?) -> Unit, label: @Composable (T) -> String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { item ->
                    val isSelected = item == selected
                    Surface(
                        selected = isSelected,
                        onClick = { onSelect(if (isSelected) null else item) },
                        shape = RoundedCornerShape(12.dp),
                        color = if (isSelected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh,
                        contentColor = if (isSelected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface,
                        border = if (isSelected) BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary) else null,
                        modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                    ) {
                        Box(contentAlignment = Alignment.CenterStart, modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp)) {
                            Text(label(item), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** Dani tjedno kao krugovi od 1 do 7. Ponovni dodir poništava odabir. */
@Composable
private fun DaysPicker(days: Int?, onChange: (Int?) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        OnboardingAnswers.DAYS_PER_WEEK_RANGE.forEach { day ->
            val isSelected = days == day
            val description = stringResource(R.string.reason_days, day)
            Surface(
                selected = isSelected,
                onClick = { onChange(if (isSelected) null else day) },
                shape = CircleShape,
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh,
                contentColor = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f).widthIn(max = 48.dp).aspectRatio(1f).semantics { contentDescription = description },
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(day.toString(), style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
}

/** Health Connect kao jedan redak: sustavski list dozvola otvara se tek na dodir "Poveži". */
@Composable
private fun HealthRow(connected: Boolean, onConnect: () -> Unit) {
    Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Favorite, contentDescription = null, tint = Color(0xFFFF2D55), modifier = Modifier.size(24.dp))
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(stringResource(R.string.health_connect), style = MaterialTheme.typography.titleSmall)
                Text(
                    stringResource(R.string.onboarding_health_detail),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (connected) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.connected), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
            } else {
                OutlinedButton(onClick = onConnect) { Text(stringResource(R.string.connect)) }
            }
        }
    }
}

/**
 * Prijedlog u onboardingu: najbolji program kao istaknuta kartica s tipkom, a druge opcije kao reci (dodir
 * dodaje program).
 */
@Composable
private fun RecommendationCards(profile: TrainingProfile, onChoose: (Program) -> Unit) {
    val items = remember(profile) { ProgramRecommender.recommend(profile) }
    items.firstOrNull()?.let { best ->
        Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.best_match).uppercase(), style = MaterialTheme.typography.labelMedium)
                Text(stringResource(programTitle(best.program)), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(stringResource(programDetails(best.program)), style = MaterialTheme.typography.bodyMedium)
                if (best.reasons.isNotEmpty()) {
                    Text(best.reasons.map { reasonText(it) }.joinToString(", "), style = MaterialTheme.typography.bodySmall)
                }
                Button(
                    onClick = { onChoose(best.program) },
                    colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.onPrimary,
                        contentColor = MaterialTheme.colorScheme.primary,
                    ),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                ) { Text(stringResource(R.string.add_and_activate)) }
            }
        }
    }
    if (items.size > 1) {
        Text(
            stringResource(R.string.or),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 20.dp, bottom = 4.dp),
        )
        items.drop(1).forEach { item ->
            Surface(onClick = { onChoose(item.program) }, color = Color.Transparent) {
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(programTitle(item.program)), style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(programDetails(item.program)),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(stringResource(R.string.add), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
                }
            }
            HorizontalDivider()
        }
    }
}

@StringRes
private fun goalShortTitle(goal: TrainingGoal): Int = when (goal) {
    TrainingGoal.HYPERTROPHY -> R.string.goal_short_hypertrophy
    TrainingGoal.STRENGTH -> R.string.goal_strength
    TrainingGoal.RECOMPOSITION -> R.string.goal_recomposition
    TrainingGoal.GENERAL_FITNESS -> R.string.goal_short_general_fitness
}

@StringRes
private fun presetShortTitle(preset: EquipmentPreset): Int = when (preset) {
    EquipmentPreset.GYM -> R.string.preset_short_gym
    EquipmentPreset.HOME_GYM -> R.string.preset_home_gym
    EquipmentPreset.DUMBBELLS -> R.string.preset_dumbbells
    EquipmentPreset.BODYWEIGHT_ONLY -> R.string.preset_bodyweight
}

@StringRes
private fun experienceDetail(level: ExperienceLevel): Int = when (level) {
    ExperienceLevel.BEGINNER -> R.string.experience_detail_beginner
    ExperienceLevel.INTERMEDIATE -> R.string.experience_detail_intermediate
    ExperienceLevel.ADVANCED -> R.string.experience_detail_advanced
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
/** Prijedlog gotovih programa u Postavke > Profil (onboarding ima svoj prikaz u listu). */
internal fun RecommendationPage(
    profile: TrainingProfile,
    onBack: () -> Unit,
    onChoose: (Program) -> Unit,
) {
    val recommendations = remember(profile) { ProgramRecommender.recommend(profile) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.suggested_schedule)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            recommendations.forEachIndexed { index, item ->
                Text(
                    stringResource(if (index == 0) R.string.recommended else R.string.other_option),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(programTitle(item.program)), style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(programDetails(item.program)),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (item.reasons.isNotEmpty()) {
                            Text(
                                item.reasons.map { reasonText(it) }.joinToString(", "),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (index == 0) {
                            Button(onClick = { onChoose(item.program) }) { Text(stringResource(R.string.add_and_activate)) }
                        } else {
                            OutlinedButton(onClick = { onChoose(item.program) }) { Text(stringResource(R.string.add_and_activate)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun reasonText(reason: RecommendationReason): String = when (reason) {
    is RecommendationReason.Days -> stringResource(R.string.reason_days, reason.days)
    is RecommendationReason.Goal -> stringResource(
        when (reason.goal) {
            TrainingGoal.HYPERTROPHY -> R.string.reason_goal_hypertrophy
            TrainingGoal.STRENGTH -> R.string.reason_goal_strength
            TrainingGoal.RECOMPOSITION -> R.string.reason_goal_recomposition
            TrainingGoal.GENERAL_FITNESS -> R.string.reason_goal_general_fitness
        },
    )
    is RecommendationReason.Level -> stringResource(
        when (reason.level) {
            ExperienceLevel.BEGINNER -> R.string.reason_level_beginner
            ExperienceLevel.INTERMEDIATE -> R.string.reason_level_intermediate
            ExperienceLevel.ADVANCED -> R.string.reason_level_advanced
        },
    )
    RecommendationReason.EquipmentFits -> stringResource(R.string.reason_equipment)
}

@StringRes
internal fun sexTitle(sex: Sex): Int = when (sex) {
    Sex.FEMALE -> R.string.sex_female
    Sex.MALE -> R.string.sex_male
}


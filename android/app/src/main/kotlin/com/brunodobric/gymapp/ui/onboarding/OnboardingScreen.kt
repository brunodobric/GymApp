package com.brunodobric.gymapp.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
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
import com.brunodobric.gymapp.ui.settings.ChoiceRow
import com.brunodobric.gymapp.ui.settings.Footer
import com.brunodobric.gymapp.ui.settings.SectionHeader
import com.brunodobric.gymapp.ui.settings.experienceTitle
import com.brunodobric.gymapp.ui.settings.goalTitle
import com.brunodobric.gymapp.ui.settings.presetDetail
import com.brunodobric.gymapp.ui.settings.presetTitle
import com.brunodobric.gymapp.ui.settings.unitTitle
import com.brunodobric.gymapp.units.NumberInput
import com.brunodobric.gymapp.units.WeightUnit

/**
 * Prvo pokretanje, kao `OnboardingScreen` na iOS-u: jedna stranica s profilom treninga i tijelom, pa prijedlog
 * gotovog rasporeda kad je korisnik odgovorio o treningu, i na kraju zaslon o Health Connectu (ako je na
 * uređaju), s izričitim pristankom ili odbijanjem. Sve osim jedinica je neobavezno.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingScreen(services: AppServices) {
    val store = services.store
    val context = LocalContext.current
    val language = catalogLanguage()
    val locale = LocalConfiguration.current.locales[0]
    // Odgovori su sirove vrijednosti, da prežive okretanje ekrana.
    var goalRaw by rememberSaveable { mutableStateOf<String?>(null) }
    var days by rememberSaveable { mutableStateOf<Int?>(null) }
    var experienceRaw by rememberSaveable { mutableStateOf<String?>(null) }
    var presetRaw by rememberSaveable { mutableStateOf<String?>(null) }
    var unitRaw by rememberSaveable { mutableStateOf(WeightUnit.KILOGRAMS.raw) }
    var heightText by rememberSaveable { mutableStateOf("") }
    var weightText by rememberSaveable { mutableStateOf("") }
    var sexRaw by rememberSaveable { mutableStateOf<String?>(null) }
    var showsRecommendation by rememberSaveable { mutableStateOf(false) }
    var pendingProgramId by rememberSaveable { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    // Odabir prije zaslona o Health Connectu: preskočeno, program i novi cilj dana.
    var showsHealth by rememberSaveable { mutableStateOf(false) }
    var skipped by rememberSaveable { mutableStateOf(false) }
    var chosenProgramId by rememberSaveable { mutableStateOf<String?>(null) }
    var chosenDaysGoal by rememberSaveable { mutableStateOf<Int?>(null) }

    val unit = WeightUnit.entries.firstOrNull { it.raw == unitRaw } ?: WeightUnit.KILOGRAMS
    val preset = EquipmentPreset.entries.firstOrNull { it.raw == presetRaw }
    val answers = OnboardingAnswers(
        goal = rawValueOf<TrainingGoal>(goalRaw),
        sex = rawValueOf<Sex>(sexRaw),
        unit = unit,
        heightCm = NumberInput.parse(heightText, locale),
        weight = NumberInput.parse(weightText, locale),
        experience = rawValueOf<ExperienceLevel>(experienceRaw),
        equipment = preset?.equipment ?: emptyList(),
        daysPerWeek = days,
    )
    val profile = TrainingProfile.from(answers)

    /** Sprema odgovore (onboarding je time obavljen i zaslon se zatvara) i po želji dodaje program. */
    fun complete(wantsHealth: Boolean) {
        try {
            if (skipped) {
                OnboardingApplier(store).skip(wantsHealthKit = wantsHealth)
            } else {
                val goal = chosenDaysGoal
                val final = (if (goal != null) answers.copy(daysPerWeek = goal) else answers).copy(wantsHealthKit = wantsHealth)
                OnboardingApplier(store).apply(final)
                val program = chosenProgramId?.let { id -> ProgramLibrary.all.firstOrNull { it.id == id } }
                program?.let { installProgram(services, context, language, it, TrainingProfile.from(final)) }
            }
            if (wantsHealth) (context.applicationContext as ApolonApplication).health.sync()
        } catch (_: Exception) {
            failed = true
        }
    }

    /** Zaslon o Health Connectu, ako je Health Connect na uređaju; inače onboarding odmah završava. */
    fun askHealth() {
        if (HealthConnect.isAvailable(context)) showsHealth = true else complete(wantsHealth = false)
    }

    /** Odabir u prijedlogu. Novi cilj dana tjedno kad je korisnik u upozorenju pristao smanjiti ga. */
    fun choose(program: Program?, newDaysGoal: Int? = null) {
        chosenProgramId = program?.id
        chosenDaysGoal = newDaysGoal
        askHealth()
    }

    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            text = { Text(stringResource(R.string.answers_failed)) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(stringResource(R.string.ok)) } },
        )
    }

    if (showsHealth) {
        val back = {
            showsHealth = false
            skipped = false
        }
        BackHandler { back() }
        HealthPage(onBack = back, onAnswer = { complete(wantsHealth = it) })
        return
    }

    if (showsRecommendation) {
        BackHandler { showsRecommendation = false }
        RecommendationPage(
            profile = profile,
            onBack = { showsRecommendation = false },
            onChoose = { program ->
                if (profile.lowerDaysGoal(program) != null) pendingProgramId = program.id else choose(program)
            },
            onSkip = { choose(null) },
        )
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
                        choose(pending, newDaysGoal = lower)
                    }) { Text(stringResource(R.string.days_goal_lower, lower)) }
                },
                dismissButton = {
                    TextButton(onClick = {
                        pendingProgramId = null
                        choose(pending)
                    }) { Text(stringResource(R.string.days_goal_keep, goal)) }
                },
            )
        }
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.welcome)) },
                actions = {
                    TextButton(onClick = {
                        skipped = true
                        askHealth()
                    }) { Text(stringResource(R.string.skip)) }
                    TextButton(onClick = {
                        // Prijedlog samo kad ima na temelju čega, inače odmah kraj.
                        if (profile.hasAnswers) showsRecommendation = true else choose(null)
                    }) { Text(stringResource(R.string.save)) }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())) {
            Text(
                stringResource(R.string.onboarding_intro),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp),
            )
            val none = stringResource(R.string.no_answer)
            ChoiceRow(
                title = stringResource(R.string.goal),
                value = answers.goal?.let { stringResource(goalTitle(it)) } ?: none,
                options = listOf(null) + TrainingGoal.entries,
                label = { it?.let { goal -> stringResource(goalTitle(goal)) } ?: none },
            ) { goalRaw = it?.raw }
            ChoiceRow(
                title = stringResource(R.string.days_per_week),
                value = days?.toString() ?: none,
                options = listOf(null) + OnboardingAnswers.DAYS_PER_WEEK_RANGE.toList(),
                label = { it?.toString() ?: none },
            ) { days = it }
            ChoiceRow(
                title = stringResource(R.string.experience),
                value = answers.experience?.let { stringResource(experienceTitle(it)) } ?: none,
                options = listOf(null) + ExperienceLevel.entries,
                label = { it?.let { level -> stringResource(experienceTitle(level)) } ?: none },
            ) { experienceRaw = it?.raw }
            Footer(stringResource(R.string.experience_footer))

            SectionHeader(stringResource(R.string.where_you_train))
            EquipmentPreset.entries.forEach { option ->
                ListItem(
                    modifier = Modifier.clickable { presetRaw = if (preset == option) null else option.raw },
                    headlineContent = { Text(stringResource(presetTitle(option))) },
                    supportingContent = { Text(stringResource(presetDetail(option))) },
                    trailingContent = if (preset == option) {
                        { Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                    } else {
                        null
                    },
                )
            }

            SectionHeader(stringResource(R.string.body_section))
            ChoiceRow(
                title = stringResource(R.string.units),
                value = stringResource(unitTitle(unit)),
                options = WeightUnit.entries,
                label = { stringResource(unitTitle(it)) },
            ) { unitRaw = it.raw }
            NumberRow(stringResource(R.string.body_height), "cm", heightText) { heightText = it }
            NumberRow(stringResource(R.string.body_weight), unit.symbol, weightText) { weightText = it }
            ChoiceRow(
                title = stringResource(R.string.sex),
                value = answers.sex?.let { stringResource(sexTitle(it)) } ?: none,
                options = listOf(null) + Sex.entries,
                label = { it?.let { sex -> stringResource(sexTitle(sex)) } ?: none },
            ) { sexRaw = it?.raw }
            Footer(stringResource(R.string.onboarding_body_footer))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
/** Prijedlog gotovih programa. Iz onboardinga ima uvod i "Složit ću sam" ([onSkip]), iz Postavki nema. */
internal fun RecommendationPage(
    profile: TrainingProfile,
    onBack: () -> Unit,
    onChoose: (Program) -> Unit,
    onSkip: (() -> Unit)? = null,
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
            if (onSkip != null) {
                Text(
                    stringResource(R.string.recommendation_intro),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
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
            if (onSkip != null) {
                TextButton(onClick = onSkip) { Text(stringResource(R.string.build_myself)) }
            }
        }
    }
}

@Composable
private fun NumberRow(title: String, suffix: String, text: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = text,
        onValueChange = onChange,
        label = { Text(title) },
        placeholder = { Text(stringResource(R.string.optional)) },
        suffix = { Text(suffix) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
    )
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

/**
 * Health Connect u onboardingu (zaslon o Apple Zdravlju na iOS-u): objašnjenje prije sustavskog lista dozvola.
 * [onAnswer] dobiva jesu li dane sve dozvole; "Ne sada" sprema da korisnik to nije odabrao.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HealthPage(onBack: () -> Unit, onAnswer: (Boolean) -> Unit) {
    val request = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        onAnswer(granted.containsAll(HealthConnect.PERMISSIONS))
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { },
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
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(stringResource(R.string.health_connect), style = MaterialTheme.typography.headlineMedium)
            Column(Modifier.widthIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.health_point_workouts), style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(R.string.health_point_weight), style = MaterialTheme.typography.bodyLarge)
                Text(
                    stringResource(R.string.health_onboarding_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Button(onClick = { request.launch(HealthConnect.PERMISSIONS) }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.health_connect_button))
            }
            TextButton(onClick = { onAnswer(false) }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.not_now))
            }
        }
    }
}

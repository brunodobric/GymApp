package com.brunodobric.gymapp.ui.home

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.model.DashboardLayout
import com.brunodobric.gymapp.model.OnboardingAnswers
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.kind
import com.brunodobric.gymapp.planning.ProfileSetupPrompt
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateStarter
import com.brunodobric.gymapp.training.RecoveryAssessment
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.WorkoutError
import com.brunodobric.gymapp.ui.workout.WorkoutLifecycle
import com.brunodobric.gymapp.ui.onboarding.OnboardingSheet
import com.brunodobric.gymapp.ui.rememberStoreRevision
import com.brunodobric.gymapp.ui.workout.PlateCalculatorDialog
import java.time.Instant

/**
 * Početna (`HomeScreen` na iOS-u): nastavak treninga u tijeku ili kartica za početak treninga, pa kartice koje
 * korisnik slaže sam ("Uredi kartice"): Ovaj tjedan, mjesec i godina, Zadnji trening, Tjelesna težina i
 * Kalkulator ploča. Dvije male kartice zaredom dijele red. Pri prvom prikazu trening koji je ostao otvoren
 * nudi nastavak, spremanje ili odbacivanje (`RecoveryAssessment`).
 */
@Composable
fun HomeScreen(
    services: AppServices,
    onOpenWorkout: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenStatistics: () -> Unit = {},
    onOpenSession: (Session) -> Unit = {},
    onOpenBody: () -> Unit = {},
    /** Ekran treninga je otvoren iznad Početne: ponuda za prekinut trening se ne pokazuje. */
    workoutShown: Boolean = false,
) {
    val store = services.store
    val revision = rememberStoreRevision(store)
    val active = store.activeSession()
    val emptyName = stringResource(R.string.workout_default_name)
    val locale = LocalConfiguration.current.locales[0]
    val upcoming = remember(revision) { ScheduleEngine(store).upcomingWorkouts() }
    val startable = remember(revision, locale) { TemplateStarter.startable(store.templates, locale) }
    var showsPicker by remember { mutableStateOf(false) }
    var showsPlates by remember { mutableStateOf(false) }
    var showsCardEditor by remember { mutableStateOf(false) }
    // Naknadno ispunjavanje profila: isti list kao onboarding, s odgovorima iz postavki.
    var showsProfileSetup by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(HOME_PREFS, Context.MODE_PRIVATE) }
    var profileSetupDismissed by remember { mutableStateOf(prefs.getBoolean(PROFILE_SETUP_DISMISSED, false)) }
    val layout = remember(store) { DashboardLayout(store) }
    LaunchedEffect(Unit) {
        layout.upgradeToWeekCard()
        layout.seedDefaults()
    }
    if (!workoutShown) RecoveryPrompt(services, onContinue = onOpenWorkout)
    // Aktivni rasporedi čiji su treninzi u izboru (prazno: izbor bez rasporeda).
    var pickerSchedules by remember { mutableStateOf<List<Schedule>>(emptyList()) }

    fun start(begin: () -> Unit) {
        showsPicker = false
        begin()
        onOpenWorkout()
    }

    if (showsPicker) {
        val schedules = pickerSchedules
        val groups = remember(revision, schedules) {
            val engine = ScheduleEngine(store)
            schedules.distinctBy { it.id }.map { schedule ->
                ScheduleChoices(
                    schedule = schedule,
                    workouts = engine.workoutChoices(schedule),
                    nextItemId = upcoming.firstOrNull { it.schedule.id == schedule.id }?.item?.id,
                )
            }.filter { it.workouts.isNotEmpty() }
        }
        TemplatePickerDialog(
            groups = groups,
            templates = startable,
            onPlanned = { planned -> start { TemplateStarter(store).start(planned) } },
            onTemplate = { template -> start { TemplateStarter(store).start(template) } },
            onDismiss = { showsPicker = false },
        )
    }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Postavke su na Početnoj, kao na iOS-u (gumb u alatnoj traci).
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_home), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = onOpenSettings) {
                Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.settings))
            }
        }
        if (active != null) {
            // Trening u tijeku: kartica s upravljanjem serijom, kao ActiveWorkoutCard na iOS-u.
            ActiveWorkoutCard(services, revision, onOpen = onOpenWorkout)
        } else {
            upcoming.firstOrNull()?.let { next ->
                NextWorkoutHero(next, onStart = { start { TemplateStarter(store).start(next) } })
            }
            StartWorkoutCard(
                planned = upcoming,
                templateCount = startable.size,
                offersOtherWorkout = upcoming.map { it.template.id }.toSet().let { next -> startable.any { it.id !in next } },
                onStart = { planned -> start { TemplateStarter(store).start(planned) } },
                onChooseTemplate = { schedules ->
                    pickerSchedules = schedules
                    showsPicker = true
                },
                onStartEmpty = { start { WorkoutEngine(store).startSession(emptyName) } },
                skipsFirst = upcoming.isNotEmpty(),
            )
        }
        if (ProfileSetupPrompt.isShown(store.settings(), store.schedules.size, profileSetupDismissed)) {
            ProfileSetupCard(
                onOpen = { showsProfileSetup = true },
                onDismiss = {
                    profileSetupDismissed = true
                    prefs.edit().putBoolean(PROFILE_SETUP_DISMISSED, true).apply()
                },
            )
        }
        val kinds = remember(revision) { layout.cards().mapNotNull { it.kind } }
        val actions = DashboardActions(
            onOpenStatistics = onOpenStatistics,
            onOpenSession = onOpenSession,
            onOpenBody = onOpenBody,
            onOpenPlates = { showsPlates = true },
        )
        DashboardLayout.rows(kinds).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { kind -> DashboardCardView(services, kind, revision, actions, Modifier.weight(1f).fillMaxHeight()) }
                // Mala kartica sama u redu zauzima pola širine.
                if (row.size == 1 && row[0].isCompact) Spacer(Modifier.weight(1f))
            }
        }
        OutlinedButton(onClick = { showsCardEditor = true }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text(stringResource(R.string.edit_cards))
        }
    }

    if (showsProfileSetup) {
        OnboardingSheet(services, OnboardingAnswers.from(store.settings()), onClose = { showsProfileSetup = false })
    }

    if (showsCardEditor) DashboardEditorDialog(services, revision, onDismiss = { showsCardEditor = false })

    if (showsPlates) {
        PlateCalculatorDialog("", store.settings().weightUnit, store.settings(), onDismiss = { showsPlates = false })
    }
}

private const val HOME_PREFS = "home"

/** Kartica "Postavi profil" zatvorena križićem (na ovom uređaju). */
private const val PROFILE_SETUP_DISMISSED = "profileSetupDismissed"

/** Naknadno ispunjavanje onboardinga (`ProfileSetupPrompt`): otvara isti list u dva koraka. */
@Composable
private fun ProfileSetupCard(onOpen: () -> Unit, onDismiss: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Box {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    stringResource(R.string.settings_profile).uppercase(),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    stringResource(R.string.profile_setup_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(end = 32.dp),
                )
                Button(onClick = onOpen) { Text(stringResource(R.string.profile_setup)) }
            }
            IconButton(onClick = onDismiss, modifier = Modifier.align(Alignment.TopEnd)) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
            }
        }
    }
}

/** Ponuda se pokazuje jednom po pokretanju aplikacije, kao `checkedRecovery` na iOS-u; otvoren ekran treninga je preskače. */
internal object RecoveryCheck {
    @Volatile var checked = false
}

/**
 * Pri pokretanju: trening koji je ostao otvoren nudi Nastavi trening, Završi i spremi (na zadnjoj završenoj
 * seriji, `closeStaleSession`) ili Odbaci trening. Trening bez aktivnosti dulje od 6 sati je "zaboravljen".
 */
@Composable
private fun RecoveryPrompt(services: AppServices, onContinue: () -> Unit) {
    val store = services.store
    var prompt by remember { mutableStateOf<Pair<Session, Boolean>?>(null) }
    LaunchedEffect(Unit) {
        if (RecoveryCheck.checked) return@LaunchedEffect
        RecoveryCheck.checked = true
        val active = store.activeSession() ?: return@LaunchedEffect
        val engine = WorkoutEngine(store)
        val assessment = RecoveryAssessment.assess(active.startedAt, active.lastActivityAt, engine.lastCompletedSetAt(active), Instant.now())
        prompt = active to assessment.isStale
    }
    val (session, isStale) = prompt ?: return
    AlertDialog(
        onDismissRequest = { prompt = null },
        title = { Text(stringResource(if (isStale) R.string.stale_title else R.string.interrupted_title)) },
        text = {
            Column {
                Text(stringResource(if (isStale) R.string.stale_message else R.string.interrupted_message))
                TextButton(onClick = {
                    prompt = null
                    onContinue()
                }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.continue_training)) }
                TextButton(onClick = {
                    prompt = null
                    try {
                        WorkoutEngine(store).closeStaleSession(session)
                        ScheduleEngine(store).sessionFinished(session)
                    } catch (_: WorkoutError.NothingCompleted) {
                        // Bez završene serije nema što spremiti: trening se odbacuje.
                        WorkoutLifecycle.discard(session, store)
                    }
                }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.finish_and_save)) }
                TextButton(onClick = {
                    prompt = null
                    WorkoutLifecycle.discard(session, store)
                }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.discard_workout), color = MaterialTheme.colorScheme.error)
                }
            }
        },
        confirmButton = {},
    )
}

package com.brunodobric.gymapp.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.planning.TemplateStarter
import com.brunodobric.gymapp.planning.WorkoutShortcuts
import com.brunodobric.gymapp.ui.exercises.ExercisesScreen
import com.brunodobric.gymapp.ui.history.HistoryScreen
import com.brunodobric.gymapp.ui.home.HomeScreen
import com.brunodobric.gymapp.ui.onboarding.OnboardingScreen
import com.brunodobric.gymapp.ui.planning.SchedulesScreen
import com.brunodobric.gymapp.ui.planning.UpcomingWorkoutScreen
import com.brunodobric.gymapp.ui.statistics.StatisticsScreen
import com.brunodobric.gymapp.ui.settings.SettingsScreen
import com.brunodobric.gymapp.ui.workout.WorkoutScreen
import com.brunodobric.gymapp.widgets.WidgetLink
import java.util.UUID

/** Pet glavnih dijelova aplikacije, isti kao tabovi na iOS-u (specifikacija, odjeljak 3). */
enum class Section(@StringRes val title: Int, val icon: ImageVector) {
    HOME(R.string.tab_home, Icons.Filled.Home),
    HISTORY(R.string.tab_history, Icons.AutoMirrored.Filled.List),
    SCHEDULES(R.string.tab_plans, Icons.Filled.DateRange),
    EXERCISES(R.string.tab_exercises, Icons.Filled.Search),
    STATISTICS(R.string.tab_statistics, Icons.Filled.Star),
}

/** Jednokratni zahtjev za otvaranje (npr. treninga iz widgeta); novi zahtjev s istom vrijednošću je ipak nov. */
class OpenRequest(val value: String)

@Composable
fun RootScreen(
    services: AppServices,
    openWorkoutRequests: Int = 0,
    openScheduleRequest: String? = null,
    onScheduleRequestHandled: () -> Unit = {},
    widgetLink: WidgetLink? = null,
    onWidgetLinkHandled: () -> Unit = {},
) {
    var selected by rememberSaveable { mutableStateOf(Section.HOME) }
    // Trening u tijeku je preko cijelog zaslona, kao na iPhoneu; tabovi ostaju ispod njega.
    var showsWorkout by rememberSaveable { mutableStateOf(false) }
    var showsSettings by rememberSaveable { mutableStateOf(false) }
    // Raspored čiji se sljedeći trening prikazuje (dodir na podsjetnik rasporeda).
    var upcomingSchedule by rememberSaveable { mutableStateOf<String?>(null) }
    // Dodir obavijesti treninga ili kraja odmora otvara ekran treninga, ako trening još traje.
    LaunchedEffect(openWorkoutRequests) {
        if (openWorkoutRequests > 0 && services.store.activeSession() != null) {
            showsSettings = false
            showsWorkout = true
        }
    }
    // Dodir na podsjetnik otvara sljedeći trening rasporeda. Dok trening traje, korisnik već trenira, pa se
    // dodir zanemaruje (kao na iOS-u).
    LaunchedEffect(openScheduleRequest) {
        val id = openScheduleRequest ?: return@LaunchedEffect
        onScheduleRequestHandled()
        if (services.store.activeSession() == null) {
            showsSettings = false
            upcomingSchedule = id
        }
    }
    // Zahtjevi koje Povijest i Statistika otvaraju kad stignu (dodir na widget).
    var historyRequest by remember { mutableStateOf<OpenRequest?>(null) }
    var bodyRequest by remember { mutableStateOf<OpenRequest?>(null) }
    val emptyName = stringResource(R.string.workout_default_name)
    // Dodir na widget otvara dio aplikacije iz poveznice, kao `onOpenURL` na iOS-u (docs/widgeti.md).
    LaunchedEffect(widgetLink) {
        val link = widgetLink ?: return@LaunchedEffect
        onWidgetLinkHandled()
        val store = services.store
        showsSettings = false
        upcomingSchedule = null
        when (link) {
            WidgetLink.Home -> selected = Section.HOME
            WidgetLink.ActiveWorkout -> if (store.activeSession() != null) showsWorkout = true else selected = Section.HOME
            WidgetLink.StartWorkout -> {
                // Nastavlja trening u tijeku ili pokreće sljedeći trening rasporeda; bez rasporeda otvara Početnu.
                if (store.activeSession() == null) {
                    ScheduleEngine(store).upcomingWorkouts().firstOrNull()?.let { TemplateStarter(store).start(it) }
                }
                if (store.activeSession() != null) showsWorkout = true else selected = Section.HOME
            }
            WidgetLink.Week -> {
                showsWorkout = false
                selected = Section.STATISTICS
            }
            WidgetLink.BodyWeight -> {
                showsWorkout = false
                selected = Section.STATISTICS
                bodyRequest = OpenRequest("body")
            }
            WidgetLink.LastWorkout -> {
                showsWorkout = false
                selected = Section.HISTORY
                historyRequest = store.finishedSessions().firstOrNull()?.let { OpenRequest(it.id.toString()) }
            }
            is WidgetLink.Session -> {
                showsWorkout = false
                selected = Section.HISTORY
                historyRequest = OpenRequest(link.id.toString())
            }
            // Prečaci na ikoni: trening u tijeku ima prednost, kao kod akcije "Započni trening" na iOS-u.
            WidgetLink.EmptyWorkout -> {
                WorkoutShortcuts(store).start(null, emptyName)
                showsWorkout = true
            }
            is WidgetLink.StartTemplate -> {
                // Obrisan ili prazan trening iz starog prečaca otvara Početnu.
                runCatching { WorkoutShortcuts(store).start(link.id, emptyName) }
                if (store.activeSession() != null) showsWorkout = true else selected = Section.HOME
            }
        }
    }
    // Prvo pokretanje: onboarding dok ga korisnik ne spremi ili preskoči.
    rememberStoreRevision(services.store)
    if (!services.store.settings().onboardingCompleted) {
        OnboardingScreen(services)
        return
    }
    if (showsWorkout) {
        WorkoutScreen(services, onClose = { showsWorkout = false })
        return
    }
    upcomingSchedule?.let { id ->
        UpcomingWorkoutScreen(
            services,
            UUID.fromString(id),
            onClose = { upcomingSchedule = null },
            onStarted = {
                upcomingSchedule = null
                showsWorkout = true
            },
        )
        return
    }
    if (showsSettings) {
        SettingsScreen(services, onClose = { showsSettings = false })
        return
    }
    Scaffold(
        bottomBar = {
            NavigationBar {
                Section.entries.forEach { section ->
                    NavigationBarItem(
                        selected = section == selected,
                        onClick = { selected = section },
                        icon = { Icon(section.icon, contentDescription = null) },
                        label = { Text(stringResource(section.title)) },
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (selected) {
                Section.HOME -> HomeScreen(
                    services,
                    onOpenWorkout = { showsWorkout = true },
                    onOpenSettings = { showsSettings = true },
                )
                Section.HISTORY -> HistoryScreen(services, historyRequest, onRequestHandled = { historyRequest = null })
                Section.SCHEDULES -> SchedulesScreen(services)
                Section.EXERCISES -> ExercisesScreen(services)
                Section.STATISTICS -> StatisticsScreen(services, bodyRequest, onRequestHandled = { bodyRequest = null })
            }
        }
    }
}

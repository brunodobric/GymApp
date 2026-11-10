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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.exercises.ExercisesScreen
import com.brunodobric.gymapp.ui.history.HistoryScreen
import com.brunodobric.gymapp.ui.home.HomeScreen
import com.brunodobric.gymapp.ui.onboarding.OnboardingScreen
import com.brunodobric.gymapp.ui.planning.SchedulesScreen
import com.brunodobric.gymapp.ui.planning.UpcomingWorkoutScreen
import com.brunodobric.gymapp.ui.statistics.StatisticsScreen
import com.brunodobric.gymapp.ui.settings.SettingsScreen
import com.brunodobric.gymapp.ui.workout.WorkoutScreen
import java.util.UUID

/** Pet glavnih dijelova aplikacije, isti kao tabovi na iOS-u (specifikacija, odjeljak 3). */
enum class Section(@StringRes val title: Int, val icon: ImageVector) {
    HOME(R.string.tab_home, Icons.Filled.Home),
    HISTORY(R.string.tab_history, Icons.AutoMirrored.Filled.List),
    SCHEDULES(R.string.tab_plans, Icons.Filled.DateRange),
    EXERCISES(R.string.tab_exercises, Icons.Filled.Search),
    STATISTICS(R.string.tab_statistics, Icons.Filled.Star),
}

@Composable
fun RootScreen(
    services: AppServices,
    openWorkoutRequests: Int = 0,
    openScheduleRequest: String? = null,
    onScheduleRequestHandled: () -> Unit = {},
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
                Section.HISTORY -> HistoryScreen(services)
                Section.SCHEDULES -> SchedulesScreen(services)
                Section.EXERCISES -> ExercisesScreen(services)
                Section.STATISTICS -> StatisticsScreen(services)
            }
        }
    }
}

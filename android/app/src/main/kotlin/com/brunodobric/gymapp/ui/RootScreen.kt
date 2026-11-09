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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.ui.exercises.ExercisesScreen

/** Pet glavnih dijelova aplikacije, isti kao tabovi na iOS-u (specifikacija, odjeljak 3). */
enum class Section(@StringRes val title: Int, val icon: ImageVector) {
    HOME(R.string.tab_home, Icons.Filled.Home),
    HISTORY(R.string.tab_history, Icons.AutoMirrored.Filled.List),
    SCHEDULES(R.string.tab_plans, Icons.Filled.DateRange),
    EXERCISES(R.string.tab_exercises, Icons.Filled.Search),
    STATISTICS(R.string.tab_statistics, Icons.Filled.Star),
}

@Composable
fun RootScreen(services: AppServices) {
    var selected by rememberSaveable { mutableStateOf(Section.HOME) }
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
                Section.EXERCISES -> ExercisesScreen(services)
                else -> Placeholder()
            }
        }
    }
}

@Composable
private fun Placeholder() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(stringResource(R.string.coming_soon), style = MaterialTheme.typography.bodyLarge)
    }
}

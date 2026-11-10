package com.brunodobric.gymapp.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.planning.Program
import com.brunodobric.gymapp.planning.ProgramLibrary
import com.brunodobric.gymapp.planning.TrainingProfile
import com.brunodobric.gymapp.ui.catalogLanguage
import com.brunodobric.gymapp.ui.planning.installProgram

/**
 * Postavke > Profil > Predloži raspored (`ProgramRecommendationScreen` na iOS-u). Profil se uzima u trenutku
 * otvaranja, da se popis ne mijenja kad korisnik smanji cilj dana.
 */
@Composable
fun ProgramRecommendationScreen(services: AppServices, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val store = services.store
    val context = LocalContext.current
    val language = catalogLanguage()
    val profile = remember { TrainingProfile.from(store.settings()) }
    var pendingProgramId by rememberSaveable { mutableStateOf<String?>(null) }
    var added by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }

    fun add(program: Program, newDaysGoal: Int?) {
        try {
            if (newDaysGoal != null) {
                store.settings().trainingDaysPerWeek = newDaysGoal
                store.save()
            }
            added = installProgram(services, context, language, program, profile).name
        } catch (_: Exception) {
            failed = true
        }
    }

    RecommendationPage(
        profile = profile,
        onBack = onClose,
        onChoose = { program ->
            if (profile.lowerDaysGoal(program) != null) pendingProgramId = program.id else add(program, null)
        },
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
                    add(pending, lower)
                }) { Text(stringResource(R.string.days_goal_lower, lower)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    pendingProgramId = null
                    add(pending, null)
                }) { Text(stringResource(R.string.days_goal_keep, goal)) }
            },
        )
    }
    added?.let { name ->
        AlertDialog(
            onDismissRequest = { added = null },
            title = { Text(stringResource(R.string.program_added)) },
            text = { Text(stringResource(R.string.program_added_message, name)) },
            confirmButton = { TextButton(onClick = { added = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
    if (failed) {
        AlertDialog(
            onDismissRequest = { failed = false },
            text = { Text(stringResource(R.string.program_failed)) },
            confirmButton = { TextButton(onClick = { failed = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

package com.brunodobric.gymapp.ui.workout

import android.Manifest
import android.content.Context
import android.media.RingtoneManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.brunodobric.gymapp.notifications.RestNotifications
import com.brunodobric.gymapp.notifications.WorkoutScreenPresence
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay

/**
 * Kraj odmora dok je ekran treninga pred korisnikom (`restExpired` na iOS-u): vibracija, zvuk ako je
 * uključen i gašenje timera. Dok je ekran u prvom planu, obavijest se ne prikazuje; kad se korisnik vrati
 * nakon isteka, timer se gasi bez zvuka, a prikazana obavijest se uklanja.
 * Dopuštenje za obavijesti traži se kad prvi odmor počne, jednom po otvaranju ekrana.
 */
@Composable
internal fun RestEndEffects(
    endsAt: Instant?,
    soundEnabled: Boolean,
    notificationsEnabled: Boolean,
    onExpired: () -> Unit,
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val state by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val resumed = state.isAtLeast(Lifecycle.State.RESUMED)
    val currentOnExpired by rememberUpdatedState(onExpired)
    val currentSound by rememberUpdatedState(soundEnabled)

    DisposableEffect(resumed) {
        if (resumed) {
            WorkoutScreenPresence.appeared()
            RestNotifications.dismiss(context)
        }
        onDispose { if (resumed) WorkoutScreenPresence.disappeared() }
    }

    var askedPermission by rememberSaveable { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    val wantsPermission = endsAt != null && notificationsEnabled && !askedPermission
    LaunchedEffect(wantsPermission) {
        if (wantsPermission && RestNotifications.needsPermission(context)) {
            askedPermission = true
            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(endsAt, resumed) {
        if (!resumed || endsAt == null) return@LaunchedEffect
        val wait = Duration.between(Instant.now(), endsAt).toMillis()
        if (wait > 0) {
            delay(wait)
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            if (currentSound) playRestEndSound(context)
        }
        currentOnExpired()
    }
}

private fun playRestEndSound(context: Context) {
    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return
    RingtoneManager.getRingtone(context, uri)?.play()
}

package com.brunodobric.gymapp.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalConfiguration
import com.brunodobric.gymapp.model.GymStore
import java.time.Instant
import kotlinx.coroutines.delay

/**
 * Broj spremanja u bazi (`DataVersion` na iOS-u). Ekran koji ga čita ponovno se iscrtava nakon svakog
 * spremanja koje je nešto promijenilo, pa upiti nad `GymStore` uvijek pokazuju zadnje stanje.
 */
@Composable
fun rememberStoreRevision(store: GymStore): Long {
    var revision by remember { mutableLongStateOf(store.revision) }
    DisposableEffect(store) {
        val listener: (Long) -> Unit = { revision = it }
        store.addListener(listener)
        onDispose { store.removeListener(listener) }
    }
    return revision
}

/** Trenutno vrijeme koje se osvježava svake sekunde (trajanje treninga, odmor). */
@Composable
fun rememberTicker(): Instant {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            now = Instant.now()
        }
    }
    return now
}

/** Jezik kataloga: hrvatski ili engleski, prema jeziku aplikacije. */
@Composable
fun catalogLanguage(): String = LocalConfiguration.current.locales[0].language.let { if (it == "hr") "hr" else "en" }

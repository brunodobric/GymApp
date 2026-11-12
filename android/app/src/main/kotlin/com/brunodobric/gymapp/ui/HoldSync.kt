package com.brunodobric.gymapp.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import com.brunodobric.gymapp.sync.SyncGate

/** Dok je ekran otvoren, promjene s drugog uređaja ne ulaze u bazu (uređivači i trening, [SyncGate]). */
@Composable
fun HoldSync() {
    DisposableEffect(Unit) {
        SyncGate.hold()
        onDispose { SyncGate.release() }
    }
}

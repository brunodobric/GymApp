package com.brunodobric.gymapp.ui.planning

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.brunodobric.gymapp.R

/** Što se uređuje: o tome ovise naslov i poruka pitanja pri izlasku (isti tekstovi kao na iOS-u). */
internal enum class EditedItem { SCHEDULE, WORKOUT }

/**
 * Pitanje pri izlasku iz uređivača s nespremljenim promjenama: Spremi, Izađi bez spremanja ili Odustani.
 * Nova stavka ima svoj naslov ("Spremiti trening?"), a postojeća "Spremiti promjene?".
 */
@Composable
internal fun SaveChangesDialog(
    item: EditedItem,
    isNew: Boolean,
    onSave: () -> Unit,
    onDiscard: () -> Unit,
    onDismiss: () -> Unit,
) {
    val title = when {
        !isNew -> R.string.save_changes_title
        item == EditedItem.SCHEDULE -> R.string.save_schedule_title
        else -> R.string.save_workout_title
    }
    val message = when {
        !isNew -> R.string.save_changes_message
        item == EditedItem.SCHEDULE -> R.string.save_schedule_message
        else -> R.string.save_workout_message
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(title)) },
        text = { Text(stringResource(message)) },
        // Tri izbora jedan ispod drugoga, jer "Izađi bez spremanja" ne stane u red uz ostale.
        confirmButton = {
            Column(horizontalAlignment = Alignment.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onSave) { Text(stringResource(R.string.save)) }
                TextButton(onClick = onDiscard) {
                    Text(stringResource(R.string.leave_without_saving), color = MaterialTheme.colorScheme.error)
                }
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
            }
        },
    )
}

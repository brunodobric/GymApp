package com.brunodobric.gymapp.ui.exercises

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.data.downscaledJpeg
import java.io.File

/** Slika vježbe iz datoteke, širine ekrana; ništa kad se datoteka ne može pročitati. */
@Composable
internal fun ExerciseImage(file: File, description: String, modifier: Modifier = Modifier) {
    val bitmap = remember(file.path, file.lastModified()) { BitmapFactory.decodeFile(file.path)?.asImageBitmap() } ?: return
    Image(
        bitmap,
        contentDescription = description,
        contentScale = ContentScale.Fit,
        modifier = modifier.fillMaxWidth().heightIn(max = 320.dp).clip(RoundedCornerShape(12.dp)),
    )
}

/**
 * Odjeljak "Slika" u uređivaču vlastite vježbe (`CustomExerciseEditor` na iOS-u). Fotografija se bira
 * sustavskim odabirom fotografija (bez dopuštenja za pohranu), smanjuje na 1200 px i čeka u privremenoj
 * datoteci dok korisnik ne spremi vježbu.
 */
@Composable
internal fun ExerciseImageSection(
    shown: File?,
    name: String,
    onPicked: (File) -> Unit,
    onRemove: () -> Unit,
) {
    val context = LocalContext.current
    var failed by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val data = downscaledJpeg(context, uri)
        if (data == null) {
            failed = true
            return@rememberLauncherForActivityResult
        }
        failed = false
        val file = File.createTempFile("exercise-image", ".jpg", context.cacheDir)
        file.writeBytes(data)
        onPicked(file)
    }
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.image), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 16.dp))
        if (shown != null) ExerciseImage(shown, name)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = {
                picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }) {
                Text(stringResource(if (shown == null) R.string.choose_image else R.string.replace_image))
            }
            if (shown != null) {
                TextButton(onClick = onRemove) { Text(stringResource(R.string.remove_image), color = MaterialTheme.colorScheme.error) }
            }
        }
        if (failed) {
            Text(stringResource(R.string.image_load_failed), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
}

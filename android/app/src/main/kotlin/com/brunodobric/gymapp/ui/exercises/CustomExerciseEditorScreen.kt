package com.brunodobric.gymapp.ui.exercises

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.brunodobric.gymapp.AppServices
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseCategory
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.rawValueOf
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.CustomExerciseStore
import java.io.File
import java.util.UUID

/**
 * Izrada i uređivanje vlastite vježbe, kao `CustomExerciseEditor` na iOS-u: naziv, opis, vrsta, kategorija,
 * oprema, vrsta unosa i mišići. Slika vježbe na Androidu dolazi kasnije. Za novu vježbu [exerciseId] je null.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomExerciseEditorScreen(services: AppServices, exerciseId: UUID?, onClose: () -> Unit) {
    val store = services.store
    val exercise = remember(exerciseId) { exerciseId?.let(store::customExercise) }
    // Stanje su sirove vrijednosti (raw), da preživi okretanje ekrana.
    var name by rememberSaveable { mutableStateOf(exercise?.name ?: "") }
    var details by rememberSaveable { mutableStateOf(exercise?.details ?: "") }
    var kindRaw by rememberSaveable { mutableStateOf(exercise?.kind?.raw ?: ExerciseKind.STRENGTH.raw) }
    var categoryRaw by rememberSaveable { mutableStateOf(exercise?.categoryRaw ?: "") }
    var equipmentRaw by rememberSaveable { mutableStateOf(exercise?.equipmentRaw ?: "") }
    var inputRaw by rememberSaveable { mutableStateOf(exercise?.inputTypeRaw ?: ExerciseInputType.WEIGHT_REPS.raw) }
    var musclesRaw by rememberSaveable { mutableStateOf(exercise?.musclesRaw ?: "") }
    var confirmRemove by remember { mutableStateOf(false) }
    // Nova slika čeka u privremenoj datoteci do spremanja; uklanjanje se također primjenjuje tek tada.
    var pendingImagePath by rememberSaveable { mutableStateOf<String?>(null) }
    var removesImage by rememberSaveable { mutableStateOf(false) }
    BackHandler(onBack = onClose)

    val kind = rawValueOf<ExerciseKind>(kindRaw) ?: ExerciseKind.STRENGTH
    val category = rawValueOf<ExerciseCategory>(categoryRaw)
    val equipment = rawValueOf<Equipment>(equipmentRaw)
    val inputType = rawValueOf<ExerciseInputType>(inputRaw) ?: ExerciseInputType.WEIGHT_REPS
    val muscles = musclesRaw.split(",").mapNotNull { rawValueOf<Muscle>(it) }.toSet()
    val canSave = name.isNotBlank()

    fun save() {
        val target = exercise ?: store.insert(CustomExercise(""))
        target.name = name.trim()
        target.details = details
        target.category = category
        target.kind = kind
        target.equipment = equipment
        target.inputType = inputType
        // Redoslijed mišića je stabilan (kao u katalogu), ne ovisi o redoslijedu odabira.
        target.muscles = Muscle.entries.filter { it in muscles }
        val images = services.exerciseImages
        val pending = pendingImagePath?.let(::File)
        if (pending != null || removesImage) {
            target.imageFile?.let(images::delete)
            target.imageFile = null
        }
        if (pending != null) {
            target.imageFile = runCatching { pending.readBytes() }.getOrNull()?.let { images.save(target.id, it) }
            pending.delete()
        }
        store.save()
        onClose()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(if (exercise == null) R.string.custom_exercise_new else R.string.custom_exercise_edit)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel))
                    }
                },
                actions = {
                    if (exercise != null) {
                        IconButton(onClick = { confirmRemove = true }) {
                            Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.remove))
                        }
                    }
                    TextButton(enabled = canSave, onClick = { save() }) { Text(stringResource(R.string.save)) }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.custom_exercise_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            )
            OutlinedTextField(
                value = details,
                onValueChange = { details = it },
                label = { Text(stringResource(R.string.custom_exercise_details)) },
                minLines = 2,
                maxLines = 6,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            )
            val shownImage = pendingImagePath?.let(::File)
                ?: exercise?.imageFile?.takeIf { !removesImage }?.let(services.exerciseImages::file)
            ExerciseImageSection(
                shown = shownImage,
                name = name,
                onPicked = { file ->
                    pendingImagePath?.let { File(it).delete() }
                    pendingImagePath = file.path
                },
                onRemove = {
                    pendingImagePath?.let { File(it).delete() }
                    pendingImagePath = null
                    removesImage = true
                },
            )
            PickerRow(stringResource(R.string.exercise_kind), stringResource(kindTitle(kind)), ExerciseKind.entries, { stringResource(kindTitle(it)) }) {
                kindRaw = it.raw
            }
            PickerRow(
                stringResource(R.string.exercise_category),
                category?.let { stringResource(categoryTitle(it)) } ?: stringResource(R.string.not_selected),
                listOf<ExerciseCategory?>(null) + ExerciseCategory.entries,
                { it?.let { value -> stringResource(categoryTitle(value)) } ?: stringResource(R.string.not_selected) },
            ) { new ->
                // Kardio kategorija je uvijek kardio vrsta (kao u katalogu).
                if (new == ExerciseCategory.CARDIO) {
                    kindRaw = ExerciseKind.CARDIO.raw
                } else if (category == ExerciseCategory.CARDIO && kind == ExerciseKind.CARDIO) {
                    kindRaw = ExerciseKind.STRENGTH.raw
                }
                categoryRaw = new?.raw ?: ""
            }
            PickerRow(
                stringResource(R.string.exercise_equipment),
                equipment?.let { stringResource(equipmentTitle(it)) } ?: stringResource(R.string.not_selected),
                listOf<Equipment?>(null) + Equipment.entries,
                { it?.let { value -> stringResource(equipmentTitle(value)) } ?: stringResource(R.string.not_selected) },
            ) { equipmentRaw = it?.raw ?: "" }
            PickerRow(stringResource(R.string.exercise_input), stringResource(inputTypeTitle(inputType)), ExerciseInputType.entries, { stringResource(inputTypeTitle(it)) }) {
                inputRaw = it.raw
            }
            Text(
                stringResource(R.string.input_type_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Text(
                stringResource(R.string.muscles),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(start = 16.dp, top = 16.dp),
            )
            Muscle.entries.forEach { muscle ->
                val selected = muscle in muscles
                fun toggle() {
                    val updated = if (selected) muscles - muscle else muscles + muscle
                    musclesRaw = updated.joinToString(",") { it.raw }
                }
                ListItem(
                    modifier = Modifier.clickable { toggle() },
                    headlineContent = { Text(stringResource(muscleTitle(muscle))) },
                    trailingContent = { Checkbox(checked = selected, onCheckedChange = { toggle() }) },
                )
            }
        }
    }

    if (confirmRemove && exercise != null) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text(stringResource(R.string.remove_exercise_title)) },
            text = { Text(stringResource(R.string.remove_exercise_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRemove = false
                    CustomExerciseStore.remove(exercise, store)
                    onClose()
                }) { Text(stringResource(R.string.remove), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Red s odabranom vrijednošću; dodir otvara izbornik. */
@Composable
private fun <T> PickerRow(title: String, value: String, options: List<T>, label: @Composable (T) -> String, onSelect: (T) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ListItem(
            modifier = Modifier.clickable { expanded = true },
            headlineContent = { Text(title) },
            trailingContent = { Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant) },
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(label(option)) }, onClick = {
                    expanded = false
                    onSelect(option)
                })
            }
        }
    }
}

package com.brunodobric.gymapp.data

import android.content.Context
import java.io.File
import java.util.UUID

/**
 * Slike vlastitih vježbi, kao datoteke u `files/exercise-images/` (na iOS-u su u bazi, `externalStorage`).
 * U bazi je samo ime datoteke (`CustomExercise.imageFile`). Mapa ide u sustavsku sigurnosnu kopiju.
 */
class ExerciseImages(context: Context) {
    private val directory = File(context.applicationContext.filesDir, "exercise-images")

    fun read(name: String): ByteArray? {
        val file = File(directory, name)
        // Ime iz baze ne smije izaći iz mape.
        if (file.parentFile != directory || !file.isFile) return null
        return runCatching { file.readBytes() }.getOrNull()
    }

    /** Sprema sliku vježbe i vraća ime datoteke; null kad spremanje ne uspije. */
    fun save(id: UUID, data: ByteArray): String? = runCatching {
        directory.mkdirs()
        val name = "${id.toString().uppercase()}.jpg"
        File(directory, name).writeBytes(data)
        name
    }.getOrNull()
}

package com.brunodobric.gymapp.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import java.io.ByteArrayOutputStream
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

    /** Datoteka slike za prikaz; null kad je nema. */
    fun file(name: String): File? = File(directory, name).takeIf { it.parentFile == directory && it.isFile }

    fun delete(name: String) {
        file(name)?.delete()
    }

    /** Sprema sliku vježbe i vraća ime datoteke; null kad spremanje ne uspije. */
    fun save(id: UUID, data: ByteArray): String? = runCatching {
        directory.mkdirs()
        val name = "${id.toString().uppercase()}.jpg"
        File(directory, name).writeBytes(data)
        name
    }.getOrNull()
}

/**
 * Učitava odabranu fotografiju i smanjuje je na najviše [maxDimension] px po duljoj strani, kao JPEG
 * (`downscaledJPEG` na iOS-u), da baza i kopija ne nose izvornu fotografiju. Null kad se slika ne može pročitati.
 */
fun downscaledJpeg(context: Context, uri: Uri, maxDimension: Int = 1200, quality: Int = 85): ByteArray? = runCatching {
    val source = ImageDecoder.createSource(context.contentResolver, uri)
    val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
        val longest = maxOf(info.size.width, info.size.height)
        if (longest > maxDimension) {
            val scale = maxDimension.toDouble() / longest
            decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1), (info.size.height * scale).toInt().coerceAtLeast(1))
        }
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
    ByteArrayOutputStream().use { out ->
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
        out.toByteArray()
    }
}.getOrNull()

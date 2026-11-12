package com.brunodobric.gymapp.ui.exercises

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import com.brunodobric.gymapp.catalog.CatalogExercise
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * MoveKit posteri u buildu (`assets/movekit/`, ne commita se: `docs/movekit.md`). Build bez MoveKit dodatka
 * (CI, klon repozitorija) nema nijedan, pa kartice vrsta pokazuju simbol.
 */
internal object MoveKitAssets {
    private const val ROOT = "movekit"

    @Volatile private var files: Set<String>? = null

    /** Putanje iz kataloga (npr. `Media/x.jpg`) koje postoje u buildu. Popis se čita jednom. */
    fun available(context: Context): Set<String> = files ?: synchronized(this) {
        files ?: list(context, ROOT).map { it.removePrefix("$ROOT/") }.toSet().also { files = it }
    }

    fun hasPoster(context: Context, exercise: CatalogExercise): Boolean =
        exercise.poster?.let { it in available(context) } == true

    fun assetPath(path: String): String = "$ROOT/$path"

    /** Poster vježbe iz kataloga ako je u buildu; null za vlastitu vježbu i build bez MoveKit dodatka. */
    fun posterPath(context: Context, exercise: CatalogExercise?): String? =
        exercise?.poster?.takeIf { it in available(context) }

    private fun list(context: Context, dir: String): List<String> {
        val children = try { context.assets.list(dir).orEmpty() } catch (_: IOException) { emptyArray() }
        // Prazan popis znači datoteku (ili praznu mapu), pa se ne ulazi dublje.
        return children.flatMap { name ->
            val path = "$dir/$name"
            val nested = list(context, path)
            if (nested.isEmpty()) listOf(path) else nested
        }
    }
}

/** Umanjene sličice postera, kao `ThumbnailLoader` na iOS-u: dekodiraju se izvan glavne niti i pamte. */
private object ThumbnailCache {
    /** Najveća strana sličice u pikselima. */
    private const val MAX_PIXEL_SIZE = 480

    private val cache = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    suspend fun load(context: Context, assetPath: String): Bitmap? {
        cache.get(assetPath)?.let { return it }
        val bitmap = withContext(Dispatchers.IO) {
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                context.assets.open(assetPath).use { BitmapFactory.decodeStream(it, null, bounds) }
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_PIXEL_SIZE) sample *= 2
                val options = BitmapFactory.Options().apply { inSampleSize = sample }
                context.assets.open(assetPath).use { BitmapFactory.decodeStream(it, null, options) }
            } catch (_: IOException) {
                null
            }
        }
        bitmap?.let { cache.put(assetPath, it) }
        return bitmap
    }
}

/**
 * Kvadratna sličica postera u mozaiku kartice vrste. Posteri su 16:9 s figurom u sredini, pa ih povećanje
 * [zoom] približi, kao na iOS-u. Dok se slika učitava stoji prazna podloga.
 */
@Composable
internal fun ExercisePosterTile(posterPath: String, modifier: Modifier = Modifier, zoom: Float = 1.4f) {
    val context = LocalContext.current
    val assetPath = MoveKitAssets.assetPath(posterPath)
    val bitmap by produceState<Bitmap?>(null, assetPath) { value = ThumbnailCache.load(context, assetPath) }
    Box(
        modifier
            .aspectRatio(1f)
            .clipToBounds()
            .background(MaterialTheme.colorScheme.surfaceContainerHighest),
    ) {
        bitmap?.let {
            Image(
                it.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize().scale(zoom),
            )
        }
    }
}

/**
 * Mala sličica ispred naziva vježbe (trening, uređivač treninga, odabir vježbe): poster iz MoveKita ili
 * početno slovo kad postera nema (vlastita vježba, build bez MoveKit dodatka). Dodir otvara stranicu vježbe.
 */
@Composable
internal fun ExerciseRowThumbnail(
    name: String,
    posterPath: String?,
    modifier: Modifier = Modifier,
    size: Dp = 52.dp,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(14.dp)
    val base = modifier.size(size).clip(shape).let { if (onClick != null) it.clickable(onClick = onClick) else it }
    if (posterPath != null) {
        ExercisePosterTile(posterPath, base)
    } else {
        Box(base.background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
            Text(
                name.take(1).uppercase(LocalConfiguration.current.locales[0]),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

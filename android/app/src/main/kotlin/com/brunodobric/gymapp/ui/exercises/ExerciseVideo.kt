package com.brunodobric.gymapp.ui.exercises

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.provider.Settings
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.brunodobric.gymapp.R
import com.brunodobric.gymapp.catalog.ExerciseIllustration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException

/** Omjer stranica MoveKit klipova (1936 × 1072), isti kao na iOS-u. */
private const val VIDEO_ASPECT_RATIO = 1936f / 1072f

/**
 * Ilustracija službene vježbe na detalju, kao `ExerciseVideoView` na iOS-u: MoveKit klip u petlji bez zvuka,
 * ili samo poster. Bez MoveKit dodatka ne prikazuje ništa.
 */
@Composable
internal fun ExerciseIllustrationView(illustration: ExerciseIllustration, description: String, modifier: Modifier = Modifier) {
    when (illustration) {
        is ExerciseIllustration.Video -> ExerciseVideo(illustration.path, illustration.poster, description, modifier)
        is ExerciseIllustration.Poster -> IllustrationFrame(description, modifier) { PosterImage(illustration.path) }
        ExerciseIllustration.Unavailable -> Unit
    }
}

@Composable
private fun IllustrationFrame(description: String, modifier: Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(VIDEO_ASPECT_RATIO)
            .clip(RoundedCornerShape(12.dp))
            // Klipovi imaju svijetlu pozadinu i u tamnom načinu, pa podloga ostaje svijetla.
            .background(Color(0xFFEDEDED))
            .clearAndSetSemantics { contentDescription = description },
    ) { content() }
}

@Composable
private fun PosterImage(path: String) {
    val context = LocalContext.current
    val bitmap by produceState<Bitmap?>(null, path) {
        value = withContext(Dispatchers.IO) {
            try {
                context.assets.open(MoveKitAssets.assetPath(path)).use(BitmapFactory::decodeStream)
            } catch (_: IOException) {
                null
            }
        }
    }
    bitmap?.let {
        Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth())
    }
}

/**
 * Klip teče samo dok je ekran vidljiv i aplikacija u prvom planu. Kad su animacije u sustavu isključene
 * (Pristupačnost > Ukloni animacije), klip ne kreće sam: stoji poster, a korisnik ga pokreće gumbom.
 * Klip nema zvuk i ne traži audio fokus, pa ne prekida glazbu.
 */
@Composable
private fun ExerciseVideo(path: String, poster: String?, description: String, modifier: Modifier) {
    val context = LocalContext.current
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val reduceMotion = remember { animationsDisabled(context) }
    // Korisnikov izbor; null dok ga nije bilo (tada odlučuju sistemske animacije).
    var wantsPlaying by rememberSaveable(path) { mutableStateOf<Boolean?>(null) }
    var hasStarted by remember(path) { mutableStateOf(false) }
    val player = remember(path) { LoopingVideo(context, MoveKitAssets.assetPath(path)) { hasStarted = true } }
    val isPlaying = lifecycle.isAtLeast(Lifecycle.State.RESUMED) && (wantsPlaying ?: !reduceMotion)

    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(player, isPlaying) { player.setPlaying(isPlaying) }

    IllustrationFrame(description, modifier) {
        poster?.let { PosterImage(it) }
        AndroidView(
            factory = { TextureView(it).apply { surfaceTextureListener = player } },
            modifier = Modifier.matchParentSize().alpha(if (hasStarted) 1f else 0f),
        )
        IconButton(
            onClick = { wantsPlaying = !isPlaying },
            colors = IconButtonDefaults.iconButtonColors(containerColor = Color.White.copy(alpha = 0.85f), contentColor = Color.Black),
            modifier = Modifier.align(Alignment.BottomEnd).padding(10.dp).size(44.dp).clip(CircleShape),
        ) {
            if (isPlaying) {
                Icon(painterResource(R.drawable.ic_pause), contentDescription = stringResource(R.string.pause_animation))
            } else {
                Icon(Icons.Filled.PlayArrow, contentDescription = stringResource(R.string.play_animation))
            }
        }
    }
}

/** Sistemske animacije isključene (trajanje animacija 0), kao Smanji kretanje na iOS-u. */
private fun animationsDisabled(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

/** MediaPlayer za klip iz assets, u petlji i bez zvuka. Priprema se kad je površina za prikaz spremna. */
private class LoopingVideo(
    private val context: Context,
    private val assetPath: String,
    private val onFirstFrame: () -> Unit,
) : TextureView.SurfaceTextureListener {
    private var player: MediaPlayer? = null
    private var surface: Surface? = null
    private var prepared = false
    private var wantsPlaying = false

    fun setPlaying(playing: Boolean) {
        wantsPlaying = playing
        apply()
    }

    private fun apply() {
        val player = player ?: return
        if (!prepared) return
        if (wantsPlaying && !player.isPlaying) player.start()
        if (!wantsPlaying && player.isPlaying) player.pause()
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        val surface = Surface(texture).also { this.surface = it }
        val player = MediaPlayer()
        this.player = player
        try {
            context.assets.openFd(assetPath).use { player.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
        } catch (_: IOException) {
            release()
            return
        }
        player.setSurface(surface)
        player.isLooping = true
        player.setVolume(0f, 0f)
        player.setOnInfoListener { _, what, _ ->
            if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) onFirstFrame()
            false
        }
        player.setOnPreparedListener {
            prepared = true
            // Prvi kadar se iscrta i kad klip stoji, da se ne vidi samo poster niže kvalitete.
            it.seekTo(0)
            apply()
        }
        player.setOnErrorListener { _, _, _ ->
            release()
            true
        }
        player.prepareAsync()
    }

    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
        release()
        return true
    }

    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit

    fun release() {
        player?.release()
        player = null
        prepared = false
        surface?.release()
        surface = null
    }
}

package com.brunodobric.gymapp.ui.statistics

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import com.brunodobric.gymapp.stats.BodyMap
import com.brunodobric.gymapp.stats.BodyMapDiagram
import com.brunodobric.gymapp.stats.BodyRegion
import com.brunodobric.gymapp.stats.PathCommand
import com.brunodobric.gymapp.stats.RegionLoad
import com.brunodobric.gymapp.stats.SVGPathParser

/** Pročitane putanje jednog crteža: obris i mišićne plohe s regijom heatmapa. */
private class ParsedDiagram(val bounds: List<Double>, val outline: List<List<PathCommand>>, val muscles: List<Pair<String?, List<PathCommand>>>)

private fun parse(diagram: BodyMapDiagram) = ParsedDiagram(
    bounds = diagram.bounds,
    outline = diagram.outline.map { SVGPathParser.parse(it.pathData) },
    muscles = diagram.muscles.map { shape ->
        shape.group?.let { BodyRegion.regionForBodyMapGroup(it) } to SVGPathParser.parse(shape.pathData)
    },
)

/** Putanja skalirana iz vidljivog dijela crteža (`bounds`) na zadanu širinu i visinu. */
private fun path(commands: List<PathCommand>, box: List<Double>, width: Float, height: Float): Path {
    val scaleX = width / box[2]
    val scaleY = height / box[3]
    fun x(value: Double) = ((value - box[0]) * scaleX).toFloat()
    fun y(value: Double) = ((value - box[1]) * scaleY).toFloat()
    return Path().apply {
        for (command in commands) {
            when (command) {
                is PathCommand.Move -> moveTo(x(command.x), y(command.y))
                is PathCommand.Line -> lineTo(x(command.x), y(command.y))
                is PathCommand.Curve -> cubicTo(x(command.c1x), y(command.c1y), x(command.c2x), y(command.c2y), x(command.x), y(command.y))
                PathCommand.Close -> close()
            }
        }
    }
}

/**
 * Jedno tijelo (sprijeda ili straga) s mišićima obojenima prema intenzitetu regije (`BodyFigureView` na
 * iOS-u). Dodir na mišić bira njegovu regiju, drugi dodir je odznačuje.
 */
@Composable
internal fun BodyFigure(
    diagrams: Map<String, BodyMapDiagram>,
    female: Boolean,
    back: Boolean,
    heatmap: Map<String, RegionLoad>,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val currentOnSelect by rememberUpdatedState(onSelect)
    val key = BodyMap.key(female, back)
    val parsed = remember(diagrams, key) { diagrams[key]?.let(::parse) } ?: return
    val box = parsed.bounds
    val accent = MaterialTheme.colorScheme.primary
    val outlineColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
    val idle = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.22f)
    val selectedStroke = MaterialTheme.colorScheme.onSurface

    // Putanje u pikselima ovise o veličini, pa se dodir provjerava nad istim putanjama koje se crtaju.
    val cache = remember(parsed) { mutableMapOf<Pair<Int, Int>, List<Pair<String?, Path>>>() }
    fun muscles(width: Float, height: Float) = cache.getOrPut(width.toInt() to height.toInt()) {
        parsed.muscles.map { (region, commands) -> region to path(commands, box, width, height) }
    }

    Canvas(
        modifier
            .fillMaxWidth()
            .aspectRatio((box[2] / box[3]).toFloat())
            .pointerInput(parsed, selected) {
                detectTapGestures { offset ->
                    val hit = muscles(size.width.toFloat(), size.height.toFloat()).lastOrNull { (region, shape) ->
                        region != null && contains(shape, offset.x, offset.y)
                    }?.first
                    if (hit != null) currentOnSelect(if (hit == selected) null else hit)
                }
            },
    ) {
        for (commands in parsed.outline) drawPath(path(commands, box, size.width, size.height), outlineColor)
        for ((region, shape) in muscles(size.width, size.height)) {
            val intensity = region?.let { heatmap[it]?.intensity } ?: 0.0
            drawPath(shape, heatColor(intensity, accent, idle))
            if (region != null && region == selected) drawPath(shape, selectedStroke, style = Stroke(width = 3f))
        }
    }
}

/** Je li točka unutar putanje (android.graphics.Region nad granicama putanje). */
private fun contains(path: Path, x: Float, y: Float): Boolean {
    val bounds = path.getBounds()
    if (!bounds.contains(androidx.compose.ui.geometry.Offset(x, y))) return false
    val clip = android.graphics.Region(bounds.left.toInt(), bounds.top.toInt(), bounds.right.toInt() + 1, bounds.bottom.toInt() + 1)
    val region = android.graphics.Region()
    region.setPath(path.asAndroidPath(), clip)
    return region.contains(x.toInt(), y.toInt())
}

/** Boja mišića za intenzitet 0...1; 0 je neopterećen mišić (sivo). Koristi je i legenda heatmapa. */
internal fun heatColor(intensity: Double, accent: Color, idle: Color): Color =
    if (intensity > 0) accent.copy(alpha = (0.25 + 0.75 * intensity).toFloat()) else idle

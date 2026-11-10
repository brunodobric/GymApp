package com.brunodobric.gymapp.ui

import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/** Jednostavna crta bez osi: vrijednosti po redu, skalirane između najmanje i najveće. */
@Composable
fun LineChart(values: List<Double>, modifier: Modifier) {
    val color = MaterialTheme.colorScheme.primary
    Canvas(modifier) {
        val shown = values.filter { it > 0 }
        if (shown.size < 2) return@Canvas
        val low = shown.min()
        val high = shown.max()
        val span = (high - low).takeIf { it > 0 } ?: 1.0
        val step = size.width / (shown.size - 1)
        val path = Path()
        shown.forEachIndexed { index, value ->
            val x = index * step
            val y = size.height - ((value - low) / span * size.height * 0.9 + size.height * 0.05).toFloat()
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
            drawCircle(color, radius = 3.dp.toPx(), center = Offset(x, y))
        }
        drawPath(path, color, style = Stroke(width = 2.dp.toPx()))
    }
}

/** Niz točaka (vrijeme u milisekundama, vrijednost) jedne crte na [DatedLineChart]. */
data class ChartSeries(val points: List<Pair<Long, Double>>, val color: Color)

/**
 * Crte po datumu na zajedničkim osima (graf napretka i usporedba dviju vježbi, kao `Chart` s `LineMark` na
 * iOS-u). Os x ide od prve do zadnje točke svih crta, os y od najmanje do najveće vrijednosti.
 */
@Composable
fun DatedLineChart(series: List<ChartSeries>, modifier: Modifier) {
    Canvas(modifier) {
        val all = series.flatMap { it.points }.filter { it.second > 0 }
        if (all.isEmpty()) return@Canvas
        val firstX = all.minOf { it.first }
        val lastX = all.maxOf { it.first }
        val spanX = (lastX - firstX).takeIf { it > 0 }?.toFloat() ?: 1f
        val low = all.minOf { it.second }
        val high = all.maxOf { it.second }
        val spanY = (high - low).takeIf { it > 0 } ?: 1.0
        series.forEach { line ->
            val shown = line.points.filter { it.second > 0 }.sortedBy { it.first }
            val path = Path()
            shown.forEachIndexed { index, (time, value) ->
                val x = if (lastX == firstX) size.width / 2 else (time - firstX) / spanX * size.width
                val y = size.height - ((value - low) / spanY * size.height * 0.9 + size.height * 0.05).toFloat()
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
                drawCircle(line.color, radius = 3.dp.toPx(), center = Offset(x, y))
            }
            if (shown.size > 1) drawPath(path, line.color, style = Stroke(width = 2.dp.toPx()))
        }
    }
}

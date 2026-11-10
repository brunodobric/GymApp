package com.brunodobric.gymapp.ui

import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
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

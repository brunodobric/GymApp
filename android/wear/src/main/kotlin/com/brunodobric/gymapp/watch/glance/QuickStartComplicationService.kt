package com.brunodobric.gymapp.watch.glance

import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.watch.WatchApplication
import com.brunodobric.gymapp.watch.WorkoutService
import com.brunodobric.gymapp.wear.WatchGlance

/**
 * Komplikacija "Započni trening" (`QuickStartComplication` na iOS-u): ▶ koji otvara aplikaciju na satu,
 * spremnu za početak treninga. Kratki tekst uz ▶ pokazuje sljedeći trening.
 */
class QuickStartComplicationService : ComplicationDataSourceService() {
    override fun onComplicationRequest(request: ComplicationRequest, listener: ComplicationRequestListener) {
        val glance = WatchGlance.from((application as WatchApplication).store.state.value)
        listener.onComplicationData(data(request.complicationType, glance.next?.name))
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? = data(type, "Push")

    private fun data(type: ComplicationType, nextName: String?): ComplicationData? {
        val description = PlainComplicationText.Builder(getString(R.string.complication_quick_start)).build()
        val icon = MonochromaticImage.Builder(Icon.createWithResource(this, R.drawable.ic_play)).build()
        val tap = WorkoutService.openAppIntent(this)
        return when (type) {
            ComplicationType.MONOCHROMATIC_IMAGE -> MonochromaticImageComplicationData.Builder(icon, description)
                .setTapAction(tap)
                .build()
            ComplicationType.SHORT_TEXT -> {
                val label = (nextName ?: getString(R.string.start)).take(SHORT_TEXT_LENGTH)
                ShortTextComplicationData.Builder(PlainComplicationText.Builder(label).build(), description)
                    .setMonochromaticImage(icon)
                    .setTapAction(tap)
                    .build()
            }
            else -> null
        }
    }

    private companion object {
        const val SHORT_TEXT_LENGTH = 7
    }
}

package com.brunodobric.gymapp.watch.glance

import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import com.brunodobric.gymapp.watch.R
import com.brunodobric.gymapp.watch.WatchApplication
import com.brunodobric.gymapp.watch.WorkoutService
import com.brunodobric.gymapp.units.WeightUnit
import com.brunodobric.gymapp.wear.WatchGlance

/** Komplikacija "Težina" (`BodyWeightComplication` na iOS-u): zadnja tjelesna težina s mobitela. */
class BodyWeightComplicationService : ComplicationDataSourceService() {
    override fun onComplicationRequest(request: ComplicationRequest, listener: ComplicationRequestListener) {
        val glance = WatchGlance.from((application as WatchApplication).store.state.value)
        listener.onComplicationData(data(request.complicationType, glance))
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        data(type, WatchGlance(bodyWeightKg = 82.4, unit = WeightUnit.KILOGRAMS))

    private fun data(type: ComplicationType, glance: WatchGlance): ComplicationData? {
        val number = glance.bodyWeightNumber() ?: "–"
        val symbol = glance.unit.symbol
        val name = getString(R.string.complication_body_weight)
        val description = PlainComplicationText.Builder("$name $number $symbol").build()
        val icon = MonochromaticImage.Builder(Icon.createWithResource(this, R.drawable.ic_body)).build()
        val tap = WorkoutService.openAppIntent(this)
        return when (type) {
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(PlainComplicationText.Builder(number).build(), description)
                .setTitle(PlainComplicationText.Builder(symbol).build())
                .setMonochromaticImage(icon)
                .setTapAction(tap)
                .build()
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(PlainComplicationText.Builder("$number $symbol").build(), description)
                .setTitle(PlainComplicationText.Builder(name).build())
                .setMonochromaticImage(icon)
                .setTapAction(tap)
                .build()
            else -> null
        }
    }
}

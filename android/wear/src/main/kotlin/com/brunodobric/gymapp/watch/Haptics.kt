package com.brunodobric.gymapp.watch

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import com.brunodobric.gymapp.wear.Haptic

/** Vibracija za kvačicu, grešku i kraj odmora (`WKInterfaceDevice.play` na satu). */
class Haptics(context: Context) {
    private val vibrator = context.getSystemService(Vibrator::class.java)

    fun play(haptic: Haptic) {
        val vibrator = vibrator ?: return
        val effect = when (haptic) {
            Haptic.SUCCESS -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
            Haptic.CLICK -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
            Haptic.FAILURE -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK)
            // Kraj odmora: dvaput dulje, da se osjeti i tijekom serije.
            Haptic.NOTIFICATION -> VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300), -1)
        }
        runCatching { vibrator.vibrate(effect) }
    }
}

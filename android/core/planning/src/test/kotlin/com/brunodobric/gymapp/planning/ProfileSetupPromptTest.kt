package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.model.EquipmentPreset
import com.brunodobric.gymapp.model.Sex
import com.brunodobric.gymapp.model.UserSettings
import org.junit.jupiter.api.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ProfileSetupPromptTest {
    @Test
    fun `samo nakon onboardinga bez odgovora o treningu, bez rasporeda i dok nije zatvorena`() {
        val settings = UserSettings()
        assertFalse(ProfileSetupPrompt.isShown(null, 0, false))
        // Dok traje onboarding kartica nema smisla.
        assertFalse(ProfileSetupPrompt.isShown(settings, 0, false))
        settings.onboardingCompleted = true
        assertTrue(ProfileSetupPrompt.isShown(settings, 0, false))
        assertFalse(ProfileSetupPrompt.isShown(settings, 0, true))
        assertFalse(ProfileSetupPrompt.isShown(settings, 1, false))
        // Spol, jedinice i zdravstveni podaci nisu odgovori o treningu.
        settings.sex = Sex.FEMALE
        settings.wantsHealthKit = true
        assertTrue(ProfileSetupPrompt.isShown(settings, 0, false))
        settings.equipment = EquipmentPreset.GYM.equipment
        assertFalse(ProfileSetupPrompt.isShown(settings, 0, false))
    }
}

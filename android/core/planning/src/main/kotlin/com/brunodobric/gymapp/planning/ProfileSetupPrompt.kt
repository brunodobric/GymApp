package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.model.UserSettings

/**
 * Kartica "Postavi profil" na Početnoj (`ProfileSetupPrompt` na iOS-u): naknadno ispunjavanje onboardinga kad ga
 * je korisnik preskočio ili ostavio prazan, a još nema nijedan raspored. Zatvara se križićem ili sama nestaje kad
 * korisnik odgovori o treningu ili doda raspored.
 */
object ProfileSetupPrompt {
    fun isShown(settings: UserSettings?, scheduleCount: Int, dismissed: Boolean): Boolean {
        if (settings == null || !settings.onboardingCompleted || dismissed || scheduleCount > 0) return false
        return !TrainingProfile.from(settings).hasAnswers
    }
}

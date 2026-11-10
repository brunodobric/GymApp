package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.WorkoutError
import java.time.Instant
import java.util.UUID

/** Ishod pokretanja treninga iz prečaca (pločica u brzim postavkama, prečac na ikoni, widget). */
sealed interface ShortcutStartResult {
    /** Trening je već u tijeku: novi se ne pokreće, nego se otvara taj. */
    data class AlreadyActive(val session: Session) : ShortcutStartResult
    data class Started(val session: Session) : ShortcutStartResult

    /** Nema aktivnog rasporeda s treningom koji slijedi. */
    data object NothingScheduled : ShortcutStartResult
}

/** Ishod završavanja treninga iz prečaca. */
sealed interface ShortcutFinishResult {
    data object NoActiveWorkout : ShortcutFinishResult

    /** Trening vodi sat (na iOS-u Apple Watch). Android zasad nema sat, ali pravilo ostaje isto. */
    data class LedByWatch(val session: Session) : ShortcutFinishResult

    /** Nijedna serija nije završena, pa se trening ne može spremiti (na ekranu treninga nudi se odbacivanje). */
    data class NothingCompleted(val session: Session) : ShortcutFinishResult
    data class Finished(val session: Session) : ShortcutFinishResult
}

sealed class ShortcutError(message: String) : Exception(message) {
    /** Odabrani trening je u međuvremenu obrisan ili više nema vježbi. */
    data object TemplateUnavailable : ShortcutError("Trening nije dostupan")
}

/**
 * Radnje za prečace (App Intents na iOS-u). Pravila su ista kao na Početnoj i ekranu treninga, a aplikacija
 * nakon njih samo javlja promjenu obavijesti treninga, widgetima i podsjetnicima.
 */
class WorkoutShortcuts(private val store: GymStore) {

    /** Spremljeni treninzi koje akcija "Započni trening" nudi (isti kao izbor na Početnoj). */
    fun startableTemplates(): List<WorkoutTemplate> = TemplateStarter.startable(store.templates)

    /**
     * Spremljeni treninzi za dinamičke prečace na ikoni (samo Android): najprije oni koji su zadnji pokretani,
     * zatim ostali po nazivu. Najviše [limit].
     */
    fun recentTemplates(limit: Int): List<WorkoutTemplate> {
        val lastStarted = store.sessions.filter { it.templateId != null }
            .groupBy { it.templateId }
            .mapValues { (_, sessions) -> sessions.maxOf { it.startedAt } }
        val startable = startableTemplates()
        return startable.withIndex()
            .sortedWith(compareByDescending<IndexedValue<WorkoutTemplate>> { lastStarted[it.value.id] ?: Instant.MIN }.thenBy { it.index })
            .map { it.value }
            .take(limit.coerceAtLeast(0))
    }

    /**
     * Pokreće spremljeni trening, a bez njega prazan trening s nazivom `emptyName`.
     *
     * Ako je odabrani trening u aktivnom rasporedu, pokreće se kao trening rasporeda (s izmjenama ciklusa),
     * pa raspored napreduje kad se završi, isto kao "Odaberi drugi trening" ispod rasporeda na Početnoj.
     */
    fun start(templateId: UUID?, emptyName: String, now: Instant = Instant.now()): ShortcutStartResult {
        store.activeSession()?.let { return ShortcutStartResult.AlreadyActive(it) }
        if (templateId == null) return ShortcutStartResult.Started(WorkoutEngine(store).startSession(emptyName, now = now))
        val template = startableTemplates().firstOrNull { it.id == templateId } ?: throw ShortcutError.TemplateUnavailable
        val starter = TemplateStarter(store)
        val session = scheduled(templateId)?.let { starter.start(it, now) } ?: starter.start(template, now)
        return ShortcutStartResult.Started(session)
    }

    /** Pokreće sljedeći trening aktivnog rasporeda (prvog, ako ih je više), kao prvi gumb na Početnoj. */
    fun startNextScheduled(now: Instant = Instant.now()): ShortcutStartResult {
        store.activeSession()?.let { return ShortcutStartResult.AlreadyActive(it) }
        val planned = ScheduleEngine(store).upcomingWorkouts().firstOrNull() ?: return ShortcutStartResult.NothingScheduled
        return ShortcutStartResult.Started(TemplateStarter(store).start(planned, now))
    }

    /**
     * Završava trening u tijeku kao gumb "Završi": nezavršene serije se brišu, a raspored napreduje
     * ako je to bio njegov trening.
     */
    fun finishActive(now: Instant = Instant.now()): ShortcutFinishResult {
        val session = store.activeSession() ?: return ShortcutFinishResult.NoActiveWorkout
        if (session.controllingDevice != DeviceRole.PHONE) return ShortcutFinishResult.LedByWatch(session)
        try {
            WorkoutEngine(store).finishSession(session, now = now)
        } catch (_: WorkoutError.NothingCompleted) {
            return ShortcutFinishResult.NothingCompleted(session)
        }
        // Kao na ekranu treninga: trening je spremljen i kad napredovanje rasporeda ne uspije.
        runCatching { ScheduleEngine(store).sessionFinished(session) }
        return ShortcutFinishResult.Finished(session)
    }

    /** Trening iz aktivnog rasporeda s tim predloškom: prvo sljedeći trening, zatim ostali treninzi rasporeda. */
    private fun scheduled(templateId: UUID): PlannedWorkout? {
        val engine = ScheduleEngine(store)
        val upcoming = engine.upcomingWorkouts()
        upcoming.firstOrNull { it.template.id == templateId }?.let { return it }
        for (planned in upcoming) {
            engine.workoutChoices(planned.schedule).firstOrNull { it.template.id == templateId }?.let { return it }
        }
        return null
    }
}

package com.brunodobric.gymapp.widgets

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.WeightStepSettings
import com.brunodobric.gymapp.planning.PlannedWorkout
import com.brunodobric.gymapp.planning.ScheduleEngine
import com.brunodobric.gymapp.stats.BodyTracking
import com.brunodobric.gymapp.stats.StatisticsEngine
import com.brunodobric.gymapp.stats.StatsCalendar
import com.brunodobric.gymapp.stats.WeekProgress
import com.brunodobric.gymapp.stats.weekProgress
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.PersonalRecord
import com.brunodobric.gymapp.training.SessionCardio
import com.brunodobric.gymapp.training.SessionMix
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.SetPlanner
import com.brunodobric.gymapp.training.WorkoutEngine
import com.brunodobric.gymapp.training.WorkoutSummary
import com.brunodobric.gymapp.training.previousSetValues
import com.brunodobric.gymapp.training.target
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * Slaže snimku za widgete ([WidgetSnapshot]) iz baze (`WidgetSnapshotBuilder` na iOS-u): trening u tijeku,
 * sljedeći trening, tekući tjedan, tjelesnu težinu, zadnji trening i najnoviji rekord.
 * Što ovisi o katalogu i jeziku daje aplikacija: je li vježba kardio ili složena i tekst rekorda.
 */
class WidgetSnapshotBuilder(
    private val store: GymStore,
    private val isCardio: (String) -> Boolean = { false },
    private val isCompound: (String) -> Boolean? = { null },
    /** Vrijednost rekorda za prikaz, npr. "120 kg × 5". */
    private val recordText: (PersonalRecord) -> String,
) {
    fun make(now: Instant = Instant.now(), calendar: StatsCalendar = StatsCalendar.system()): WidgetSnapshot {
        val settings = store.settings()
        val progress = StatisticsEngine(store).weekProgress(now, settings.trainingDaysPerWeek, calendar, isCardio)
        var snapshot = WidgetSnapshot(
            generatedAt = now,
            accent = settings.accent.raw,
            weightUnit = settings.weightUnit.raw,
            activeWorkout = store.activeSession()?.let { WidgetSnapshot.ActiveWorkout(it.name, it.startedAt) },
            nextWorkout = ScheduleEngine(store).upcomingWorkouts().firstOrNull()?.let(::nextWorkout),
            week = week(progress),
            bodyWeight = bodyWeight(),
        )
        snapshot = addRecentSessions(snapshot)
        return snapshot
    }

    private fun nextWorkout(planned: PlannedWorkout): WidgetSnapshot.NextWorkout {
        val sources = planned.template.orderedExercises.associateBy { it.id }
        val settings = store.settings()
        val step = WeightStepSettings.resolver(settings, null, emptyList())
        val exercises = planned.exercises.take(WidgetSnapshot.NextWorkout.MAX_EXERCISES).map { exercise ->
            val targets = if (exercise.isReplacement) emptyList() else sources[exercise.source]?.orderedSets.orEmpty()
            val previous = store.previousSetValues(exercise.ref, planned.template.id)
            val working = plannedSets(
                previous, targets, exercise.inputType,
                if (settings.suggestsHeavierWeight) step(exercise.ref) else null, settings.weightUnit,
            )
                .filter { it.kind == SetKind.WORKING }
            val first = working.firstOrNull()
            WidgetSnapshot.PlannedExercise(
                exercise.ref.name, working.size, first?.reps, first?.weightKg ?: first?.extraWeightKg, first?.durationSeconds,
            )
        }
        return WidgetSnapshot.NextWorkout(planned.template.name, planned.schedule.name, planned.exercises.size, exercises)
    }

    private fun bodyWeight(): WidgetSnapshot.BodyWeight? {
        val tracking = BodyTracking(store)
        val all = tracking.measurements(BodyMeasurementKind.WEIGHT)
        val latest = all.lastOrNull() ?: return null
        return WidgetSnapshot.BodyWeight(
            latest.value, latest.date, tracking.recentChange(BodyMeasurementKind.WEIGHT),
            all.takeLast(WidgetSnapshot.BodyWeight.MAX_POINTS).map { it.value },
        )
    }

    /** Zadnji trening i najnoviji rekord iz zadnjih treninga. */
    private fun addRecentSessions(snapshot: WidgetSnapshot): WidgetSnapshot {
        val recent = store.ownFinishedSessions().take(RECORD_LOOKBACK)
        if (recent.isEmpty()) return snapshot
        val settings = store.settings()
        val engine = WorkoutEngine(store)
        val trackedKinds = PRKind.tracked(settings)
        val summaries = mutableMapOf<UUID, WorkoutSummary?>()
        fun summary(session: Session): WorkoutSummary? = summaries.getOrPut(session.id) {
            runCatching {
                engine.summary(session, trackedKinds, settings.prExcludedExerciseKeys, isCompound, isCardio)
            }.getOrNull()
        }

        val last = recent.first()
        val lastSummary = summary(last)
        val lastWorkout = WidgetSnapshot.LastWorkout(
            last.name, last.startedAt,
            last.endedAt?.let { Duration.between(last.startedAt, it).seconds.coerceAtLeast(0).toInt() },
            mix(SessionCardio.mix(last, isCardio)),
            lastSummary?.hardSets ?: 0,
            lastSummary?.highlights.orEmpty().map { WidgetSnapshot.Highlight(it.exerciseName, recordText(it.record)) },
        )
        val record = recent.firstNotNullOfOrNull { session ->
            summary(session)?.highlights?.firstOrNull()?.let {
                WidgetSnapshot.Record(it.exerciseName, recordText(it.record), session.startedAt, session.id.toString().uppercase())
            }
        }
        return snapshot.copy(lastWorkout = lastWorkout, latestRecord = record)
    }

    companion object {
        /** Koliko se zadnjih treninga gleda za najnoviji rekord. */
        const val RECORD_LOOKBACK = 5

        internal fun week(progress: WeekProgress) = WidgetSnapshot.Week.of(
            progress.start,
            progress.days.map { WidgetSnapshot.Week.Day(it.date, it.strength, it.cardio) },
            progress.sessions, progress.goal, progress.streakWeeks,
            progress.hardSets, progress.cardioSeconds, progress.totalSeconds.toInt(),
        )

        internal fun mix(mix: SessionMix) = when (mix) {
            SessionMix.STRENGTH -> WidgetSnapshot.Mix.STRENGTH
            SessionMix.CARDIO -> WidgetSnapshot.Mix.CARDIO
            SessionMix.MIXED -> WidgetSnapshot.Mix.MIXED
        }

        /**
         * Serije nove vježbe po istim pravilima kao `WorkoutEngine.addExercise` i `TemplateStarter` ([SetPlanner],
         * `WatchContextBuilder.plannedSets` na iOS-u).
         */
        internal fun plannedSets(
            previous: List<SetValues>,
            targets: List<TemplateSet>,
            inputType: ExerciseInputType,
            weightStep: Double? = null,
            unit: WeightUnit = WeightUnit.KILOGRAMS,
        ): List<SetValues> = SetPlanner.plan(
            previous = previous, targets = targets.map { it.target }, inputType = inputType, weightStep = weightStep, unit = unit,
        ).sets
    }
}


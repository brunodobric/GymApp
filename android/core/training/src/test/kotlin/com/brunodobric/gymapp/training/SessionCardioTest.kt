package com.brunodobric.gymapp.training

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull

private val press = ExerciseRef.catalog("press", "Potisak s klupe")
private val treadmill = ExerciseRef.catalog("treadmill", "Traka za trčanje")
private val bike = ExerciseRef.catalog("bike", "Sobni bicikl")
private val start = Instant.ofEpochSecond(1_800_000_000)
private val isCardio: (String) -> Boolean = { it == "c:treadmill" || it == "c:bike" }

private data class Entry(
    val ref: ExerciseRef,
    val inputType: ExerciseInputType = ExerciseInputType.WEIGHT_REPS,
    val weight: Double? = null,
    val reps: Int? = null,
    val seconds: Int? = null,
    val meters: Double? = null,
    val completed: Boolean = true,
)

private fun makeSession(entries: List<Entry>, kind: WorkoutKind = WorkoutKind.STRENGTH): Session {
    val session = Session("Trening", kind, start)
    session.state = SessionState.FINISHED
    entries.forEachIndexed { index, entry ->
        val exercise = session.add(SessionExercise(index, entry.ref, entry.inputType))
        val set = exercise.add(SetLog(0))
        set.weightKg = entry.weight
        set.reps = entry.reps
        set.durationSeconds = entry.seconds
        set.distanceMeters = entry.meters
        set.completedAt = if (entry.completed) start.plusSeconds(600) else null
    }
    return session
}

private val lift = Entry(press, weight = 100.0, reps = 5)
private val run = Entry(treadmill, ExerciseInputType.DURATION_DISTANCE, seconds = 900, meters = 2500.0)

class SessionCardioTest {

    @Test
    fun `vrsta za prikaz - snaga, kardio i mješoviti trening`() {
        assertEquals(SessionMix.STRENGTH, SessionCardio.mix(makeSession(listOf(lift)), isCardio))
        assertEquals(SessionMix.MIXED, SessionCardio.mix(makeSession(listOf(lift, run)), isCardio))
        assertEquals(SessionMix.CARDIO, SessionCardio.mix(makeSession(listOf(run)), isCardio))
        assertEquals(SessionMix.CARDIO, SessionCardio.mix(makeSession(emptyList(), WorkoutKind.CARDIO), isCardio))
        assertEquals(SessionMix.STRENGTH, SessionCardio.mix(makeSession(listOf(lift, run.copy(completed = false))), isCardio))
        assertEquals(setOf(WorkoutKind.STRENGTH, WorkoutKind.CARDIO), SessionMix.MIXED.kinds)
    }

    @Test
    fun `kardio dio - zbroj vremena i udaljenosti odrađenih kardio serija`() {
        val cycling = Entry(bike, ExerciseInputType.DURATION, seconds = 600)
        assertEquals(CardioPart(1500, 2500.0), SessionCardio.part(makeSession(listOf(cycling, lift, run)), isCardio))
        assertEquals(CardioPart(600), SessionCardio.part(makeSession(listOf(cycling)), isCardio))
        assertNull(SessionCardio.part(makeSession(listOf(lift)), isCardio))
    }

    @Test
    fun `vrsta predloška iz vježbi, a kardio plan ostaje kardio`() {
        fun template(refs: List<ExerciseRef>, kind: WorkoutKind = WorkoutKind.STRENGTH) =
            WorkoutTemplate("Trening", kind).apply { refs.forEachIndexed { index, ref -> add(TemplateExercise(index, ref)) } }
        assertEquals(SessionMix.STRENGTH, SessionCardio.mix(template(listOf(press)), isCardio))
        assertEquals(SessionMix.MIXED, SessionCardio.mix(template(listOf(press, bike)), isCardio))
        assertEquals(SessionMix.CARDIO, SessionCardio.mix(template(listOf(treadmill, bike)), isCardio))
        assertEquals(SessionMix.STRENGTH, SessionCardio.mix(template(emptyList()), isCardio))
        assertEquals(SessionMix.CARDIO, SessionCardio.mix(template(emptyList(), WorkoutKind.CARDIO), isCardio))
    }
}

class PRRankingTest {

    @Test
    fun `veći napredak na složenoj vježbi je ispred malog napretka na izolacijskoj`() {
        val deadlift = RecordCandidate("c:deadlift", "Mrtvo dizanje", listOf(PersonalRecord(PRKind.ESTIMATED_ONE_REP_MAX, 205.0, 200.0)), true)
        val curl = RecordCandidate("c:curl", "Pregib", listOf(PersonalRecord(PRKind.MAX_REPS, 13.0, 12.0)), false)
        val volume = RecordCandidate("c:row", "Veslanje", listOf(PersonalRecord(PRKind.EXERCISE_VOLUME, 2000.0, 1000.0, showsInSummary = false)), null)
        val result = PRRanking.highlights(listOf(curl, deadlift, volume))
        assertEquals(listOf("c:deadlift", "c:curl"), result.shown.map { it.exerciseKey })
        assertEquals(1, result.hiddenCount)
        assertEquals(1, PRRanking.highlights(listOf(curl, deadlift), limit = 1).shown.size)
    }

    @Test
    fun `glavni rekord vježbe ide po prioritetu, a manja pomoć je napredak`() {
        val records = listOf(
            PersonalRecord(PRKind.MAX_WEIGHT, 100.0, 95.0),
            PersonalRecord(PRKind.ESTIMATED_ONE_REP_MAX, 120.0, 115.0),
        )
        assertEquals(PRKind.ESTIMATED_ONE_REP_MAX, PRRanking.headline(records)?.kind)
        val assistance = PersonalRecord(PRKind.LOWEST_ASSISTANCE, 20.0, 25.0)
        assert(PRRanking.significance(assistance, null) > 0)
        assertEquals(0.0, PRRanking.significance(PersonalRecord(PRKind.MAX_REPS, 10.0, null), null))
    }
}

package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.DeviceRole
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.WorkoutKind
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

private val base: Instant = Instant.ofEpochSecond(1_800_000_000)

private fun minute(value: Double): Instant = base.plusMillis((value * 60_000).toLong())

// Port GymKit/Tests/HealthSyncTests (spremanje treninga u Zdravlje).
class HealthExportTest {
    private val cardioKeys: (String) -> Boolean = { it == "c:bike" || it == "c:treadmill" }

    private fun finishedSession(kind: WorkoutKind = WorkoutKind.STRENGTH): Session {
        val session = Session("Push", kind, base)
        session.state = SessionState.FINISHED
        session.endedAt = base.plusSeconds(3_600)
        return session
    }

    /** Dodaje vježbu s odrađenim serijama: (minuta od početka kad je serija označena, trajanje serije u minutama). */
    private fun Session.addExercise(key: String, sets: List<Pair<Double, Int?>>) {
        val input = if (sets.any { it.second != null }) ExerciseInputType.DURATION else ExerciseInputType.WEIGHT_REPS
        val exercise = add(SessionExercise(orderedExercises.size, ExerciseRef.catalog(key, key), input))
        sets.forEachIndexed { index, (at, minutes) ->
            val set = exercise.add(SetLog(index))
            set.durationSeconds = minutes?.let { it * 60 }
            set.completedAt = minute(at)
        }
    }

    @Test
    fun `zavrseni trening s telefona se sprema kao trening snage`() {
        val session = finishedSession()
        val export = assertNotNull(HealthWorkoutExport.make(session))
        assertEquals(HealthActivity.STRENGTH_TRAINING, export.activity)
        assertEquals(session.id, export.sessionId)
        assertEquals(base, export.start)
        assertEquals(base.plusSeconds(3_600), export.end)
        assertEquals(HealthActivity.MIXED_CARDIO, HealthWorkoutExport.make(finishedSession(WorkoutKind.CARDIO))?.activity)
    }

    @Test
    fun `bicikl za zagrijavanje i traka na kraju - kardio, snaga, kardio`() {
        val session = finishedSession()
        session.addExercise("bike", listOf(10.0 to 10))
        session.addExercise("bench", listOf(15.0 to null, 20.0 to null, 40.0 to null))
        session.addExercise("treadmill", listOf(58.0 to 15))

        val export = assertNotNull(HealthWorkoutExport.make(session, cardioKeys))
        assertEquals(
            listOf(
                HealthWorkoutSegment(HealthActivity.MIXED_CARDIO, base, minute(10.0)),
                HealthWorkoutSegment(HealthActivity.STRENGTH_TRAINING, minute(10.0), minute(43.0)),
                // Traka je završila 2 minute prije kraja treninga, pa kardio ide do kraja.
                HealthWorkoutSegment(HealthActivity.MIXED_CARDIO, minute(43.0), minute(60.0)),
            ),
            export.segments,
        )
        assertEquals(1, export.primaryIndex)
        assertEquals(HealthActivity.STRENGTH_TRAINING, export.activity)
        assertEquals(base, export.start)
        assertEquals(minute(60.0), export.end)
    }

    @Test
    fun `bez kardija jedan dio snage, samo kardio jedan kardio dio`() {
        val strength = finishedSession().apply { addExercise("bench", listOf(20.0 to null)) }
        val cardioOnly = finishedSession().apply { addExercise("treadmill", listOf(30.0 to 25)) }
        assertEquals(
            listOf(HealthWorkoutSegment(HealthActivity.STRENGTH_TRAINING, base, minute(60.0))),
            HealthWorkoutExport.make(strength, cardioKeys)?.segments,
        )
        assertEquals(
            listOf(HealthWorkoutSegment(HealthActivity.MIXED_CARDIO, base, minute(60.0))),
            HealthWorkoutExport.make(cardioOnly, cardioKeys)?.segments,
        )
    }

    @Test
    fun `kardio serija bez trajanja ne dijeli trening`() {
        val session = finishedSession()
        session.addExercise("bench", listOf(20.0 to null))
        session.addExercise("bike", listOf(50.0 to null))
        assertEquals(1, HealthWorkoutExport.make(session, cardioKeys)?.segments?.size)
    }

    @Test
    fun `ne sprema se trening u tijeku, sa sata, vec spremljen ni uvezen`() {
        val active = Session("U tijeku", WorkoutKind.STRENGTH, base)
        val watch = finishedSession().apply { controllingDevice = DeviceRole.WATCH }
        val saved = finishedSession().apply { healthKitWorkoutId = UUID.randomUUID() }
        val imported = finishedSession(WorkoutKind.CARDIO).apply { isImportedFromWorkoutsApp = true }
        val recordedByWatch = finishedSession().apply { healthRecordedByWatch = true }
        listOf(active, watch, saved, imported, recordedByWatch).forEach { assertNull(HealthWorkoutExport.make(it)) }
    }

    @Test
    fun `prvi izvoz ide od pocetka dana prije zadanog broja dana`() {
        val start = HealthImportWindow.start(30, base, ZoneOffset.UTC)
        val startOfDay = base.atZone(ZoneOffset.UTC).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant()
        assertEquals(startOfDay.minusSeconds(30 * 86_400L), start)
    }
}

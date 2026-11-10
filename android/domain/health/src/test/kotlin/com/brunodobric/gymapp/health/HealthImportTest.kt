package com.brunodobric.gymapp.health

import com.brunodobric.gymapp.model.BodyMeasurementKind
import java.io.File
import java.nio.file.Files
import java.time.Instant
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/HealthSyncTests (uvoz treninga i mjerenja iz Zdravlja).
class HealthImportTest {
    private val start: Instant = Instant.ofEpochSecond(1_800_000_000)
    private val own = "com.brunodobric.gymapp"
    private val name: (HealthCardioActivity) -> String = { it.name.lowercase() }

    private fun record(
        id: String,
        activity: HealthCardioActivity? = HealthCardioActivity.RUNNING,
        packageName: String = "com.sec.android.app.shealth",
        minutes: Long = 30,
    ) = HealthWorkoutRecord(
        id, activity, start, start.plusSeconds(minutes * 60), packageName,
        activeEnergyKilocalories = 300.0, distanceMeters = 0.0, averageHeartRate = 150.0,
    )

    @Test
    fun `uvoze se kardio treninzi drugih aplikacija bez duplikata`() {
        val records = listOf(
            record("a"),
            record("snaga", activity = null),
            record("moj", packageName = own),
            record("prazan", minutes = 0),
        )
        val (first, count) = HealthImporter.importWorkouts(HealthLocalData(), records, own, name)
        assertEquals(1, count)
        val workout = first.workouts.single()
        assertEquals("running", workout.name)
        assertEquals(HealthImporter.localId("a"), workout.id)
        assertEquals(300.0, workout.activeEnergyKilocalories)
        assertNull(workout.distanceMeters)

        val (second, again) = HealthImporter.importWorkouts(first, records, own, name)
        assertEquals(0, again)
        assertEquals(first, second)
    }

    @Test
    fun `uvoze se tezina i visina, a vlastiti zapisi i druge mjere ne`() {
        val samples = listOf(
            HealthBodySample("w", BodyMeasurementKind.WEIGHT, 80.0, start, "com.fitbit"),
            HealthBodySample("h", BodyMeasurementKind.HEIGHT, 180.0, start, "com.fitbit"),
            HealthBodySample("moj", BodyMeasurementKind.WEIGHT, 79.0, start, own),
            HealthBodySample("struk", BodyMeasurementKind.WAIST, 85.0, start, "com.fitbit"),
            HealthBodySample("nula", BodyMeasurementKind.WEIGHT, 0.0, start, "com.fitbit"),
        )
        val (local, count) = HealthImporter.importBodySamples(HealthLocalData(), samples, own)
        assertEquals(2, count)
        assertEquals(listOf("w", "h"), local.measurements.map { it.recordId }.sortedDescending())
        assertEquals(0, HealthImporter.importBodySamples(local, samples, own).second)
    }

    @Test
    fun `obrisan zapis se ne vraca ponovnim citanjem, a baza se cita kako je spremljena`() {
        val file = File(Files.createTempDirectory("health").toFile(), "local.json")
        val store = HealthLocalFile(file)
        store.replace(HealthImporter.importWorkouts(store.data, listOf(record("a"), record("b")), own, name).first)
        store.replace(
            HealthImporter.importBodySamples(
                store.data, listOf(HealthBodySample("w", BodyMeasurementKind.WEIGHT, 80.0, start, "com.fitbit")), own,
            ).first,
        )
        store.deleteWorkout(HealthImporter.localId("a"))
        assertEquals(listOf("b"), store.workouts.map { it.recordId })

        val reopened = HealthLocalFile(file)
        assertEquals(store.data, reopened.data)
        assertTrue("a" in HealthImporter.knownRecordIds(reopened.data))
        assertEquals(0, HealthImporter.importWorkouts(reopened.data, listOf(record("a")), own, name).second)

        reopened.clear()
        assertTrue(HealthLocalFile(file).workouts.isEmpty())
        assertEquals(HealthLocalData(), HealthLocalData.decode("nije json"))
    }
}

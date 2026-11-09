package com.brunodobric.gymapp.backup

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.ExerciseKind
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.model.AccentChoice
import com.brunodobric.gymapp.model.AppTheme
import com.brunodobric.gymapp.model.BodyMeasurement
import com.brunodobric.gymapp.model.BodyMeasurementKind
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.CycleOverride
import com.brunodobric.gymapp.model.CycleOverrideKind
import com.brunodobric.gymapp.model.DashboardCard
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.InMemoryPersistence
import com.brunodobric.gymapp.model.MeasurementSource
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.ScheduleItem
import com.brunodobric.gymapp.model.ScheduleItemKind
import com.brunodobric.gymapp.model.Session
import com.brunodobric.gymapp.model.SessionExercise
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.SetLog
import com.brunodobric.gymapp.model.TemplateExercise
import com.brunodobric.gymapp.model.TemplateSet
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.model.WorkoutTemplate
import com.brunodobric.gymapp.units.WeightUnit
import java.time.Instant
import java.util.UUID
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

// Port GymKit/Tests/BackupTests/BackupTests.swift.

private val start: Instant = Instant.ofEpochSecond(1_800_000_000)
private val exportTime: Instant = Instant.ofEpochSecond(1_810_000_000)
private val healthSample: UUID = UUID.fromString("6F1C2B9E-0000-4000-8000-00000000BEEF")

private fun newStore() = GymStore(InMemoryPersistence())

/** Po jedan zapis svake vrste, s neobičnim vrijednostima (zarez, navodnici, novi redak, nedostajuća polja). */
private fun GymStore.fillSample(): Session {
    val settings = settings()
    settings.weightUnit = WeightUnit.POUNDS
    settings.defaultRestSeconds = 120
    settings.goal = TrainingGoal.STRENGTH
    settings.experience = ExperienceLevel.INTERMEDIATE
    settings.equipment = listOf(Equipment.BARBELL, Equipment.DUMBBELL)
    settings.trainingDaysPerWeek = 4
    settings.onboardingCompleted = true
    settings.wantsHealthKit = true
    settings.notificationsEnabled = false
    settings.bodyMapFemale = true
    settings.restNotificationEnabled = false
    settings.startsWatchWorkout = false
    settings.liveActivityFollowsApp = false
    settings.liveActivityTheme = AppTheme.LIGHT
    settings.liveActivityAccent = AccentChoice.PINK
    settings.availablePlatesKg = listOf(1.25, 2.5, 20.0)

    val custom = insert(CustomExercise("Moja \"vježba\", s zarezom"))
    custom.details = "Prvi red\nDrugi red"
    custom.muscles = listOf(Muscle.CHEST, Muscle.TRICEPS)
    custom.imageFile = "slika.jpg"

    val template = insert(WorkoutTemplate("Push"))
    val templateExercise = template.add(TemplateExercise(0, ExerciseRef.catalog("bench", "Potisak s klupe")))
    templateExercise.restSeconds = 150
    templateExercise.notes = "Pauza na prsima"
    templateExercise.supersetGroupId = UUID.randomUUID()
    templateExercise.add(TemplateSet(0, targetWeightKg = 80.0, targetReps = 5))

    val schedule = insert(Schedule("Tjedni"))
    schedule.cycleCount = 4
    schedule.weekdays = listOf(2, 4, 6)
    schedule.reminderMinutes = 18 * 60
    schedule.isActive = true
    schedule.currentPosition = 1
    val workoutItem = schedule.add(ScheduleItem(0, ScheduleItemKind.WORKOUT, template.id))
    schedule.add(ScheduleItem(1, ScheduleItemKind.REST_DAY))
    val change = insert(CycleOverride(schedule.id, 1, workoutItem.id, CycleOverrideKind.REPLACE_EXERCISE))
    change.targetExerciseKey = "c:bench"
    change.replacement = ExerciseRef.catalog("incline", "Kosi potisak")
    change.replacementInputType = ExerciseInputType.WEIGHT_REPS

    val session = insert(Session("Push, \"A\"", startedAt = start))
    session.state = SessionState.FINISHED
    session.endedAt = start.plusSeconds(3600)
    session.notes = "Dobar trening,\nlagani kraj"
    session.averageHeartRate = 131.5
    session.templateId = template.id
    session.lastActivityAt = start.plusSeconds(3600)
    val benchEntry = session.add(SessionExercise(0, ExerciseRef.catalog("bench", "Potisak s klupe")))
    benchEntry.restSeconds = 120
    listOf(8, 6).forEachIndexed { index, reps ->
        val set = benchEntry.add(SetLog(index, if (index == 0) SetKind.WARM_UP else SetKind.WORKING))
        set.weightKg = 60 + index * 22.5
        set.reps = reps
        set.rpe = 8.5
        set.completedAt = start.plusSeconds(600L + index * 180)
    }
    val cardio = session.add(SessionExercise(1, ExerciseRef.custom(custom.id, custom.name), ExerciseInputType.DURATION_DISTANCE))
    val run = cardio.add(SetLog(0))
    run.durationSeconds = 1500
    run.distanceMeters = 5000.5
    run.completedAt = start.plusSeconds(3000)
    session.add(SessionExercise(2, ExerciseRef.catalog("plank", "Plank")))

    insert(BodyMeasurement(BodyMeasurementKind.WEIGHT, 82.4, start))
    val custom2 = insert(BodyMeasurement(BodyMeasurementKind.CUSTOM, 36.5, start.plusSeconds(86_400)))
    custom2.customName = "Bicepsi, lijevi"
    custom2.source = MeasurementSource.HEALTH_KIT
    custom2.healthKitSampleId = healthSample
    insert(DashboardCard("plateCalculator", 0))

    // Ne smiju u izvoz.
    insert(Session("U tijeku", startedAt = start.plusSeconds(7200)))
    insert(Session("Odbačen", startedAt = start.plusSeconds(9000))).state = SessionState.DISCARDED

    save()
    return session
}

private val image = byteArrayOf(1, 2, 3, 4)
private fun images(exercise: CustomExercise) = if (exercise.imageFile != null) image else null

class BackupTest {

    @Nested
    inner class JsonBackupTests {
        @Test
        fun `export pa import na cistoj bazi vraca identicne podatke`() {
            val source = newStore()
            source.fillSample()
            source.templates.first().exercises.first().sets.first().targetRepsMax = 8
            source.customExercises.first().kind = ExerciseKind.STRETCHING
            source.settings().compoundRestSeconds = 210
            source.save()
            val first = JsonBackup.export(source, exportTime, ::images)

            val target = newStore()
            val saved = mutableMapOf<UUID, ByteArray>()
            val result = JsonBackup.import(first, target) { id, bytes -> saved[id] = bytes; "slika.jpg" }
            val second = JsonBackup.export(target, exportTime, ::images)

            assertEquals(first, second)
            assertEquals(BackupImportResult(8, 0), result)
            assertEquals(ExerciseKind.STRETCHING, target.customExercises.first().kind)
            assertContentEquals(image, saved[target.customExercises.first().id])
            val session = target.sessions.first()
            assertEquals(3, session.orderedExercises.size)
            assertEquals(2, session.orderedExercises[0].orderedSets.size)
            val templateSet = target.templates.first().exercises.first().sets.first()
            assertTrue(templateSet.targetReps == 5 && templateSet.targetRepsMax == 8)
            val restored = target.settings()
            assertEquals(WeightUnit.POUNDS, restored.weightUnit)
            assertTrue(restored.bodyMapFemale)
            assertFalse(restored.restNotificationEnabled)
            assertFalse(restored.startsWatchWorkout)
            assertFalse(restored.liveActivityFollowsApp)
            assertEquals(210, restored.compoundRestSeconds)
            assertEquals(AppTheme.LIGHT, restored.liveActivityTheme)
            assertEquals(AccentChoice.PINK, restored.liveActivityAccent)
            assertTrue(target.bodyMeasurements.any { it.healthKitSampleId == healthSample })
            assertEquals(1, target.settingsRecords.size)
        }

        @Test
        fun `zapis je kao na iOS-u - datumi od 2001, kljucevi abecedno, bez null polja`() {
            val source = newStore()
            source.fillSample()
            val text = JsonBackup.export(source, exportTime)
            assertTrue("\"exportedAt\" : 831692800" in text)
            assertTrue("\"format\" : \"gymapp-backup\"" in text)
            assertTrue("\"version\" : 1" in text)
            assertTrue("\"weightKg\" : 82.5" in text && "\"weightKg\" : 60\n" in text)
            assertFalse("null" in text)
            assertTrue(text.indexOf("\"customExercises\"") < text.indexOf("\"dashboardCards\""))
            // UUID velikim slovima.
            assertTrue(source.sessions.first().id.uppercaseString in text)
        }

        @Test
        fun `cita kopiju napravljenu na iPhoneu`() {
            val id = "0C8E1B1A-2B6C-4C1E-9E3A-6C4B8D2E1F00"
            val json = """
                {"format":"gymapp-backup","version":1,"exportedAt":821692800.5,"customExercises":[],"templates":[],
                 "schedules":[],"cycleOverrides":[],"measurements":[],"dashboardCards":[],
                 "sessions":[{"id":"$id","name":"Noge","kindRaw":"strength","startedAt":821692800,
                   "controllingDeviceRaw":"phone","notes":"","isImportedFromWorkoutsApp":false,
                   "lastActivityAt":821696400.25,"exercises":[]}]}
            """.trimIndent()
            val store = newStore()
            assertEquals(BackupImportResult(1, 0), JsonBackup.import(json, store))
            val session = store.sessions.single()
            assertEquals(UUID.fromString(id), session.id)
            assertEquals(Instant.parse("2027-01-15T08:00:00Z"), session.startedAt)
            assertEquals(Instant.parse("2027-01-15T09:00:00.250Z"), session.lastActivityAt)
            assertEquals(SessionState.FINISHED, session.state)
        }

        @Test
        fun `trening u tijeku i odbaceni se ne izvoze`() {
            val source = newStore()
            source.fillSample()
            val target = newStore()
            JsonBackup.import(JsonBackup.export(source, exportTime), target)
            assertEquals(listOf("Push, \"A\""), target.sessions.map { it.name })
        }

        @Test
        fun `ponovni uvoz ne udvostrucuje podatke`() {
            val source = newStore()
            source.fillSample()
            val again = JsonBackup.import(JsonBackup.export(source, exportTime), source)
            assertEquals(BackupImportResult(0, 8), again)
            assertEquals(3, source.sessions.size)
            assertEquals(3, source.setLogs.size)
            assertEquals(1, source.settingsRecords.size)
        }

        @Test
        fun `tuda ili novija datoteka se odbija`() {
            val store = newStore()
            assertThrows<BackupException.UnsupportedFormat> { JsonBackup.import("{}", store) }
            assertThrows<BackupException.UnsupportedFormat> { JsonBackup.import("nije json", store) }
            val newer = JsonBackup.export(newStore(), exportTime).replace("\"version\" : 1", "\"version\" : 9")
            assertEquals(BackupException.NewerVersion(9), assertThrows<BackupException.NewerVersion> { JsonBackup.import(newer, store) })
        }

        @Test
        fun `trening i tezina iz Zdravlja iz kopije s iPhonea se preskacu`() {
            val source = newStore()
            val session = source.insert(Session("Bicikl", WorkoutKind.CARDIO, start))
            session.state = SessionState.FINISHED
            session.endedAt = start.plusSeconds(1800)
            session.isImportedFromWorkoutsApp = true
            source.insert(BodyMeasurement(BodyMeasurementKind.WEIGHT, 80.0, start, MeasurementSource.HEALTH_KIT))
            source.insert(BodyMeasurement(BodyMeasurementKind.WEIGHT, 81.0, start))
            source.save()

            val target = newStore()
            val result = JsonBackup.import(JsonBackup.export(source, exportTime), target)
            assertEquals(BackupImportResult(1, 2), result)
            assertTrue(target.sessions.isEmpty())
            assertEquals(listOf(81.0), target.bodyMeasurements.map { it.value })
        }

        @Test
        fun `kopija sa starim poljima (kardio plan, plan sa sata) i dalje se uvozi`() {
            val source = newStore()
            source.insert(WorkoutTemplate("Push"))
            source.save()
            val json = JsonBackup.export(source, exportTime)
                .replace("\"name\" : \"Push\"", "\"cardioPlanRaw\" : \"{}\", \"name\" : \"Push\"")
            assertTrue("cardioPlanRaw" in json)
            val target = newStore()
            JsonBackup.import(json, target)
            assertEquals(listOf("Push"), target.templates.map { it.name })
        }
    }

    @Nested
    inner class CsvBackupTests {
        @Test
        fun `povijest - export pa import vraca identican CSV`() {
            val source = newStore()
            source.fillSample()
            val first = CsvBackup.exportHistory(source)

            val target = newStore()
            val result = CsvBackup.importHistory(first, target)
            val second = CsvBackup.exportHistory(target)

            assertEquals(first, second)
            assertEquals(BackupImportResult(1, 0), result)
            val session = target.sessions.first()
            assertEquals("Push, \"A\"", session.name)
            assertEquals("Dobar trening,\nlagani kraj", session.notes)
            assertEquals(SessionState.FINISHED, session.state)
            assertEquals(listOf(2, 1, 0), session.orderedExercises.map { it.orderedSets.size })
            assertNotNull(session.orderedExercises[1].exerciseCustomId)
            assertEquals(82.5, session.orderedExercises[0].orderedSets[1].weightKg)
        }

        @Test
        fun `povijest - redak je kao na iOS-u`() {
            val source = newStore()
            val session = source.fillSample()
            val text = CsvBackup.exportHistory(source)
            assertTrue(text.startsWith(CsvBackup.historyColumns.joinToString(",") + "\n"))
            val id = session.id.uppercaseString
            val head = "$id,\"Push, \"\"A\"\"\",strength,2027-01-15T08:00:00.000Z,2027-01-15T09:00:00.000Z,\"Dobar trening,\nlagani kraj\","
            assertTrue("\n${head}0,c:bench,Potisak s klupe,weightReps,,120,1,working,82.5,6,,,,8.5,2027-01-15T08:13:00.000Z\n" in text)
            assertTrue("\n${head}2,c:plank,Plank,weightReps,,,,,,,,,,,\n" in text)
        }

        @Test
        fun `povijest - ponovni uvoz preskace postojece treninge`() {
            val store = newStore()
            store.fillSample()
            val result = CsvBackup.importHistory(CsvBackup.exportHistory(store), store)
            assertEquals(BackupImportResult(0, 1), result)
            assertEquals(3, store.sessions.size)
        }

        @Test
        fun `povijest - neispravan redak odbija cijeli uvoz`() {
            val source = newStore()
            source.fillSample()
            val header = CsvBackup.exportHistory(source).lines()[0]
            assertEquals(BackupException.InvalidCsv(1), assertThrows<BackupException.InvalidCsv> { CsvBackup.importHistory("a,b,c\n1,2,3\n", newStore()) })
            val target = newStore()
            val broken = header + "\n" + UUID.randomUUID().uppercaseString + ",Ime,strength,nije datum" + ",".repeat(17) + "\n"
            assertEquals(BackupException.InvalidCsv(2), assertThrows<BackupException.InvalidCsv> { CsvBackup.importHistory(broken, target) })
            assertTrue(target.sessions.isEmpty())

            // Neispravan broj u retku serije, nakon ispravnog treninga: ništa se ne sprema.
            val row = listOf(
                UUID.randomUUID().uppercaseString, "A", "strength", "2027-01-15T08:00:00.000Z", "", "", "0", "c:bench", "Bench",
                "weightReps", "", "", "0", "working", "abc", "", "", "", "", "", "",
            ).joinToString(",")
            assertEquals(BackupException.InvalidCsv(2), assertThrows<BackupException.InvalidCsv> { CsvBackup.importHistory("$header\n$row\n", target) })
            assertTrue(target.sessions.isEmpty())
            assertTrue(target.sessionExercises.isEmpty())
        }

        @Test
        fun `mjerenja - export pa import vraca identican CSV`() {
            val source = newStore()
            source.fillSample()
            val first = CsvBackup.exportBody(source)
            val target = newStore()
            assertEquals(BackupImportResult(2, 0), CsvBackup.importBody(first, target))
            assertEquals(first, CsvBackup.exportBody(target))
            val custom = target.bodyMeasurements.first { it.kind == BodyMeasurementKind.CUSTOM }
            assertTrue(custom.customName == "Bicepsi, lijevi" && custom.source == MeasurementSource.HEALTH_KIT)
        }

        @Test
        fun `importAny prepoznaje vrstu CSV-a po zaglavlju`() {
            val source = newStore()
            source.fillSample()
            val target = newStore()
            assertEquals(BackupImportResult(1, 0), CsvBackup.importAny(CsvBackup.exportHistory(source), target))
            assertEquals(BackupImportResult(2, 0), CsvBackup.importAny(CsvBackup.exportBody(source), target))
            assertThrows<BackupException.InvalidCsv> { CsvBackup.importAny("x,y\n1,2\n", target) }
        }

        @Test
        fun `CSV parser - navodnici, zarezi, novi redovi i CRLF`() {
            val rows = Csv.parse("a,\"b,\"\"c\"\"\nd\",e\r\n1,,3\r\n")
            assertEquals(listOf(listOf("a", "b,\"c\"\nd", "e"), listOf("1", "", "3")), rows)
            assertTrue(Csv.parse("").isEmpty())
            assertEquals("x,\"y,z\",\"q\"\"r\"", Csv.line(listOf("x", "y,z", "q\"r")))
        }
    }

    @Nested
    inner class DataResetTests {
        @Test
        fun `brise sve zapise i djecu, a postavke se vracaju na zadane`() {
            val store = newStore()
            store.fillSample()
            DataReset.deleteAll(store)

            assertTrue(store.sessions.isEmpty() && store.sessionExercises.isEmpty() && store.setLogs.isEmpty())
            assertTrue(store.templates.isEmpty() && store.templateExercises.isEmpty())
            assertTrue(store.schedules.isEmpty() && store.scheduleItems.isEmpty() && store.cycleOverrides.isEmpty())
            assertTrue(store.customExercises.isEmpty() && store.bodyMeasurements.isEmpty() && store.dashboardCards.isEmpty())
            val settings = store.settings()
            assertTrue(settings.weightUnit == WeightUnit.KILOGRAMS && !settings.onboardingCompleted)
        }
    }
}

package com.brunodobric.gymapp.stats

import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.catalog.Muscle
import com.brunodobric.gymapp.catalog.uppercaseString
import com.brunodobric.gymapp.model.CustomExercise
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.SessionState
import com.brunodobric.gymapp.model.SetKind
import com.brunodobric.gymapp.model.WorkoutKind
import com.brunodobric.gymapp.training.PRKind
import com.brunodobric.gymapp.training.SetMetrics
import com.brunodobric.gymapp.training.SetValues
import com.brunodobric.gymapp.training.WorkoutEngine
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Port GymKit/Tests/StatsTests/StatsTests.swift (povijest, statistika, regije, usporedba, skala).
class StatsTest {

    @Nested
    inner class HistoryTests {
        @Test
        fun `filter po vrsti i sortiranje po datumu`() {
            val store = newStore()
            val lifts = listOf(Lift(bench, listOf(Work(80.0, 5))))
            val old = store.addSession(base, lifts = lifts)
            val new = store.addSession(base.plusDays(1.0), WorkoutKind.CARDIO, lifts)
            val history = HistoryQueries(store)

            assertEquals(listOf(new.id, old.id), history.sessions().map { it.id })
            assertEquals(listOf(old.id, new.id), history.sessions(HistoryFilter(sort = HistorySort.OLDEST_FIRST)).map { it.id })
            assertEquals(listOf(new.id), history.sessions(HistoryFilter(setOf(WorkoutKind.CARDIO))).map { it.id })
        }

        @Test
        fun `ispod kalendara su treninzi prikazanog mjeseca, a s odabranim danom samo tog dana`() {
            val store = newStore()
            // 15. 1., 31. 1. u 23:00 i 1. 2. 2027.
            val jan15 = store.addSession(base, lifts = emptyList())
            val jan31 = store.addSession(base.plusSeconds(16 * DAY + 15 * 3600), WorkoutKind.CARDIO, emptyList())
            val feb1 = store.addSession(base.plusSeconds(17 * DAY), lifts = emptyList())
            val all = listOf(jan15, jan31, feb1)
            val filter = HistoryFilter()

            assertEquals(listOf(jan31.id, jan15.id), filter.apply(all, base, null, utcMonday).map { it.id })
            assertEquals(listOf(feb1.id), filter.apply(all, feb1.startedAt, null, utcMonday).map { it.id })
            assertEquals(listOf(jan31.id), filter.apply(all, base, jan31.startedAt, utcMonday).map { it.id })
            assertTrue(filter.apply(all, base, base.plusDays(1.0), utcMonday).isEmpty())
            assertEquals(listOf(jan15.id), HistoryFilter(setOf(WorkoutKind.STRENGTH)).apply(all, base, null, utcMonday).map { it.id })
        }

        @Test
        fun `treninzi koji nisu završeni nisu u povijesti`() {
            val store = newStore()
            val session = store.addSession(base, lifts = emptyList())
            session.state = SessionState.ACTIVE
            store.save()
            assertTrue(HistoryQueries(store).sessions().isEmpty())
        }

        @Test
        fun `dani s treningom za kalendar i popis treninga za dan`() {
            val store = newStore()
            val lifts = listOf(Lift(bench, listOf(Work(80.0, 5))))
            store.addSession(base, lifts = lifts)
            store.addSession(base.plusSeconds(3 * 3600), lifts = lifts)
            store.addSession(base.plusDays(2.0), lifts = lifts)
            val history = HistoryQueries(store)

            val days = history.workoutDays(utcMonday.monthInterval(base), utcMonday)
            assertEquals(setOf(utcMonday.startOfDay(base), utcMonday.startOfDay(base.plusDays(2.0))), days)
            assertEquals(2, history.sessions(base, utcMonday).size)
            assertTrue(history.sessions(base.plusDays(1.0), utcMonday).isEmpty())
        }

        @Test
        fun `brisanje treninga briše i njegove vježbe i serije`() {
            val store = newStore()
            val session = store.addSession(base, lifts = listOf(Lift(bench, listOf(Work(80.0, 5)))))
            HistoryQueries(store).delete(session)
            assertTrue(store.sessions.isEmpty())
            assertTrue(store.sessionExercises.isEmpty())
            assertTrue(store.setLogs.isEmpty())
            store.rollback()
            assertTrue(store.sessions.isEmpty())
        }
    }

    @Nested
    inner class StatisticsTests {
        @Test
        fun `napredak vježbe - najbolja težina, 1RM i volumen bez zagrijavanja`() {
            val store = newStore()
            store.addSession(base, lifts = listOf(Lift(bench, listOf(Work(40.0, 10, SetKind.WARM_UP), Work(100.0, 5), Work(90.0, 8)))))
            store.addSession(base.plusDays(7.0), lifts = listOf(Lift(bench, listOf(Work(105.0, 5)))))
            store.addSession(base.plusDays(1.0), lifts = listOf(Lift(squat, listOf(Work(150.0, 5)))))

            val points = StatisticsEngine(store).progress(bench)
            assertEquals(2, points.size)
            assertTrue(points[0].date < points[1].date)
            assertEquals(100.0, points[0].bestWeightKg)
            assertEquals(100.0 * 5 + 90 * 8, points[0].volumeKg)
            // Epley: 100 × (1 + 5/30) = 116,67; 90 × (1 + 8/30) = 114.
            assertTrue(abs((points[0].estimatedOneRepMaxKg ?: 0.0) - 116.6667) < 0.01)
            val brzycki = StatisticsEngine(store).progress(bench, SetMetrics.OneRepMaxFormula.BRZYCKI)
            assertTrue(abs((brzycki[0].estimatedOneRepMaxKg ?: 0.0) - 112.5) < 0.01)
        }

        @Test
        fun `tjedni volumen po mišiću, mjeseci i vrijeme izvan raspona`() {
            val store = newStore()
            // Tjedan od ponedjeljka 11. 1.: dva treninga prsa i noge; prethodni tjedan jedan; stariji od raspona.
            store.addSession(
                base,
                lifts = listOf(
                    Lift(bench, listOf(Work(100.0, 5), Work(20.0, 10, SetKind.WARM_UP))),
                    Lift(squat, listOf(Work(120.0, 5))),
                ),
            )
            store.addSession(base.plusDays(1.0), lifts = listOf(Lift(bench, listOf(Work(100.0, 4)))))
            store.addSession(base.plusDays(-7.0), lifts = listOf(Lift(bench, listOf(Work(90.0, 5)))))
            store.addSession(base.plusDays(-60.0), lifts = listOf(Lift(bench, listOf(Work(90.0, 5)))))

            val engine = StatisticsEngine(store)
            val weeks = engine.volumeBuckets(BucketSize.WEEK, 2, base, utcMonday, infoProvider)
            assertEquals(2, weeks.size)
            assertEquals(MuscleLoad(450.0, 1.0), weeks[0].loads["chest"])
            assertEquals(MuscleLoad(900.0, 2.0), weeks[1].loads["chest"])
            assertEquals(MuscleLoad(600.0, 1.0), weeks[1].loads["quads"])
            assertEquals(1500.0, weeks[1].totalVolumeKg)
            assertEquals(3, weeks[1].totalSets)
            // Pomoćne regije dobivaju pola serije, ali ne i tonažu.
            assertEquals(MuscleLoad(0.0, 1.0), weeks[1].loads["triceps"])
            assertEquals(MuscleLoad(0.0, 0.5), weeks[1].loads["glutes"])

            val months = engine.volumeBuckets(BucketSize.MONTH, 3, base, utcMonday, infoProvider)
            assertEquals(3, months.size)
            assertEquals(3.0, months[2].loads["chest"]?.sets)
            assertEquals(1.0, months[0].loads["chest"]?.sets)
        }

        @Test
        fun `serije s vlastitom težinom broje se u serije, a ne u tonažu`() {
            val store = newStore()
            val session = store.addSession(base, lifts = listOf(Lift(bench, listOf(Work(0.0, 12)))))
            session.orderedExercises.first().inputType = ExerciseInputType.BODYWEIGHT
            store.save()
            val weeks = StatisticsEngine(store).volumeBuckets(BucketSize.WEEK, 1, base, utcMonday, infoProvider)
            assertEquals(MuscleLoad(0.0, 1.0), weeks[0].loads["chest"])
            assertEquals(1, weeks[0].totalSets)
        }

        @Test
        fun `frekvencija po tjednima`() {
            val store = newStore()
            val lifts = listOf(Lift(bench, listOf(Work(80.0, 5))))
            store.addSession(base, lifts = lifts)
            store.addSession(base.plusDays(1.0), lifts = lifts)
            store.addSession(base.plusDays(-7.0), lifts = lifts)
            assertEquals(listOf(0, 1, 2), StatisticsEngine(store).frequency(3, base, utcMonday).map { it.sessions })
        }

        @Test
        fun `rekordi kroz povijest - prva tri izvođenja nisu rekord, kasnija jesu`() {
            val store = newStore()
            listOf(80.0, 80.0, 80.0, 85.0, 82.0).forEachIndexed { index, weight ->
                store.addSession(base.plusDays(index * 7.0), lifts = listOf(Lift(bench, listOf(Work(weight, 5)))))
            }
            val engine = StatisticsEngine(store)
            val entries = engine.personalRecords()
            val weight = entries.filter { it.record.kind == PRKind.MAX_WEIGHT }
            assertEquals(1, weight.size)
            assertEquals(85.0, weight[0].record.value)
            assertEquals(80.0, weight[0].record.previousBest)
            assertEquals("Potisak s klupe", weight[0].exerciseName)
            // Najnoviji prvi.
            assertEquals(entries.map { it.date }.sortedDescending(), entries.map { it.date })
            assertTrue(engine.personalRecords(kinds = emptySet()).isEmpty())
            assertTrue(engine.personalRecords(excluded = setOf(bench.key)).isEmpty())
        }

        @Test
        fun `heatmap - serije tjedno na fiksnoj skali, pomoćne upola, učestalost samo s cijelom serijom`() {
            val store = newStore()
            store.addSession(base, lifts = listOf(Lift(bench, listOf(Work(100.0, 5)))))
            store.addSession(
                base.plusDays(1.0),
                lifts = listOf(Lift(bench, listOf(Work(100.0, 5))), Lift(squat, listOf(Work(100.0, 5)))),
            )
            // Prvi trening je na početku razdoblja, pa je razdoblje kraće od tjedna i prosjek se računa na 1 tjedan.
            val result = StatisticsEngine(store).heatmap(base.plusDays(-1.0), base.plusDays(3.0), infoProvider)
            val chest = assertNotNull(result["chest"])
            assertEquals(2, chest.sessions)
            assertEquals(2.0, chest.sets)
            assertEquals(2.0, chest.weeklySets)
            assertEquals(1000.0, chest.volumeKg)
            assertEquals(1, chest.weeklyLevel)
            assertEquals(0.25, chest.intensity)
            assertEquals(base.plusDays(1.0), chest.lastTrained)
            // Pomoćna regija: dvije polovine serije u dva treninga, ni u jednom cijela serija.
            assertEquals(1.0, result["triceps"]?.sets)
            assertEquals(0, result["triceps"]?.sessions)
            assertEquals(500.0, result["triceps"]?.volumeKg)
            assertEquals(1, result["quads"]?.sessions)
            assertEquals(250.0, result["glutes"]?.volumeKg)
            assertNull(result["lats"])
        }

        @Test
        fun `heatmap - prosjek po tjednima razdoblja i razine skale`() {
            val store = newStore()
            // Stari trening izvan razdoblja: razdoblje od 14 dana računa se cijelo.
            store.addSession(base.plusDays(-60.0), lifts = listOf(Lift(bench, listOf(Work(80.0, 5)))))
            val ten = List(10) { Work(80.0, 8) }
            store.addSession(base.plusDays(-3.0), lifts = listOf(Lift(bench, ten)))
            store.addSession(base.plusDays(-10.0), lifts = listOf(Lift(bench, ten)))
            val result = StatisticsEngine(store).heatmap(base.plusDays(-14.0), base, infoProvider)
            assertTrue(abs((result["chest"]?.weeklySets ?: 0.0) - 10) < 0.001)
            assertEquals(3, result["chest"]?.weeklyLevel)
            assertTrue(abs((result["chest"]?.sessionsPerWeek ?: 0.0) - 1) < 0.001)
            assertEquals(2, result["triceps"]?.weeklyLevel)
        }

        @Test
        fun `trend snage - mjesečni nagib procjene 1RM po regiji, vježba treba barem 4 izvođenja`() {
            val store = newStore()
            for ((offset, weight) in listOf(42.0 to 100.0, 28.0 to 102.5, 14.0 to 105.0, 1.0 to 107.5)) {
                store.addSession(base.plusDays(-offset), lifts = listOf(Lift(bench, listOf(Work(weight, 5), Work(60.0, 20)))))
            }
            store.addSession(base.plusDays(-3.0), lifts = listOf(Lift(squat, listOf(Work(120.0, 5)))))
            val trends = StatisticsEngine(store).strengthTrends(4, base, infoProvider)
            assertEquals(listOf("chest"), trends.map { it.region })
            // Theil–Sen nad ln(1RM): oko +5,4 % mjesečno.
            assertTrue(abs(trends[0].change - 0.0543) < 0.001)
            assertEquals(1, trends[0].exercises)
        }
    }

    @Nested
    inner class ExerciseInfoBuilderTests {
        @Test
        fun `vlastita vježba dobiva regije iz mišića`() {
            val custom = CustomExercise("Moja")
            custom.muscles = listOf(Muscle.CHEST, Muscle.MIDDLE_BACK, Muscle.NECK, Muscle.TRAPS)
            val provider = ExerciseInfoBuilder.provider(null, listOf(custom))
            val info = provider("u:${custom.id.uppercaseString}")
            assertEquals(listOf(Muscle.CHEST, Muscle.MIDDLE_BACK, Muscle.NECK, Muscle.TRAPS), info?.primary)
            assertEquals(listOf("chest", "upperBack", "traps"), info?.primaryRegions)
            assertNull(provider("c:nepoznato"))
        }

        @Test
        fun `glavne regije i regija svakog mišića su poznate`() {
            assertTrue(BodyRegion.all.containsAll(BodyRegion.major))
            for (muscle in Muscle.entries) assertTrue(BodyRegion.region(muscle) in BodyRegion.all)
        }

        @Test
        fun `svaka regija ima boju, bliske regije dijele boju, a nepoznata nema`() {
            for (region in BodyRegion.all) assertNotNull(BodyRegion.colorGroup(region))
            assertEquals(BodyRegion.colorGroup("lats"), BodyRegion.colorGroup("lowerBack"))
            assertEquals(BodyRegion.ColorGroup.LEGS, BodyRegion.colorGroup("quads"))
            assertNotEquals(BodyRegion.colorGroup("chest"), BodyRegion.colorGroup("triceps"))
            assertNull(BodyRegion.colorGroup("neck"))
            // Sve boje se koriste.
            assertEquals(BodyRegion.ColorGroup.entries.size, BodyRegion.all.mapNotNull(BodyRegion::colorGroup).toSet().size)
        }

        @Test
        fun `ključ vježbe se vraća u referencu`() {
            val catalogRef = ExerciseRef.catalog("bench", "A")
            assertEquals(catalogRef, ExerciseRef.fromKey(catalogRef.key, "A"))
            val customRef = ExerciseRef.custom(java.util.UUID.randomUUID(), "B")
            assertEquals(customRef, ExerciseRef.fromKey(customRef.key, "B"))
            assertNull(ExerciseRef.fromKey("x:1", "C"))
            assertNull(ExerciseRef.fromKey("u:nije-uuid", "C"))
            assertNull(ExerciseRef.fromKey("c:", "C"))
        }
    }

    @Nested
    inner class BodyMapTests {
        @Test
        fun `čita M, L, C i Z`() {
            assertEquals(
                listOf(
                    PathCommand.Move(1.5, 2.0), PathCommand.Line(3.0, -4.0),
                    PathCommand.Curve(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), PathCommand.Close,
                ),
                SVGPathParser.parse("M1.5 2L3-4C1 2 3 4 5 6Z"),
            )
        }

        @Test
        fun `ponavlja argumente bez naredbe`() {
            val commands = SVGPathParser.parse("M0 0 1 1 2 2C1 1 2 2 3 3 4 4 5 5 6 6")
            assertEquals(5, commands.size)
            assertEquals(PathCommand.Line(1.0, 1.0), commands[1])
            assertEquals(PathCommand.Curve(4.0, 4.0, 5.0, 5.0, 6.0, 6.0), commands[4])
        }

        @Test
        fun `susjedni decimalni brojevi i više putanja`() {
            val commands = SVGPathParser.parse("M1.5.5L2 2ZM5 5L6 6Z")
            assertEquals(PathCommand.Move(1.5, 0.5), commands.first())
            assertEquals(2, commands.count { it == PathCommand.Close })
        }

        @Test
        fun `staje na nepodržanoj ili nepotpunoj naredbi`() {
            assertEquals(listOf<PathCommand>(PathCommand.Move(0.0, 0.0)), SVGPathParser.parse("M0 0A1 1 0 0 1 2 2"))
            assertEquals(listOf<PathCommand>(PathCommand.Move(0.0, 0.0)), SVGPathParser.parse("M0 0L5"))
            assertTrue(SVGPathParser.parse("").isEmpty())
        }

        @Test
        fun `čita crtež i grupe mišića`() {
            val json = """
                {"male-front":{"viewBox":[0,0,10,20],"bounds":[1,2,8,16],"outline":[{"id":"BODY","d":"M0 0Z"}],
                "muscles":[{"id":"A","group":"QUADS","d":"M0 0Z"}]}}
            """.trimIndent()
            val diagram = assertNotNull(BodyMap.decode(json)[BodyMap.key(female = false, back = false)])
            assertEquals("QUADS", diagram.muscles.first().group)
            assertNull(diagram.outline.first().group)
            assertEquals(listOf(1.0, 2.0, 8.0, 16.0), diagram.bounds)
        }

        @Test
        fun `svaka grupa crteža ima poznatu regiju`() {
            val groups = listOf(
                "CHEST", "SHOULDERS_FRONT", "SHOULDERS_SIDE", "SHOULDERS_REAR", "BICEPS", "TRICEPS", "FOREARMS", "CORE",
                "OBLIQUES", "QUADS", "HAMSTRINGS", "ADDUCTORS", "ABDUCTORS", "TRAPEZIUS", "RHOMBOIDS", "LATS",
                "BACK_LOWER", "GLUTES", "CALVES",
            )
            for (group in groups) assertTrue(BodyRegion.regionForBodyMapGroup(group) in BodyRegion.all)
            assertNull(BodyRegion.regionForBodyMapGroup("HIP_FLEXORS"))
        }
    }

    @Nested
    inner class SessionRegionsTests {
        @Test
        fun `boja jednog treninga je na fiksnoj skali, pomoćne serije upola`() {
            val store = newStore()
            val session = store.addSession(base, lifts = listOf(Lift(bench, List(6) { Work(80.0, 5) })))
            val regions = SessionRegions.worked(session, infoProvider)
            assertEquals(0.75, regions["chest"]?.intensity)
            assertEquals(0.5, regions["triceps"]?.intensity)
            assertEquals(3.0, regions["triceps"]?.sets)
            assertNull(regions["quads"])
        }

        @Test
        fun `lagan trening ostaje svijetao - boja ne ovisi o najopterećenijoj regiji`() {
            val store = newStore()
            val session = store.addSession(
                base,
                lifts = listOf(Lift(bench, List(2) { Work(80.0, 5) }), Lift(squat, List(4) { Work(100.0, 5) })),
            )
            val sets = SessionRegions.sets(session, infoProvider)
            assertEquals(listOf("quads", "chest", "glutes", "triceps"), sets.map { it.region })
            assertEquals(RegionSets("quads", primarySets = 4, volumeKg = 2000.0), sets.first())
            assertEquals(RegionSets("triceps", secondarySets = 2, volumeKg = 400.0), sets.last())

            val heatmap = SessionRegions.heatmap(sets)
            assertEquals(0.5, heatmap["quads"]?.intensity)
            assertEquals(0.25, heatmap["chest"]?.intensity)
            assertEquals(0.25, heatmap["glutes"]?.intensity)
            assertEquals(0.25, heatmap["triceps"]?.intensity)
        }

        @Test
        fun `popis ispod mape - glavni mišići pa oni koji samo pomažu, redoslijed ostaje`() {
            val sets = listOf(
                RegionSets("chest", primarySets = 9),
                RegionSets("triceps", primarySets = 4, secondarySets = 5),
                RegionSets("abs", secondarySets = 3),
                RegionSets("shoulders", primarySets = 3, secondarySets = 4),
                RegionSets("traps", secondarySets = 1),
            )
            val (primary, assisting) = SessionRegions.split(sets)
            assertEquals(listOf("chest", "triceps", "shoulders"), primary.map { it.region })
            assertEquals(listOf("abs", "traps"), assisting.map { it.region })
            assertTrue(SessionRegions.split(emptyList()).first.isEmpty())
        }

        @Test
        fun `serija s RPE ispod 6 se ne broji, s RPE 6 ili bez RPE-a se broji`() {
            val store = newStore()
            val session = store.addSession(
                base,
                lifts = listOf(Lift(bench, listOf(Work(40.0, 10, rpe = 5.0), Work(60.0, 8, rpe = 6.0), Work(70.0, 6)))),
            )
            assertEquals(2, SessionRegions.sets(session, infoProvider).first { it.region == "chest" }.primarySets)
        }

        @Test
        fun `serije iste regije iz više vježbi se zbrajaju, glavne i pomoćne odvojeno`() {
            val store = newStore()
            val session = store.addSession(
                base,
                lifts = listOf(Lift(bench, List(2) { Work(80.0, 5) }), Lift(squat, listOf(Work(100.0, 5)))),
            )
            val sets = SessionRegions.sets(session) { key ->
                if (key == "c:squat") ExerciseInfo(primaryRegions = listOf("triceps"), secondaryRegions = listOf("chest", "triceps"))
                else infoProvider(key)
            }
            assertEquals(2, sets.first { it.region == "chest" }.primarySets)
            assertEquals(1, sets.first { it.region == "chest" }.secondarySets)
            // Regija koja je u vježbi i glavna i pomoćna broji se samo kao glavna.
            assertEquals(1, sets.first { it.region == "triceps" }.primarySets)
            assertEquals(2, sets.first { it.region == "triceps" }.secondarySets)
        }

        @Test
        fun `warm-up i nezavršene vježbe se ne broje, a trening bez serija nema heatmap`() {
            val store = newStore()
            val session = store.addSession(base, lifts = listOf(Lift(squat, listOf(Work(100.0, 5, SetKind.WARM_UP)))))
            assertTrue(SessionRegions.sets(session, infoProvider).isEmpty())
            assertTrue(SessionRegions.worked(session, infoProvider).isEmpty())
        }
    }

    @Nested
    inner class VolumeComparisonTests {
        @Test
        fun `zadnje razdoblje uspoređuje se s prethodnim u serijama, regije od najviše serija`() {
            val buckets = listOf(
                VolumeBucket(base.plusDays(-14.0), linkedMapOf("chest" to MuscleLoad(5000.0, 9.0)), totalSets = 9),
                VolumeBucket(
                    base.plusDays(-7.0),
                    linkedMapOf("chest" to MuscleLoad(1000.0, 3.0), "quads" to MuscleLoad(3000.0, 5.0)),
                    totalSets = 8,
                ),
                VolumeBucket(base, linkedMapOf("chest" to MuscleLoad(1500.0, 4.0), "biceps" to MuscleLoad(300.0, 2.0)), totalSets = 6),
            )
            val comparison = assertNotNull(VolumeComparison.of(buckets))
            assertEquals(base, comparison.currentStart)
            assertEquals(base.plusDays(-7.0), comparison.previousStart)
            assertEquals(6, comparison.currentSets)
            assertEquals(8, comparison.previousSets)
            assertEquals(-0.25, comparison.change)
            assertEquals(listOf("quads", "chest", "biceps"), comparison.muscles.map { it.region })
            assertEquals(MuscleComparison("quads", 0.0, 5.0), comparison.muscles[0])
            assertEquals(MuscleComparison("biceps", 2.0, 0.0), comparison.muscles[2])
        }

        @Test
        fun `bez prethodnih serija nema postotka, a s jednim razdobljem nema usporedbe`() {
            assertNull(VolumeComparison.of(listOf(VolumeBucket(base))))
            val comparison = VolumeComparison.of(
                listOf(VolumeBucket(base.plusDays(-7.0)), VolumeBucket(base, linkedMapOf("chest" to MuscleLoad(100.0, 1.0)), totalSets = 1)),
            )
            assertNull(comparison?.change)
            assertEquals(1, comparison?.muscles?.size)
        }
    }

    @Nested
    inner class EffectiveSetsTests {
        @Test
        fun `skala tjednih serija i serija jednog treninga`() {
            assertEquals(listOf(0, 1, 1, 2, 2, 3, 3, 4), listOf(0.0, 1.0, 4.5, 5.0, 9.5, 10.0, 20.0, 20.5).map(LoadScale::weeklyLevel))
            assertEquals(listOf(0, 1, 1, 2, 2, 3, 3, 4), listOf(0.0, 0.5, 2.5, 3.0, 5.5, 6.0, 9.5, 10.0).map(LoadScale::sessionLevel))
            assertEquals(0.5, LoadScale.intensity(2))
            assertEquals(1.0, LoadScale.intensity(9))
        }

        @Test
        fun `warm-up i serija s niskim RPE-om nisu tvrde`() {
            assertTrue(EffectiveSets.isHard(SetValues(weightKg = 50.0, reps = 10)))
            assertTrue(EffectiveSets.isHard(SetValues(weightKg = 50.0, reps = 10, rpe = 6.0)))
            assertFalse(EffectiveSets.isHard(SetValues(weightKg = 50.0, reps = 10, rpe = 5.5)))
            assertFalse(EffectiveSets.isHard(SetValues(kind = SetKind.WARM_UP, weightKg = 50.0, reps = 10)))
        }
    }

    @Nested
    inner class DoneExercisesTests {
        @Test
        fun `samo vježbe iz završenih treninga, bez ponavljanja i abecedno`() {
            val store = newStore()
            val engine = WorkoutEngine(store)
            val finished = engine.startSession("A", now = base)
            val squatSet = engine.addExercise(squat, ExerciseInputType.WEIGHT_REPS, finished, now = base).orderedSets[0]
            squatSet.weightKg = 100.0
            squatSet.reps = 5
            engine.completeSet(squatSet, 0, base)
            val benchSet = engine.addExercise(bench, ExerciseInputType.WEIGHT_REPS, finished, now = base).orderedSets[0]
            benchSet.weightKg = 80.0
            benchSet.reps = 5
            engine.completeSet(benchSet, 0, base)
            engine.finishSession(finished, now = base.plusSeconds(3600))

            val active = engine.startSession("B", now = base.plusDays(1.0))
            engine.addExercise(ExerciseRef.catalog("row", "Veslanje"), ExerciseInputType.WEIGHT_REPS, active, now = base.plusDays(1.0))

            val done = DoneExercises.fetch(store, java.util.Locale.forLanguageTag("hr"))
            assertEquals(listOf("Čučanj", "Potisak s klupe"), done.map { it.name })
            assertEquals(squat.key, done.first().ref?.key)
        }
    }
}

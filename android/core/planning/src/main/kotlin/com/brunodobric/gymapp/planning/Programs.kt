package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.catalog.ExerciseInputType
import com.brunodobric.gymapp.model.ExerciseRef
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.GymStore
import com.brunodobric.gymapp.model.ReminderMode
import com.brunodobric.gymapp.model.Schedule
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.model.WorkoutTemplate

// Gotovi programi (docs/SPECIFIKACIJA.md, "Gotovi programi i preporuka").
// Program zadaje strukturu: treninge, vježbe kao obrasce kretanja i broj serija. Ponavljanja i pauze
// slijede iz cilja i iskustva (`ProgramPrescription`), a konkretna vježba iz opreme koju korisnik ima.
// Podloga: ACSM 2026 (Currier i sur.), Pelland i sur. 2026, Schoenfeld i sur. 2016, 2019 i 2021.

/** Uloga vježbe u treningu: određuje raspon ponavljanja i pauzu. */
enum class ExerciseRole {
    /** Glavna višezglobna vježba, na početku treninga, s najvećim opterećenjem. */
    MAIN,

    /** Pomoćna višezglobna vježba. */
    SECONDARY,

    /** Izolacijska vježba. Preskače se kad za nju nema opreme. */
    ISOLATION,
}

/** Jedna izvedba obrasca kretanja: vježba iz kataloga i oprema bez koje se ne može. */
data class ExerciseOption(
    val catalogId: String,
    val inputType: ExerciseInputType,
    /** Potrebna oprema. Prazno znači samo vlastita težina. Šipka za zgibove je [Equipment.OTHER]. */
    val equipment: Set<Equipment>,
) {
    fun isAvailable(available: Set<Equipment>): Boolean = available.containsAll(equipment)
}

data class ProgramExercise(
    /** Izvedbe po redu prednosti: bira se prva za koju korisnik ima opremu. */
    val options: List<ExerciseOption>,
    val role: ExerciseRole,
    val sets: Int,
) {
    /** Prva izvedba za dostupnu opremu, ili null kad nijedna nije moguća. */
    fun option(available: Set<Equipment>): ExerciseOption? = options.firstOrNull { it.isAvailable(available) }
}

data class ProgramWorkout(val key: String, val name: String, val exercises: List<ProgramExercise>)

sealed interface ProgramStep {
    data class Workout(val key: String) : ProgramStep
    data object RestDay : ProgramStep
}

/** Gotov program: skup treninga, njihov redoslijed i za koga je. */
data class Program(
    val id: String,
    val name: String,
    val summary: String,
    /** Treninga tjedno kad se niz prati po danima podsjetnika. */
    val daysPerWeek: Int,
    /** Broj dana tjedno za koje program odgovara (preporuka). */
    val suitableDays: IntRange,
    val goals: Set<TrainingGoal>,
    val levels: Set<ExperienceLevel>,
    val workouts: List<ProgramWorkout>,
    /** Niz jednog ciklusa. Može trajati više tjedana (A/B izmjena), tada ima `daysPerWeek × weeks` treninga. */
    val sequence: List<ProgramStep>,
    val weeks: Int,
) {
    /** Program se može izvesti kad glavne i pomoćne vježbe imaju izvedbu za dostupnu opremu. */
    fun isAvailable(available: Set<Equipment>): Boolean =
        workouts.all { workout -> workout.exercises.all { it.role == ExerciseRole.ISOLATION || it.option(available) != null } }

    /**
     * Broj dana treninga tjedno nakon dodavanja za profil (dani podsjetnika): dani iz profila ako ih program
     * podržava, inače dani programa.
     */
    fun trainingDays(profile: TrainingProfile): Int =
        profile.daysPerWeek?.takeIf { it in suitableDays }?.let { minOf(it, daysPerWeek) } ?: daysPerWeek
}

/** Ponavljanja, pauza i broj serija za jednu vježbu programa. */
data class Prescription(val sets: Int, val repsMin: Int, val repsMax: Int, val restSeconds: Int)

/**
 * Doziranje prema cilju i iskustvu. Snaga: glavne vježbe 3–6 ponavljanja (≥80 % 1RM). Hipertrofija:
 * 6–15 ponavljanja blizu otkaza. Opća kondicija: 8–15 ponavljanja i serija manje (ACSM 2026; Schoenfeld i sur.
 * 2021). Pauze 2–3 min za višezglobne vježbe (Schoenfeld i sur. 2016). Početnik radi seriju manje
 * izolacijskih vježbi: kod početnika i manji volumen daje napredak, a tehnika glavnih vježbi je važnija.
 */
object ProgramPrescription {
    fun make(role: ExerciseRole, sets: Int, goal: TrainingGoal?, level: ExperienceLevel?): Prescription {
        val target = goal ?: TrainingGoal.HYPERTROPHY
        var count = sets
        if (target == TrainingGoal.GENERAL_FITNESS) count -= 1
        if (level == ExperienceLevel.BEGINNER && role == ExerciseRole.ISOLATION) count -= 1
        count = maxOf(2, count)

        fun dose(min: Int, max: Int, rest: Int) = Prescription(count, min, max, rest)
        return when (target) {
            TrainingGoal.STRENGTH -> when (role) {
                ExerciseRole.MAIN -> dose(3, 6, 180)
                ExerciseRole.SECONDARY -> dose(5, 8, 150)
                ExerciseRole.ISOLATION -> dose(8, 12, 90)
            }
            TrainingGoal.HYPERTROPHY, TrainingGoal.RECOMPOSITION -> when (role) {
                ExerciseRole.MAIN -> dose(6, 10, 150)
                ExerciseRole.SECONDARY -> dose(8, 12, 120)
                ExerciseRole.ISOLATION -> dose(10, 15, 90)
            }
            TrainingGoal.GENERAL_FITNESS -> when (role) {
                ExerciseRole.MAIN -> dose(8, 12, 120)
                ExerciseRole.SECONDARY -> dose(10, 15, 90)
                ExerciseRole.ISOLATION -> dose(12, 15, 60)
            }
        }
    }
}

object ProgramLibrary {
    private val allGoals = TrainingGoal.entries.toSet()
    private val allLevels = ExperienceLevel.entries.toSet()
    private val rest = ProgramStep.RestDay
    private fun w(key: String) = ProgramStep.Workout(key)

    val all: List<Program> = with(ProgramContent) {
        listOf(
            Program(
                "basic-full-body-2", "Osnovni full body (2 dana)",
                "Dva kratka treninga cijelog tijela tjedno. Dovoljno za zdravlje i napredak kad nema više vremena.",
                2, 1..2, allGoals, allLevels, listOf(basicA, basicB),
                listOf(rest, w("basicA"), rest, rest, w("basicB"), rest, rest), 1,
            ),
            Program(
                "beginner-full-body-3", "Početnički full body (3 dana)",
                "Treninzi A i B naizmjence, tri puta tjedno. Malo vježbi, svaki mišić tri puta tjedno.",
                3, 3..3, allGoals, setOf(ExperienceLevel.BEGINNER), listOf(beginnerA, beginnerB),
                listOf(
                    w("beginnerA"), rest, w("beginnerB"), rest, w("beginnerA"), rest, rest,
                    w("beginnerB"), rest, w("beginnerA"), rest, w("beginnerB"), rest, rest,
                ),
                2,
            ),
            Program(
                "full-body-3", "Full body (3 dana)",
                "Tri različita treninga cijelog tijela tjedno, svaki mišić dva do tri puta.",
                3, 3..3, allGoals, setOf(ExperienceLevel.INTERMEDIATE, ExperienceLevel.ADVANCED),
                listOf(fullBodyA, fullBodyB, fullBodyC),
                listOf(w("fullA"), rest, w("fullB"), rest, w("fullC"), rest, rest), 1,
            ),
            Program(
                "upper-lower-4", "Upper/Lower (4 dana)",
                "Dva dana gornjeg i dva dana donjeg dijela tijela tjedno, svaki mišić dvaput.",
                4, 4..4, allGoals, allLevels, listOf(upperA, lowerA, upperB, lowerB),
                listOf(w("upperA"), w("lowerA"), rest, w("upperB"), w("lowerB"), rest, rest), 1,
            ),
            Program(
                "upper-lower-ppl-5", "Upper/Lower + PPL (5 dana)",
                "Gornji i donji dio tijela, dan odmora, pa guranje, povlačenje i noge. Svaki mišić dvaput tjedno.",
                5, 5..5, setOf(TrainingGoal.HYPERTROPHY, TrainingGoal.RECOMPOSITION, TrainingGoal.STRENGTH),
                setOf(ExperienceLevel.INTERMEDIATE, ExperienceLevel.ADVANCED),
                listOf(upperA, lowerA, pushB, pullA, legsB),
                listOf(w("upperA"), w("lowerA"), rest, w("pushB"), w("pullA"), w("legsB"), rest), 1,
            ),
            Program(
                "ppl-6", "Push/Pull/Legs (6 dana)",
                "Guranje, povlačenje i noge dvaput tjedno, s dvije varijante svakog treninga.",
                6, 6..7, setOf(TrainingGoal.HYPERTROPHY, TrainingGoal.RECOMPOSITION),
                setOf(ExperienceLevel.INTERMEDIATE, ExperienceLevel.ADVANCED),
                listOf(pushA, pullA, legsA, pushB, pullB, legsB),
                listOf(w("pushA"), w("pullA"), w("legsA"), w("pushB"), w("pullB"), w("legsB"), rest), 1,
            ),
        )
    }

    /**
     * Dani u tjednu (kao `Calendar.weekday`, 1 = nedjelja) za fiksne podsjetnike, s odmorom između treninga
     * gdje god je moguće.
     */
    fun defaultWeekdays(daysPerWeek: Int): List<Int> = when {
        daysPerWeek <= 1 -> listOf(4)
        daysPerWeek == 2 -> listOf(3, 6)
        daysPerWeek == 3 -> listOf(2, 4, 6)
        daysPerWeek == 4 -> listOf(2, 3, 5, 6)
        daysPerWeek == 5 -> listOf(2, 3, 5, 6, 7)
        daysPerWeek == 6 -> listOf(2, 3, 4, 5, 6, 7)
        else -> listOf(1, 2, 3, 4, 5, 6, 7)
    }
}

/** Stvara predloške i raspored iz gotovog programa. Nazive vježbi daje pozivatelj (katalog je na jeziku korisnika). */
class ProgramInstaller(private val store: GymStore) {

    /**
     * @param profile cilj i iskustvo određuju ponavljanja i pauze, a oprema izvedbu vježbe.
     *   Bez opreme u profilu vrijedi teretana (sva oprema).
     * @param name naziv rasporeda na jeziku sučelja (zadano: hrvatski naziv programa)
     * @param workoutName naziv treninga na jeziku sučelja (zadano: hrvatski naziv)
     */
    fun install(
        program: Program,
        profile: TrainingProfile = TrainingProfile(),
        name: String? = null,
        workoutName: (ProgramWorkout) -> String = { it.name },
        exerciseName: (String) -> String,
    ): Schedule {
        val templates = TemplateEngine(store)
        val schedules = ScheduleEngine(store)
        val available = profile.availableEquipment
        val created = mutableMapOf<String, WorkoutTemplate>()

        for (workout in program.workouts) {
            val template = templates.createTemplate(workoutName(workout))
            for (item in workout.exercises) {
                // Glavne i pomoćne vježbe uvijek postoje (ako oprema ne odgovara, ide prva izvedba),
                // a izolacijska se preskače.
                val choice = item.option(available)
                    ?: (if (item.role == ExerciseRole.ISOLATION) null else item.options.first())
                    ?: continue
                val dose = ProgramPrescription.make(item.role, item.sets, profile.goal, profile.experience)
                val ref = ExerciseRef.catalog(choice.catalogId, exerciseName(choice.catalogId))
                val exercise = templates.addExercise(ref, choice.inputType, template, dose.sets)
                exercise.restSeconds = dose.restSeconds
                if (choice.inputType != ExerciseInputType.DURATION && choice.inputType != ExerciseInputType.DURATION_DISTANCE) {
                    for (set in exercise.orderedSets) {
                        set.targetReps = dose.repsMin
                        set.targetRepsMax = dose.repsMax
                    }
                }
            }
            created[workout.key] = template
        }
        store.save()

        val schedule = schedules.createSchedule(name ?: program.name)
        for (step in program.sequence) {
            when (step) {
                is ProgramStep.Workout -> created[step.key]?.let { schedules.addWorkout(it, schedule) }
                ProgramStep.RestDay -> schedules.addRestDay(schedule)
            }
        }
        // Fiksni dani za podsjetnike: inače bi "3 dana" s jednim danom razmaka bila 4 treninga tjedno.
        // Vrijeme podsjetnika ostaje prazno, pa se ništa ne zakazuje dok ga korisnik ne postavi.
        schedule.reminderMode = ReminderMode.FIXED_DAYS
        schedule.weekdays = ProgramLibrary.defaultWeekdays(program.trainingDays(profile))
        store.save()
        return schedule
    }
}

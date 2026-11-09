package com.brunodobric.gymapp.planning

import com.brunodobric.gymapp.catalog.Equipment
import com.brunodobric.gymapp.model.ExperienceLevel
import com.brunodobric.gymapp.model.OnboardingAnswers
import com.brunodobric.gymapp.model.TrainingGoal
import com.brunodobric.gymapp.model.UserSettings

/** Ono što preporuka i instalacija programa znaju o korisniku: odgovori iz onboardinga ili profila u Postavkama. */
data class TrainingProfile(
    val goal: TrainingGoal? = null,
    val experience: ExperienceLevel? = null,
    /** Dostupna oprema. Prazno znači da korisnik nije odgovorio, i tada vrijedi teretana. */
    val equipment: Set<Equipment> = emptySet(),
    val daysPerWeek: Int? = null,
) {
    /** Oprema za odabir vježbi. Vlastita težina je uvijek dostupna. */
    val availableEquipment: Set<Equipment>
        get() = (equipment.ifEmpty { Equipment.entries.toSet() }) + Equipment.BODYWEIGHT

    /** Ima li profil išta po čemu se može preporučiti (inače se preporuka ne nudi). */
    val hasAnswers: Boolean get() = goal != null || experience != null || daysPerWeek != null || equipment.isNotEmpty()

    /**
     * Dani treninga programa kad ih je manje od cilja dana tjedno, inače null. Tada se prije dodavanja
     * nudi smanjenje cilja (korisnik može zadržati cilj i dodatni trening odraditi sam).
     */
    fun lowerDaysGoal(program: Program): Int? {
        val target = daysPerWeek ?: return null
        val days = program.trainingDays(this)
        return if (days < target) days else null
    }

    companion object {
        fun from(answers: OnboardingAnswers) = TrainingProfile(
            answers.goal, answers.experience, answers.equipment.toSet(), answers.validDaysPerWeek,
        )

        fun from(settings: UserSettings) = TrainingProfile(
            settings.goal, settings.experience, settings.equipment.toSet(), settings.trainingDaysPerWeek,
        )
    }
}

/** Zašto je program predložen. Tekst slaže aplikacija na jeziku sučelja. */
sealed interface RecommendationReason {
    data class Days(val days: Int) : RecommendationReason
    data class Goal(val goal: TrainingGoal) : RecommendationReason
    data class Level(val level: ExperienceLevel) : RecommendationReason

    /** Sve vježbe se mogu izvesti s odabranom opremom. */
    data object EquipmentFits : RecommendationReason
}

data class ProgramRecommendation(val program: Program, val score: Int, val reasons: List<RecommendationReason>)

/**
 * Prijedlog gotovih programa iz profila. Oprema je tvrdi filtar; dani, cilj i iskustvo daju bodove.
 * Bez odgovora o danima vrijede 3 dana, a bez iskustva početnik (sigurniji izbor).
 */
object ProgramRecommender {
    const val DEFAULT_DAYS = 3

    fun recommend(
        profile: TrainingProfile,
        programs: List<Program> = ProgramLibrary.all,
        limit: Int = 3,
    ): List<ProgramRecommendation> {
        val available = profile.availableEquipment
        val days = profile.daysPerWeek ?: DEFAULT_DAYS
        val level = profile.experience ?: ExperienceLevel.BEGINNER

        val scored = programs.withIndex().mapNotNull { (index, program) ->
            if (!program.isAvailable(available)) return@mapNotNull null
            var score = 0
            val reasons = mutableListOf<RecommendationReason>()

            // Dani su glavni kriterij: točan pogodak vrijedi najviše, a svaki dan razlike oduzima.
            if (days in program.suitableDays) {
                score += 6
                reasons += RecommendationReason.Days(days)
            } else {
                val distance = if (days < program.suitableDays.first) program.suitableDays.first - days
                else days - program.suitableDays.last
                score -= 3 * distance
            }
            if (level in program.levels) {
                score += 3
                if (profile.experience != null) reasons += RecommendationReason.Level(level)
            }
            val goal = profile.goal
            if (goal != null && goal in program.goals) {
                score += 2
                reasons += RecommendationReason.Goal(goal)
            }
            if (profile.equipment.isNotEmpty()) reasons += RecommendationReason.EquipmentFits
            index to ProgramRecommendation(program, score, reasons)
        }

        // Jednaki bodovi: redoslijed knjižnice (od jednostavnijeg prema složenijem).
        return scored
            .sortedWith(compareByDescending<Pair<Int, ProgramRecommendation>> { it.second.score }.thenBy { it.first })
            .take(limit)
            .map { it.second }
    }
}

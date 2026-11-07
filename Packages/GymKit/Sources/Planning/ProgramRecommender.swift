import Catalog
import Foundation
import Models

/// Ono što preporuka i instalacija programa znaju o korisniku: odgovori iz onboardinga ili profila u Postavkama.
public struct TrainingProfile: Equatable, Sendable {
    public var goal: TrainingGoal?
    public var experience: ExperienceLevel?
    /// Dostupna oprema. Prazno znači da korisnik nije odgovorio, i tada vrijedi teretana.
    public var equipment: Set<Equipment>
    public var daysPerWeek: Int?

    public init(
        goal: TrainingGoal? = nil,
        experience: ExperienceLevel? = nil,
        equipment: Set<Equipment> = [],
        daysPerWeek: Int? = nil
    ) {
        self.goal = goal
        self.experience = experience
        self.equipment = equipment
        self.daysPerWeek = daysPerWeek
    }

    public init(answers: OnboardingAnswers) {
        self.init(
            goal: answers.goal, experience: answers.experience,
            equipment: Set(answers.equipment), daysPerWeek: answers.validDaysPerWeek
        )
    }

    public init(settings: UserSettings) {
        self.init(
            goal: settings.goal, experience: settings.experience,
            equipment: Set(settings.equipment), daysPerWeek: settings.trainingDaysPerWeek
        )
    }

    /// Oprema za odabir vježbi. Vlastita težina je uvijek dostupna.
    public var availableEquipment: Set<Equipment> {
        (equipment.isEmpty ? Set(Equipment.allCases) : equipment).union([.bodyweight])
    }

    /// Ima li profil išta po čemu se može preporučiti (inače se preporuka ne nudi).
    public var hasAnswers: Bool {
        goal != nil || experience != nil || daysPerWeek != nil || !equipment.isEmpty
    }
}

/// Zašto je program predložen. Tekst slaže aplikacija na jeziku sučelja.
public enum RecommendationReason: Equatable, Sendable {
    case days(Int)
    case goal(TrainingGoal)
    case level(ExperienceLevel)
    /// Sve vježbe se mogu izvesti s odabranom opremom.
    case equipment
}

public struct ProgramRecommendation: Equatable, Sendable {
    public let program: Program
    public let score: Int
    public let reasons: [RecommendationReason]
}

/// Prijedlog gotovih programa iz profila. Oprema je tvrdi filtar; dani, cilj i iskustvo daju bodove.
/// Bez odgovora o danima vrijede 3 dana, a bez iskustva početnik (sigurniji izbor).
public enum ProgramRecommender {
    public static let defaultDays = 3

    public static func recommend(
        for profile: TrainingProfile,
        programs: [Program] = ProgramLibrary.all,
        limit: Int = 3
    ) -> [ProgramRecommendation] {
        let available = profile.availableEquipment
        let days = profile.daysPerWeek ?? defaultDays
        let level = profile.experience ?? .beginner

        let scored = programs.enumerated().compactMap { index, program -> (Int, ProgramRecommendation)? in
            guard program.isAvailable(with: available) else { return nil }
            var score = 0
            var reasons: [RecommendationReason] = []

            // Dani su glavni kriterij: točan pogodak vrijedi najviše, a svaki dan razlike oduzima.
            if program.suitableDays.contains(days) {
                score += 6
                reasons.append(.days(days))
            } else {
                let distance = days < program.suitableDays.lowerBound
                    ? program.suitableDays.lowerBound - days
                    : days - program.suitableDays.upperBound
                score -= 3 * distance
            }
            if program.levels.contains(level) {
                score += 3
                if profile.experience != nil { reasons.append(.level(level)) }
            }
            if let goal = profile.goal, program.goals.contains(goal) {
                score += 2
                reasons.append(.goal(goal))
            }
            if !profile.equipment.isEmpty { reasons.append(.equipment) }
            return (index, ProgramRecommendation(program: program, score: score, reasons: reasons))
        }

        // Jednaki bodovi: redoslijed knjižnice (od jednostavnijeg prema složenijem).
        return scored
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
            .prefix(limit)
            .map { $0.1 }
    }
}

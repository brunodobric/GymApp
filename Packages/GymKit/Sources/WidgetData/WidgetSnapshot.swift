import Foundation
import Units

/// Podaci za widgete na iPhoneu, iPadu i satu: aplikacija ih slaže iz baze (`WidgetSnapshotBuilder`),
/// sprema u zajednički App Group (`WidgetSnapshotStore`), a widget extension ih samo čita i crta.
///
/// Widget nema pristup bazi ni katalogu, pa snimka nosi gotove nazive i brojeve. Težina je u kg (`Units`),
/// a jedinica za prikaz ide uz nju. Tekstovi koji ovise o jeziku (npr. rekord) dolaze već oblikovani iz aplikacije.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    /// Naglasna boja iz Postavki (`AccentChoice.rawValue`).
    public var accent: String
    public var weightUnit: WeightUnit
    /// Trening u tijeku; dok traje, widget sljedećeg treninga nudi nastavak.
    public var activeWorkout: ActiveWorkout?
    public var nextWorkout: NextWorkout?
    public var week: Week?
    public var bodyWeight: BodyWeight?
    public var lastWorkout: LastWorkout?
    public var latestRecord: Record?

    public init(
        generatedAt: Date, accent: String = "blue", weightUnit: WeightUnit = .kilograms,
        activeWorkout: ActiveWorkout? = nil, nextWorkout: NextWorkout? = nil, week: Week? = nil,
        bodyWeight: BodyWeight? = nil, lastWorkout: LastWorkout? = nil, latestRecord: Record? = nil
    ) {
        self.generatedAt = generatedAt
        self.accent = accent
        self.weightUnit = weightUnit
        self.activeWorkout = activeWorkout
        self.nextWorkout = nextWorkout
        self.week = week
        self.bodyWeight = bodyWeight
        self.lastWorkout = lastWorkout
        self.latestRecord = latestRecord
    }

    /// Prazna snimka (prije prvog pokretanja aplikacije).
    public static let empty = WidgetSnapshot(generatedAt: .distantPast)

    /// Primjer za galeriju widgeta i pregled u Xcodeu.
    public static func sample(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        var week = Week(start: start, sessions: 2, goal: 3, streakWeeks: 3, hardSets: 38, cardioSeconds: 2_700, totalSeconds: 7_800,
                        calendar: calendar)
        if week.days.count == 7 {
            week.days[0].strength = true
            week.days[2].cardio = true
            week.days[3].strength = true
        }
        return WidgetSnapshot(
            generatedAt: now,
            nextWorkout: NextWorkout(name: "Push", scheduleName: "Push / Pull / Legs", exerciseCount: 6, exercises: [
                .init(name: "Bench press", workingSets: 4, reps: 8, weightKg: 80),
                .init(name: "Military press", workingSets: 3, reps: 10, weightKg: 45),
                .init(name: "Dips", workingSets: 3, reps: 12),
            ]),
            week: week,
            bodyWeight: BodyWeight(latestKg: 82.4, date: now, changeKg: -0.6, points: [83.2, 83.0, 83.1, 82.8, 82.9, 82.6, 82.7, 82.4]),
            lastWorkout: LastWorkout(
                name: "Legs", startedAt: now.addingTimeInterval(-86_400), durationSeconds: 3_840, mix: .mixed, hardSets: 18,
                highlights: [.init(exercise: "Squat", value: "120 kg × 5")]
            ),
            latestRecord: Record(exercise: "Squat", value: "120 kg × 5", date: now.addingTimeInterval(-86_400))
        )
    }
}

// MARK: - Dijelovi snimke

extension WidgetSnapshot {
    public struct ActiveWorkout: Codable, Equatable, Sendable {
        public var name: String
        public var startedAt: Date

        public init(name: String, startedAt: Date) {
            self.name = name
            self.startedAt = startedAt
        }
    }

    /// Sljedeći trening prvog aktivnog rasporeda, s planom prvih vježbi.
    public struct NextWorkout: Codable, Equatable, Sendable {
        public var name: String
        public var scheduleName: String?
        public var exerciseCount: Int
        /// Najviše `maxExercises` prvih vježbi.
        public var exercises: [PlannedExercise]

        public static let maxExercises = 3

        public init(name: String, scheduleName: String?, exerciseCount: Int, exercises: [PlannedExercise]) {
            self.name = name
            self.scheduleName = scheduleName
            self.exerciseCount = exerciseCount
            self.exercises = Array(exercises.prefix(Self.maxExercises))
        }

        /// Vježbe koje nisu u popisu ("+3 vježbe").
        public var remainingExercises: Int { max(0, exerciseCount - exercises.count) }
    }

    /// Plan jedne vježbe: broj radnih serija i vrijednosti prve radne serije.
    public struct PlannedExercise: Codable, Equatable, Sendable {
        public var name: String
        public var workingSets: Int
        public var reps: Int?
        public var weightKg: Double?
        public var durationSeconds: Int?

        public init(name: String, workingSets: Int, reps: Int? = nil, weightKg: Double? = nil, durationSeconds: Int? = nil) {
            self.name = name
            self.workingSets = workingSets
            self.reps = reps
            self.weightKg = weightKg
            self.durationSeconds = durationSeconds
        }

        /// Kratki opis plana, npr. "4 × 8 · 80 kg", "3 × 12" ili "3 × 0:45". Prazno bez serija.
        public func summary(unit: WeightUnit, locale: Locale = .current) -> String {
            guard workingSets > 0 else { return "" }
            var parts: [String] = []
            if let reps, reps > 0 {
                parts.append("\(workingSets) × \(reps)")
            } else if let durationSeconds, durationSeconds > 0 {
                parts.append("\(workingSets) × \(DurationInput.format(durationSeconds))")
            } else {
                parts.append("\(workingSets) ×")
            }
            if let weightKg, weightKg > 0 {
                parts.append(WeightFormatter(unit: unit, locale: locale).string(fromKilograms: weightKg))
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Vrsta treninga za ikonu (kao `SessionMix`, koji widget ne vidi).
    public enum Mix: String, Codable, Sendable {
        case strength, cardio, mixed
    }

    public struct LastWorkout: Codable, Equatable, Sendable {
        public var name: String
        public var startedAt: Date
        public var durationSeconds: Int?
        public var mix: Mix
        public var hardSets: Int
        /// Najviše dva istaknuta rekorda, s vrijednošću oblikovanom u aplikaciji.
        public var highlights: [Highlight]

        public init(name: String, startedAt: Date, durationSeconds: Int?, mix: Mix, hardSets: Int, highlights: [Highlight]) {
            self.name = name
            self.startedAt = startedAt
            self.durationSeconds = durationSeconds
            self.mix = mix
            self.hardSets = hardSets
            self.highlights = Array(highlights.prefix(2))
        }
    }

    public struct Highlight: Codable, Equatable, Sendable {
        public var exercise: String
        public var value: String

        public init(exercise: String, value: String) {
            self.exercise = exercise
            self.value = value
        }
    }

    /// Najnoviji osobni rekord (najznačajniji iz zadnjeg treninga s rekordom).
    public struct Record: Codable, Equatable, Sendable {
        public var exercise: String
        public var value: String
        public var date: Date

        public init(exercise: String, value: String, date: Date) {
            self.exercise = exercise
            self.value = value
            self.date = date
        }
    }

    /// Tjelesna težina: zadnja vrijednost, promjena u 30 dana i vrijednosti za krivulju.
    public struct BodyWeight: Codable, Equatable, Sendable {
        public var latestKg: Double
        public var date: Date
        public var changeKg: Double?
        /// Vrijednosti (kg) zadnjih mjerenja, od najstarije, najviše `maxPoints`.
        public var points: [Double]

        public static let maxPoints = 30

        public init(latestKg: Double, date: Date, changeKg: Double?, points: [Double]) {
            self.latestKg = latestKg
            self.date = date
            self.changeKg = changeKg
            self.points = Array(points.suffix(Self.maxPoints))
        }

        /// Točke krivulje između 0 (najniža) i 1 (najviša). Ravna krivulja je na sredini; manje od dvije točke nema krivulje.
        public var normalizedPoints: [Double] {
            let values = points.filter(\.isFinite)
            guard values.count >= 2, let low = values.min(), let high = values.max() else { return [] }
            guard high - low > 0.000_1 else { return values.map { _ in 0.5 } }
            return values.map { ($0 - low) / (high - low) }
        }
    }
}

// MARK: - Datumi

public enum WidgetDates {
    /// Broj kalendarskih dana od `date` do `now` (0 = danas, 1 = jučer). Budući datum daje 0.
    public static func daysAgo(_ date: Date, now: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// Početci idućih dana nakon `now` (za zapise na vremenskoj crti widgeta: danas, tjedan i "prije N dana" se mijenjaju u ponoć).
    public static func nextMidnights(after now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: now)
        for _ in 0..<max(0, count) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            result.append(next)
            cursor = next
        }
        return result
    }
}

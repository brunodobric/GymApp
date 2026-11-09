import Catalog
import Foundation
import Models
import Training

// Podaci za prikaz na satu koji se računaju iz konteksta i snimke: vrsta treninga (snaga, kardio ili
// oboje), procjena trajanja, "prošli put" za seriju i kardio dio za sažetak. Ista pravila kao na iPhoneu
// (`SessionCardio`), samo nad strukturama koje sat ima.

extension PlannedSetPayload {
    public init(values: SetValues) {
        self.init(
            kind: values.kind, weightKg: values.weightKg, reps: values.reps, extraWeightKg: values.extraWeightKg,
            durationSeconds: values.durationSeconds, distanceMeters: values.distanceMeters
        )
    }

    public var values: SetValues {
        SetValues(
            kind: kind, weightKg: weightKg, reps: reps, extraWeightKg: extraWeightKg,
            durationSeconds: durationSeconds, distanceMeters: distanceMeters
        )
    }
}

extension SessionMix {
    /// Vrsta iz oznaka "je li kardio" po vježbi: bez kardija snaga, samo kardio kardio, inače oboje.
    /// Bez vježbi je snaga (kao prazan predložak na iPhoneu).
    public static func from(cardioFlags flags: [Bool]) -> SessionMix {
        let cardio = flags.filter { $0 }.count
        if cardio == 0 { return .strength }
        return cardio == flags.count ? .cardio : .mixed
    }
}

extension PlannedWorkoutPayload {
    /// Rad jedne serije bez upisanog trajanja (snaga), u sekundama.
    public static let assumedSetSeconds = 45
    /// Prijelaz na sljedeću vježbu (namještanje sprave), u sekundama.
    public static let exerciseChangeSeconds = 60

    /// Vrsta treninga iz vježbi, kao `SessionCardio.mix(of: WorkoutTemplate)` na iPhoneu.
    public var mix: SessionMix {
        SessionMix.from(cardioFlags: exercises.map { $0.isCardio ?? false })
    }

    /// Približno trajanje u minutama, zaokruženo na 5: rad serija (trajanje kardio serije ili 45 s),
    /// odmor između serija i minuta za prijelaz na sljedeću vježbu. Nil za trening bez serija.
    public func estimatedMinutes(defaultRestSeconds: Int) -> Int? {
        estimatedMinutes(restDefaults: RestDefaults(uniform: defaultRestSeconds))
    }

    /// Kao gore, a vježba bez vlastite pauze odmara prema vrsti (`RestDefaults`).
    public func estimatedMinutes(restDefaults: RestDefaults) -> Int? {
        var seconds = 0
        var setCount = 0
        for (index, exercise) in exercises.enumerated() {
            if index > 0 { seconds += Self.exerciseChangeSeconds }
            let rest = max(0, exercise.restSeconds ?? restDefaults.seconds(isCompound: [exercise.isCompound]))
            for (setIndex, set) in exercise.sets.enumerated() {
                let work = set.durationSeconds.flatMap { $0 > 0 ? $0 : nil } ?? Self.assumedSetSeconds
                seconds += work
                if setIndex < exercise.sets.count - 1 { seconds += rest }
                setCount += 1
            }
        }
        guard setCount > 0 else { return nil }
        let minutes = Double(seconds) / 60
        return max(5, Int((minutes / 5).rounded()) * 5)
    }
}

extension WatchContextPayload {
    private var allPlannedExercises: [PlannedExercisePayload] {
        (upcoming + templates).flatMap(\.exercises)
    }

    /// Zadane pauze s iPhonea (`RestDefaults`).
    public var restDefaults: RestDefaults {
        RestDefaults(compoundSeconds: compoundRestSeconds ?? defaultRestSeconds, otherSeconds: defaultRestSeconds)
    }

    /// Je li vježba složena, prema vježbama u treninzima koje je poslao iPhone. Nil za nepoznatu vježbu.
    public func isCompound(_ exercise: ExerciseRef) -> Bool? {
        let key = exercise.key
        return allPlannedExercises.first { $0.exercise.key == key && $0.isCompound != nil }?.isCompound
    }

    /// Je li vježba kardio, prema vježbama u treninzima koje je poslao iPhone. Nepoznata vježba nije kardio.
    public func isCardio(_ exercise: ExerciseRef) -> Bool {
        let key = exercise.key
        return allPlannedExercises.contains { $0.exercise.key == key && $0.isCardio == true }
    }

    /// Vrijednosti iz zadnjeg izvođenja za seriju na danom mjestu (redni broj među serijama iste vrste),
    /// po istom pravilu kao "prošli put" na iPhoneu (`SmartDefaults`): serija iznad broja prošlih
    /// dobiva zadnju prošlu. Nil kad vježba nije bila odrađena.
    public func previousSet(for exercise: ExerciseRef, kind: SetKind, position: Int) -> SetSnapshot? {
        let key = exercise.key
        guard let previous = allPlannedExercises.first(where: { $0.exercise.key == key && !($0.previous ?? []).isEmpty })?.previous,
              let values = SmartDefaults.defaults(forPosition: position, kind: kind, previous: previous.map(\.values))
        else { return nil }
        return SetSnapshot(
            orderIndex: 0, kind: kind, weightKg: values.weightKg, reps: values.reps, extraWeightKg: values.extraWeightKg,
            durationSeconds: values.durationSeconds, distanceMeters: values.distanceMeters
        )
    }
}

extension ExerciseSnapshot {
    /// Redni broj serije među serijama iste vrste (0 za prvu radnu ili prvu seriju zagrijavanja).
    public func position(ofSet setID: UUID) -> Int? {
        let ordered = orderedSets
        guard let set = ordered.first(where: { $0.id == setID }) else { return nil }
        return ordered.filter { $0.kind == set.kind }.firstIndex { $0.id == setID }
    }

    /// Broj za oznaku serije kao na iPhoneu: radne serije su 1, 2, 3…, a zagrijavanje nema broja (Z).
    public func workingNumber(ofSet setID: UUID) -> Int? {
        guard let set = sets.first(where: { $0.id == setID }), set.kind == .working else { return nil }
        return position(ofSet: setID).map { $0 + 1 }
    }

    public var completedSetCount: Int { sets.filter(\.isCompleted).count }
}

extension SessionSnapshot {
    /// Odrađene vježbe: nisu izbačene i imaju barem jednu seriju s kvačicom.
    private var doneExercises: [ExerciseSnapshot] {
        visibleExercises.filter { $0.sets.contains(where: \.isCompleted) }
    }

    /// Vježbe kojima su sve serije završene.
    public var completedExerciseCount: Int {
        visibleExercises.filter { !$0.sets.isEmpty && $0.isFullyCompleted }.count
    }

    /// Vrsta za sažetak, kao `SessionCardio.mix(of: Session)`: snaga s odrađenim samo kardio vježbama je kardio.
    public func mix(isCardio: (ExerciseRef) -> Bool) -> SessionMix {
        SessionMix.from(cardioFlags: doneExercises.map { isCardio($0.exercise) })
    }

    /// Zbroj odrađenih serija kardio vježbi, kao `SessionCardio.part`; nil kad ih nema.
    public func cardioPart(isCardio: (ExerciseRef) -> Bool) -> CardioPart? {
        let cardio = doneExercises.filter { isCardio($0.exercise) }
        guard !cardio.isEmpty else { return nil }
        let sets = cardio.flatMap(\.sets).filter(\.isCompleted)
        let seconds = sets.reduce(0) { $0 + max(0, $1.durationSeconds ?? 0) }
        let distances = sets.compactMap(\.distanceMeters).filter { $0 > 0 }
        return CardioPart(seconds: seconds, meters: distances.isEmpty ? nil : distances.reduce(0, +))
    }

    /// Završene serije bez kardio vježbi (kardio se ne broji u serije, kao na iPhoneu).
    public func strengthSetCount(isCardio: (ExerciseRef) -> Bool) -> Int {
        visibleExercises.filter { !isCardio($0.exercise) }.reduce(0) { $0 + $1.completedSetCount }
    }
}

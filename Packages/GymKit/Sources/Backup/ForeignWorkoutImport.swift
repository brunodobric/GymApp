import Catalog
import Foundation
import Models
import SwiftData

/// Uvoz treninga iz CSV izvoza druge aplikacije (`ForeignWorkoutsCSV`): prvo pregled, pa uvoz.
///
/// * Svaki trening dobiva stabilan UUID iz zaglavlja i datuma, pa se već uvezeni trening preskače
///   (i kod ponovnog uvoza iste ili novije datoteke, i na drugom uređaju nakon sinkronizacije).
/// * Vježbe se povezuju s katalogom (`ForeignExerciseMatcher`). Ostale postaju vlastite vježbe;
///   ako vlastita vježba istog naziva već postoji, koristi se ona.
/// * Serije bez ponavljanja i trajanja ("-") se ne uvoze, a ni vježba kojoj ne ostane nijedna serija.
public enum ForeignWorkoutImport {

    /// Kamo ide vježba iz datoteke.
    public enum Target: Equatable, Sendable {
        case catalog(id: String, name: String)
        case existingCustom(id: UUID, name: String)
        case newCustom(name: String)

        public var name: String {
            switch self {
            case .catalog(_, let name), .existingCustom(_, let name), .newCustom(let name): name
            }
        }

        public var isNewCustom: Bool {
            if case .newCustom = self { return true }
            return false
        }
    }

    /// Jedna vježba iz datoteke i kamo će se uvesti.
    public struct ExerciseMapping: Identifiable, Equatable, Sendable {
        /// Naziv i oprema iz datoteke ("incline bench press|dumbbells").
        public var id: String
        public var sourceName: String
        public var sourceEquipment: String
        public var target: Target
        public var inputType: ExerciseInputType
        /// U koliko novih treninga se pojavljuje.
        public var workoutCount: Int
    }

    /// Što će uvoz napraviti. Ne mijenja bazu.
    public struct Preview: Sendable {
        /// Treninzi koji još ne postoje, od najstarijeg.
        public var newWorkouts: [ForeignWorkoutsCSV.Workout]
        /// Treninzi koji su već uvezeni (ili se u datoteci ponavljaju).
        public var alreadyImported: Int
        /// Vježbe iz novih treninga, abecedno po nazivu iz datoteke.
        public var exercises: [ExerciseMapping]
        /// Broj odrađenih serija u novim treninzima.
        public var setCount: Int

        public var firstDate: Date? { newWorkouts.first?.startedAt }
        public var lastDate: Date? { newWorkouts.last?.startedAt }
        public var newCustomCount: Int {
            exercises.filter(\.target.isNewCustom).count
        }
    }

    /// Čita datoteku i priprema pregled. Baca `BackupError.invalidCSV` za neispravnu datoteku.
    public static func preview(
        _ text: String,
        catalog: ExerciseCatalog,
        language: String,
        context: ModelContext,
        timeZone: TimeZone = .current
    ) throws -> Preview {
        let workouts = try ForeignWorkoutsCSV.parse(text, timeZone: timeZone)
        let known = Set(try context.fetch(FetchDescriptor<Session>()).map(\.id))

        var seen = Set<UUID>()
        var fresh: [ForeignWorkoutsCSV.Workout] = []
        var skipped = 0
        for workout in workouts {
            let id = workout.stableID
            guard !known.contains(id), seen.insert(id).inserted else {
                skipped += 1
                continue
            }
            fresh.append(workout)
        }
        fresh.sort { ($0.startedAt, $0.line) < ($1.startedAt, $1.line) }

        let customs = try context.fetch(FetchDescriptor<CustomExercise>())
        var mappings: [String: ExerciseMapping] = [:]
        var setCount = 0
        for workout in fresh {
            var inWorkout = Set<String>()
            for exercise in workout.exercises {
                let done = exercise.sets.filter(\.isDone)
                guard !done.isEmpty else { continue }
                setCount += done.count
                let key = mappingKey(exercise)
                if mappings[key] == nil {
                    mappings[key] = ExerciseMapping(
                        id: key,
                        sourceName: exercise.name,
                        sourceEquipment: exercise.equipment,
                        target: target(for: exercise, catalog: catalog, language: language, customs: customs),
                        inputType: inputType(exercise),
                        workoutCount: 0
                    )
                }
                if inWorkout.insert(key).inserted { mappings[key]?.workoutCount += 1 }
            }
        }
        let sorted = mappings.values.sorted {
            ($0.sourceName.lowercased(), $0.sourceEquipment) < ($1.sourceName.lowercased(), $1.sourceEquipment)
        }
        return Preview(newWorkouts: fresh, alreadyImported: skipped, exercises: sorted, setCount: setCount)
    }

    /// Uvozi treninge iz pregleda. Sve ili ništa: kod greške se baza vraća na stanje prije uvoza.
    @discardableResult
    public static func apply(_ preview: Preview, into context: ModelContext) throws -> BackupImportResult {
        // Pregled je mogao zastarjeti (npr. sinkronizacija je u međuvremenu donijela iste treninge).
        let known = Set(try context.fetch(FetchDescriptor<Session>()).map(\.id))
        let mappings = Dictionary(uniqueKeysWithValues: preview.exercises.map { ($0.id, $0) })
        var created: [String: ExerciseRef] = [:]
        var result = BackupImportResult(skipped: preview.alreadyImported)

        do {
            for workout in preview.newWorkouts {
                guard !known.contains(workout.stableID) else {
                    result.skipped += 1
                    continue
                }
                try insert(workout, mappings: mappings, created: &created, into: context)
                result.added += 1
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return result
    }

    // MARK: Pomoćno

    private static func insert(
        _ workout: ForeignWorkoutsCSV.Workout,
        mappings: [String: ExerciseMapping],
        created: inout [String: ExerciseRef],
        into context: ModelContext
    ) throws {
        let session = Session(name: workout.name, kind: .strength, startedAt: workout.startedAt)
        session.id = workout.stableID
        session.notes = workout.details
        session.state = .finished
        let doneSets = workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isDone).count }
        // Bez trajanja u datoteci: oko tri minute po seriji, da trening ima smislen kraj.
        let duration = TimeInterval(workout.durationSeconds ?? max(doneSets, 1) * 180)
        session.endedAt = workout.startedAt.addingTimeInterval(duration)
        session.lastActivityAt = session.endedAt ?? workout.startedAt
        context.insert(session)

        var order = 0
        var setNumber = 0
        for exercise in workout.exercises {
            let done = exercise.sets.filter(\.isDone)
            let key = mappingKey(exercise)
            guard !done.isEmpty, let mapping = mappings[key] else { continue }
            let ref = try reference(for: mapping, created: &created, in: context)

            // Vrsta unosa prema podacima ovog treninga (ista vježba je mogla biti i s teretom i bez njega).
            let sessionExercise = SessionExercise(orderIndex: order, exercise: ref, inputType: inputType(exercise))
            context.insert(sessionExercise)
            sessionExercise.session = session
            order += 1

            for (index, row) in done.enumerated() {
                let set = SetLog(orderIndex: index, kind: .working)
                set.weightKg = row.weightKg
                set.extraWeightKg = row.extraWeightKg
                set.reps = row.reps
                set.durationSeconds = row.durationSeconds
                set.distanceMeters = row.distanceMeters
                // Datoteka nema vrijeme serija: raspoređuju se ravnomjerno kroz trening, redom.
                setNumber += 1
                set.completedAt = workout.startedAt.addingTimeInterval(duration * Double(setNumber) / Double(max(doneSets, 1)))
                context.insert(set)
                set.exercise = sessionExercise
            }
        }
    }

    private static func reference(
        for mapping: ExerciseMapping, created: inout [String: ExerciseRef], in context: ModelContext
    ) throws -> ExerciseRef {
        switch mapping.target {
        case .catalog(let id, let name):
            return ExerciseRef(catalogId: id, name: name)
        case .existingCustom(let id, let name):
            return ExerciseRef(customExerciseId: id, name: name)
        case .newCustom(let name):
            if let ref = created[mapping.id] { return ref }
            let custom = CustomExercise(name: name, inputType: mapping.inputType)
            custom.equipment = ForeignExerciseMatcher.equipment(from: mapping.sourceEquipment)
            context.insert(custom)
            created[mapping.id] = custom.ref
            return custom.ref
        }
    }

    private static func target(
        for exercise: ForeignWorkoutsCSV.Exercise, catalog: ExerciseCatalog, language: String, customs: [CustomExercise]
    ) -> Target {
        if let id = ForeignExerciseMatcher.catalogId(name: exercise.name, equipment: exercise.equipment, catalog: catalog),
           let item = catalog.exercise(withID: id) {
            return .catalog(id: id, name: item.displayName(language: language))
        }
        let name = ForeignExerciseMatcher.normalized(exercise.name)
        if let custom = customs.first(where: { ForeignExerciseMatcher.normalized($0.name) == name && !$0.isArchived })
            ?? customs.first(where: { ForeignExerciseMatcher.normalized($0.name) == name }) {
            return .existingCustom(id: custom.id, name: custom.name)
        }
        return .newCustom(name: exercise.name)
    }

    private static func inputType(_ exercise: ForeignWorkoutsCSV.Exercise) -> ExerciseInputType {
        switch exercise.kind {
        case .weightReps: .weightReps
        case .weightedBodyweight: .weightedBodyweight
        case .reps: .bodyweight
        case .duration: .duration
        case .durationDistance: .durationDistance
        }
    }

    private static func mappingKey(_ exercise: ForeignWorkoutsCSV.Exercise) -> String {
        ForeignExerciseMatcher.normalized(exercise.name) + "|" + ForeignExerciseMatcher.normalized(exercise.equipment)
    }
}

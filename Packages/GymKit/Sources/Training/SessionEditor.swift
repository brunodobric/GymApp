import Catalog
import Foundation
import Models
import SwiftData

/// Naknadno uređivanje odrađenog treninga: naziv, vrijeme, bilješke, vježbe i serije.
///
/// Za razliku od `WorkoutEngine` ništa se ne sprema usput, pa uređivač radi u zasebnom kontekstu
/// i odustajanje jednostavno odbacuje sve izmjene. Promjene se spremaju tek u `save`.
public struct SessionEditor {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Vježbe

    /// Dodaje vježbu na kraj treninga s praznim radnim serijama.
    @discardableResult
    public func addExercise(_ ref: ExerciseRef, inputType: ExerciseInputType, to session: Session) -> SessionExercise {
        let order = ((session.exercises ?? []).map(\.orderIndex).max() ?? -1) + 1
        let exercise = SessionExercise(orderIndex: order, exercise: ref, inputType: inputType)
        context.insert(exercise)
        exercise.session = session
        for index in 0..<WorkoutEngine.defaultWorkingSets {
            let set = SetLog(orderIndex: index)
            context.insert(set)
            set.exercise = exercise
        }
        return exercise
    }

    /// Briše vježbu sa svim serijama. Superset s jednom preostalom vježbom se raspušta.
    public func removeExercise(_ exercise: SessionExercise) {
        let session = exercise.session
        let group = exercise.supersetGroupId
        // Veza se prekida prije brisanja: bez spremanja bi vježba inače ostala u popisu treninga.
        exercise.session = nil
        context.delete(exercise)
        guard let session else { return }
        let rest = session.orderedExercises.filter { $0.id != exercise.id }
        for (index, item) in rest.enumerated() { item.orderIndex = index }
        let members = rest.filter { group != nil && $0.supersetGroupId == group }
        if members.count == 1 { members[0].supersetGroupId = nil }
    }

    // MARK: Serije

    /// Nova serija preuzima vrijednosti zadnje serije iste vrste. Ako su vrijednosti potpune, serija je
    /// odmah završena (dodaje se serija koja je odrađena, a nije upisana); prazna čeka unos i kvačicu.
    @discardableResult
    public func addSet(to exercise: SessionExercise, kind: SetKind = .working, now: Date = Date()) -> SetLog {
        let existing = exercise.orderedSets
        let set = SetLog(orderIndex: existing.count, kind: kind)
        if let last = existing.last(where: { $0.kind == kind }) {
            set.weightKg = last.weightKg
            set.reps = last.reps
            set.extraWeightKg = last.extraWeightKg
            set.durationSeconds = last.durationSeconds
            set.distanceMeters = last.distanceMeters
        }
        context.insert(set)
        set.exercise = exercise
        if SetMetrics.isComplete(set.values, inputType: exercise.inputType) {
            set.completedAt = completionDate(of: exercise, now: now)
        }
        return set
    }

    public func removeSet(_ set: SetLog) {
        let exercise = set.exercise
        set.exercise = nil
        context.delete(set)
        guard let exercise else { return }
        for (index, remaining) in exercise.orderedSets.filter({ $0.id != set.id }).enumerated() {
            remaining.orderIndex = index
        }
    }

    /// Kvačica u uređivaču: završena serija mora imati sve vrijednosti, ali ne pokreće odmor.
    public func toggleCompleted(_ set: SetLog, now: Date = Date()) throws {
        if set.isCompleted {
            set.completedAt = nil
            return
        }
        guard let exercise = set.exercise else { return }
        guard SetMetrics.isComplete(set.values, inputType: exercise.inputType) else { throw WorkoutError.setIncomplete }
        set.completedAt = completionDate(of: exercise, now: now)
    }

    // MARK: Spremanje

    /// Sprema izmjene kao kod završetka treninga: nezavršene serije i vježbe bez završene serije se brišu,
    /// a trening bez ijedne završene serije se ne sprema (može se obrisati). Kraj nije prije početka.
    public func save(_ session: Session) throws {
        let exercises = session.orderedExercises.filter { !$0.isDeleted }
        let completedSets = { (exercise: SessionExercise) in
            exercise.orderedSets.filter { !$0.isDeleted && $0.isCompleted }
        }
        let remaining = exercises.filter { !$0.isRemoved && !completedSets($0).isEmpty }
        guard !remaining.isEmpty else { throw WorkoutError.nothingCompleted }

        for exercise in exercises where !remaining.contains(where: { $0.id == exercise.id }) {
            exercise.session = nil
            context.delete(exercise)
        }
        // Superset kojem je ostala jedna vježba se raspušta.
        for exercise in remaining where exercise.supersetGroupId != nil {
            if remaining.filter({ $0.supersetGroupId == exercise.supersetGroupId }).count == 1 {
                exercise.supersetGroupId = nil
            }
        }
        for (order, exercise) in remaining.enumerated() {
            exercise.orderIndex = order
            for set in exercise.orderedSets where !set.isCompleted {
                set.exercise = nil
                context.delete(set)
            }
            for (index, set) in completedSets(exercise).enumerated() { set.orderIndex = index }
        }

        let distance = remaining.flatMap(completedSets).compactMap(\.distanceMeters).reduce(0, +)
        if distance > 0 { session.distanceMeters = distance }
        if let end = session.endedAt, end < session.startedAt { session.endedAt = session.startedAt }
        session.name = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.lastActivityAt = session.endedAt ?? session.lastActivityAt
        try context.save()
    }

    /// Serija dodana naknadno dobiva trenutak kraja treninga (kao da je odrađena prije njega).
    private func completionDate(of exercise: SessionExercise, now: Date) -> Date {
        exercise.session?.endedAt ?? now
    }
}

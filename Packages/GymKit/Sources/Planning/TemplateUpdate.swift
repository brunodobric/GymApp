import Catalog
import Foundation
import Models
import SwiftData

/// Razlika u strukturi između odrađenog treninga i predloška iz kojeg je pokrenut: koje su vježbe dodane,
/// koje nisu rađene i kojima se promijenio broj serija. Težine i ponavljanja se ne gledaju: o njima odlučuje
/// prijedlog veće težine (`SetPlanner`). Isto kao `TemplateChanges` na Androidu.
public struct TemplateChanges: Equatable, Sendable {
    public struct SetCount: Equatable, Sendable {
        public let name: String
        public let from: Int
        public let to: Int
    }

    /// Vježbe odrađene u treningu kojih nema u predlošku.
    public var added: [String] = []
    /// Vježbe iz predloška koje u treningu nisu rađene.
    public var removed: [String] = []
    /// Vježbe s drugim brojem serija.
    public var setCounts: [SetCount] = []
    /// Isti skup vježbi, ali drugim redoslijedom.
    public var reordered = false

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && setCounts.isEmpty && !reordered }

    public init() {}
}

extension TemplateEngine {

    /// Promjene koje bi `updateTemplate` napravio. Rađena vježba je ona s barem jednom završenom serijom.
    public func changes(from session: Session, to template: WorkoutTemplate) -> TemplateChanges {
        let done = Self.performed(in: session)
        let planned = template.orderedExercises
        var changes = TemplateChanges()
        let plannedKeys = planned.map(\.exercise.key)
        let doneKeys = done.map(\.exerciseKey)
        changes.added = done.filter { !plannedKeys.contains($0.exerciseKey) }.map(\.exerciseName)
        changes.removed = planned.filter { !doneKeys.contains($0.exercise.key) }.map(\.exerciseName)
        for item in planned {
            guard let match = done.first(where: { $0.exerciseKey == item.exercise.key }) else { continue }
            let count = match.orderedSets.filter(\.isCompleted).count
            if count != item.orderedSets.count {
                changes.setCounts.append(.init(name: item.exerciseName, from: item.orderedSets.count, to: count))
            }
        }
        let common = doneKeys.filter { plannedKeys.contains($0) }
        changes.reordered = common != plannedKeys.filter { doneKeys.contains($0) }
        return changes
    }

    /// Mijenja strukturu predloška prema odrađenom treningu: redoslijed i skup vježbi kao u treningu, a broj
    /// i vrsta serija kao završene serije. Postojeće vježbe zadržavaju ciljeve, bilješke i pauze; nova serija
    /// preuzima cilj zadnje serije iste vrste. Nove vježbe dobivaju ciljeve ponavljanja iz treninga, bez težine.
    public func updateTemplate(_ template: WorkoutTemplate, from session: Session) throws {
        let done = Self.performed(in: session)
        guard !done.isEmpty else { return }
        var remaining = template.orderedExercises
        var ordered: [TemplateExercise] = []
        for exercise in done {
            let completed = exercise.orderedSets.filter(\.isCompleted)
            if let index = remaining.firstIndex(where: { $0.exercise.key == exercise.exerciseKey }) {
                let item = remaining.remove(at: index)
                resize(item, to: completed.map(\.kind))
                ordered.append(item)
            } else {
                let item = TemplateExercise(orderIndex: 0, exercise: exercise.exercise, inputType: exercise.inputType)
                item.restSeconds = exercise.restSeconds
                context.insert(item)
                item.template = template
                for (index, set) in completed.enumerated() {
                    let target = TemplateSet(orderIndex: index, kind: set.kind, targetReps: set.reps)
                    context.insert(target)
                    target.exercise = item
                }
                ordered.append(item)
            }
        }
        for item in remaining { context.delete(item) }
        for (index, item) in ordered.enumerated() { item.orderIndex = index }
        // Superset s jednom vježbom (druga nije rađena) nema smisla.
        let groups = Dictionary(grouping: ordered.filter { $0.supersetGroupId != nil }) { $0.supersetGroupId }
        for (_, members) in groups where members.count == 1 { members[0].supersetGroupId = nil }
        try context.save()
    }

    /// Vježbe treninga s barem jednom završenom serijom, redom.
    static func performed(in session: Session) -> [SessionExercise] {
        session.orderedExercises.filter { !$0.isRemoved && $0.orderedSets.contains(where: \.isCompleted) }
    }

    /// Serije predloška po vrstama iz treninga: postojeće se zadržavaju po redu, višak se briše, a nova
    /// serija preuzima ciljeve zadnje serije iste vrste.
    private func resize(_ exercise: TemplateExercise, to kinds: [SetKind]) {
        var pool = exercise.orderedSets
        var result: [TemplateSet] = []
        for kind in kinds {
            if let index = pool.firstIndex(where: { $0.kind == kind }) {
                result.append(pool.remove(at: index))
            } else {
                let last = result.last { $0.kind == kind } ?? exercise.orderedSets.last { $0.kind == kind }
                let set = TemplateSet(orderIndex: 0, kind: kind, targetWeightKg: last?.targetWeightKg, targetReps: last?.targetReps)
                set.targetRepsMax = last?.targetRepsMax
                context.insert(set)
                set.exercise = exercise
                result.append(set)
            }
        }
        for set in pool { context.delete(set) }
        for (index, set) in result.enumerated() { set.orderIndex = index }
    }
}

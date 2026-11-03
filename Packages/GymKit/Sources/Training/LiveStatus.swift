import Foundation
import Models

/// Stanje aktivnog treninga za Live Activity i obavijest o kraju odmora (specifikacija, odjeljak 6):
/// trenutna i sljedeća vježba, broj serija, serija koju gumb potvrđuje i rest timer.
public struct LiveWorkoutStatus: Equatable, Sendable {
    /// Vježba sljedeće serije. `nil` kad su sve serije završene.
    public var currentExerciseName: String?
    /// Prva druga vježba koja dolazi nakon trenutne (u supersetu je to partner).
    public var nextExerciseName: String?
    /// Redni broj sljedeće serije u njezinoj vježbi (od 1) i broj serija te vježbe.
    public var setNumber: Int
    public var setCount: Int
    /// Serija koju potvrđuje gumb u Live Activityju.
    public var nextSetID: UUID?
    /// Serija ima sve vrijednosti, pa se može potvrditi bez otvaranja aplikacije.
    public var canConfirmNextSet: Bool
    public var completedSets: Int
    public var totalSets: Int
    public var rest: RestTimer?

    public var isAllCompleted: Bool { totalSets > 0 && completedSets == totalSets }
}

extension WorkoutEngine {

    /// Nezavršene serije redom kojim ih korisnik radi.
    ///
    /// Prvo dolazi skupina (vježba ili superset) zadnje završene serije, ako u njoj još ima posla, kao što ekran
    /// treninga ostaje na otvorenoj vježbi. Zatim ostale skupine po redoslijedu. U supersetu serije idu naizmjence.
    public func remainingSets(in session: Session) -> [SetLog] {
        let exercises = visibleExercises(in: session)
        var groups: [[SessionExercise]] = []
        var seen = Set<UUID>()
        for exercise in exercises where !seen.contains(exercise.id) {
            let members = group(of: exercise)
            members.forEach { seen.insert($0.id) }
            groups.append(members)
        }

        let lastCompleted = exercises
            .flatMap(\.orderedSets)
            .filter(\.isCompleted)
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        if let lastExerciseID = lastCompleted?.exercise?.id,
           let index = groups.firstIndex(where: { $0.contains { $0.id == lastExerciseID } }) {
            let current = groups.remove(at: index)
            if current.contains(where: { $0.orderedSets.contains { !$0.isCompleted } }) {
                groups.insert(current, at: 0)
            } else {
                groups.insert(current, at: index)
            }
        }

        return groups.flatMap { members in
            SupersetSequence.order(setCounts: members.map { $0.orderedSets.count })
                .map { members[$0.exercise].orderedSets[$0.set] }
                .filter { !$0.isCompleted }
        }
    }

    /// Sljedeća serija za potvrdu, ili `nil` kad je sve gotovo.
    public func nextSet(in session: Session) -> SetLog? {
        remainingSets(in: session).first
    }

    public func liveStatus(of session: Session) -> LiveWorkoutStatus {
        let remaining = remainingSets(in: session)
        let allSets = visibleExercises(in: session).flatMap(\.orderedSets)
        let next = remaining.first
        let exercise = next?.exercise
        let nextExercise = remaining.first { $0.exercise?.id != exercise?.id }?.exercise
        let setIndex = exercise?.orderedSets.firstIndex { $0.id == next?.id }
        let canConfirm = next.map { set in
            exercise.map { SetMetrics.isComplete(set.values, inputType: $0.inputType) } ?? false
        } ?? false

        return LiveWorkoutStatus(
            currentExerciseName: exercise?.exerciseName,
            nextExerciseName: nextExercise?.exerciseName,
            setNumber: setIndex.map { $0 + 1 } ?? 0,
            setCount: exercise?.orderedSets.count ?? 0,
            nextSetID: next?.id,
            canConfirmNextSet: canConfirm,
            completedSets: allSets.filter(\.isCompleted).count,
            totalSets: allSets.count,
            rest: restTimer(of: session)
        )
    }
}

/// Kad iPhone zakazuje lokalnu obavijest o kraju odmora (specifikacija, odjeljak 6, "Notifikacije").
///
/// Samo za trening koji vodi iPhone: kad ga vodi sat, kraj odmora javlja sat haptikom. iOS obavijest ne prikazuje
/// dok je aplikacija otvorena (tada zvuk i haptiku daje sama aplikacija), pa stiže kad je iPhone zaključan.
/// Svaka promjena timera (+10 / −10, preskakanje) zakazuje obavijest iznova za novi trenutak.
public enum RestNotificationPolicy {
    /// Ispod ovoga obavijest nema smisla: odmor je praktički gotov.
    public static let minimumLeadSeconds: TimeInterval = 1

    public static func fireDate(
        restEndsAt: Date?,
        controllingDevice: DeviceRole,
        notificationsEnabled: Bool,
        isSessionActive: Bool,
        now: Date
    ) -> Date? {
        guard notificationsEnabled, isSessionActive, controllingDevice == .phone, let restEndsAt,
              restEndsAt.timeIntervalSince(now) > minimumLeadSeconds else { return nil }
        return restEndsAt
    }
}

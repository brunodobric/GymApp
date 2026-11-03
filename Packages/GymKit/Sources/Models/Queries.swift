import Foundation
import SwiftData

/// Pomoćne funkcije za dohvat koje koriste ekrani, sat i logika treninga.
public struct GymQueries {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Trening koji je trenutno u tijeku (za oporavak prekinutog treninga). Ako ih je više, vraća najnoviji.
    public func activeSession() throws -> Session? {
        let active = SessionState.active.rawValue
        var descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == active },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Završeni treninzi čiji je početak u rasponu [from, to), od najnovijeg prema starijem.
    /// Uključuje treninge uvezene iz Zdravlja (iz lokalne baze, kao `Session` za prikaz).
    public func finishedSessions(from: Date, to: Date) throws -> [Session] {
        let finished = SessionState.finished.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished && $0.startedAt >= from && $0.startedAt < to }
        )
        let own = try context.fetch(descriptor)
        let imported = try HealthLocalStore(context: context).sessions(from: from, to: to)
        return (own + imported).sorted { $0.startedAt > $1.startedAt }
    }

    /// Svi završeni treninzi, i oni uvezeni iz Zdravlja, od najnovijeg prema starijem.
    public func allFinishedSessions() throws -> [Session] {
        try finishedSessions(from: .distantPast, to: .distantFuture)
    }

    /// Zadnje izvođenje vježbe u završenom treningu (izvor za smart defaults i inline povijest).
    /// Izbačene vježbe i treninzi koji nisu završeni se preskaču.
    public func lastPerformance(of exercise: ExerciseRef) throws -> SessionExercise? {
        let key = exercise.key
        let descriptor = FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.exerciseKey == key && $0.isRemoved == false }
        )
        let finished = SessionState.finished
        return try context.fetch(descriptor)
            .filter { $0.session?.state == finished }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }

    /// Jedini zapis postavki. Ako ga nema, stvara se sa zadanim vrijednostima.
    /// Ako ih zbog sinkronizacije ima više, vraća onaj koji ostaje nakon uklanjanja duplikata
    /// (`UserSettings.preferred(in:)`).
    public func settings() throws -> UserSettings {
        if let existing = UserSettings.preferred(in: try context.fetch(FetchDescriptor<UserSettings>())) {
            return existing
        }
        let created = UserSettings()
        context.insert(created)
        return created
    }
}

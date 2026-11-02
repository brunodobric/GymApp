import Foundation
import Models
import SwiftData

public enum HistorySort: Sendable {
    case newestFirst
    case oldestFirst
}

/// Filter i sortiranje popisa odrađenih treninga. Prazan skup vrsta znači sve vrste.
public struct HistoryFilter: Equatable, Sendable {
    public var kinds: Set<WorkoutKind>
    public var sort: HistorySort

    public init(kinds: Set<WorkoutKind> = [], sort: HistorySort = .newestFirst) {
        self.kinds = kinds
        self.sort = sort
    }
}

/// Povijest odrađenih treninga: popis, dani s treningom za kalendar i brisanje.
public struct HistoryQueries {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func sessions(filter: HistoryFilter = HistoryFilter()) throws -> [Session] {
        let finished = SessionState.finished.rawValue
        let order: SortOrder = filter.sort == .newestFirst ? .reverse : .forward
        let all = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished },
            sortBy: [SortDescriptor(\.startedAt, order: order)]
        ))
        guard !filter.kinds.isEmpty else { return all }
        return all.filter { filter.kinds.contains($0.kind) }
    }

    /// Početak svakog dana u rasponu u kojem postoji odrađen trening (točkice u kalendaru).
    public func workoutDays(in interval: DateInterval, calendar: Calendar = .current) throws -> Set<Date> {
        let found = try GymQueries(context: context).finishedSessions(from: interval.start, to: interval.end)
        return Set(found.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Treninzi odrađeni određenog dana, od najranijeg.
    public func sessions(on day: Date, calendar: Calendar = .current) throws -> [Session] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try GymQueries(context: context).finishedSessions(from: start, to: end).reversed()
    }

    /// Briše trening zajedno s vježbama i serijama. Raspored se ne vraća unatrag.
    public func delete(_ session: Session) throws {
        context.delete(session)
        try context.save()
    }
}

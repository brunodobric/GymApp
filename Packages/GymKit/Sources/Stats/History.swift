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

    /// Primjenjuje filter i sortiranje na već učitane treninge (za žive upite u sučelju).
    public func apply(to sessions: [Session]) -> [Session] {
        let selected = kinds.isEmpty ? sessions : sessions.filter { kinds.contains($0.kind) }
        return selected.sorted { sort == .newestFirst ? $0.startedAt > $1.startedAt : $0.startedAt < $1.startedAt }
    }

    /// Popis ispod kalendara: treninzi odabranog dana ili, bez odabira, cijelog prikazanog mjeseca.
    public func apply(to sessions: [Session], month: Date, day: Date?, calendar: Calendar = .current) -> [Session] {
        let component: Calendar.Component = day == nil ? .month : .day
        guard let interval = calendar.dateInterval(of: component, for: day ?? month) else { return [] }
        return apply(to: sessions.filter { interval.contains($0.startedAt) && $0.startedAt < interval.end })
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
        let all = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.stateRaw == finished }))
        return filter.apply(to: all)
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

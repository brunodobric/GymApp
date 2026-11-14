import Catalog
import Foundation
import Models
import SwiftData

public enum HistorySort: Sendable {
    case newestFirst
    case oldestFirst
}

/// Filter i sortiranje popisa odrađenih treninga. Prazan skup vrsta znači sve vrste, a prazna pretraga sve treninge.
public struct HistoryFilter: Equatable, Sendable {
    public var kinds: Set<WorkoutKind>
    public var sort: HistorySort
    /// Pretraga po nazivu treninga i nazivima vježbi (`matches`).
    public var query: String

    public init(kinds: Set<WorkoutKind> = [], sort: HistorySort = .newestFirst, query: String = "") {
        self.kinds = kinds
        self.sort = sort
        self.query = query
    }

    /// Trening odgovara pretrazi kad se svaka riječ upita nađe u nazivu treninga ili nazivu neke vježbe,
    /// bez obzira na velika slova i dijakritike ("cucanj" pronalazi "Čučanj"). Izbačene vježbe se ne gledaju.
    public static func matches(_ session: Session, query: String) -> Bool {
        let words = ExerciseSearch.normalize(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let names = [session.name] + session.orderedExercises.filter { !$0.isRemoved }.map(\.exerciseName)
        let text = ExerciseSearch.normalize(names.joined(separator: " "))
        return words.allSatisfy { text.contains($0) }
    }

    /// Primjenjuje filter i sortiranje na već učitane treninge (za žive upite u sučelju).
    /// `kindsOf` daje vrste treninga; u sučelju je to `SessionMix.kinds`, pa je trening snage s kardiom
    /// i pod snagom i pod kardiom.
    public func apply(
        to sessions: [Session], kindsOf: (Session) -> Set<WorkoutKind> = { [$0.kind] }
    ) -> [Session] {
        let byKind = kinds.isEmpty ? sessions : sessions.filter { !kinds.isDisjoint(with: kindsOf($0)) }
        let selected = query.isEmpty ? byKind : byKind.filter { Self.matches($0, query: query) }
        return selected.sorted { sort == .newestFirst ? $0.startedAt > $1.startedAt : $0.startedAt < $1.startedAt }
    }

    /// Popis ispod kalendara: treninzi odabranog dana ili, bez odabira, cijelog prikazanog mjeseca.
    public func apply(
        to sessions: [Session], month: Date, day: Date?, calendar: Calendar = .current,
        kindsOf: (Session) -> Set<WorkoutKind> = { [$0.kind] }
    ) -> [Session] {
        let component: Calendar.Component = day == nil ? .month : .day
        guard let interval = calendar.dateInterval(of: component, for: day ?? month) else { return [] }
        return apply(to: sessions.filter { interval.contains($0.startedAt) && $0.startedAt < interval.end }, kindsOf: kindsOf)
    }
}

/// Povijest odrađenih treninga: popis, dani s treningom za kalendar i brisanje.
public struct HistoryQueries {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func sessions(filter: HistoryFilter = HistoryFilter()) throws -> [Session] {
        filter.apply(to: try GymQueries(context: context).allFinishedSessions())
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
    /// Trening uvezen iz Zdravlja briše se iz lokalne baze (u Zdravlju ostaje).
    public func delete(_ session: Session) throws {
        if session.isImportedFromWorkoutsApp {
            try HealthLocalStore(context: context).deleteImported(sessionId: session.id)
            return
        }
        try HealthLocalStore(context: context).deleteValues(forSession: session.id)
        context.delete(session)
        try context.save()
    }
}

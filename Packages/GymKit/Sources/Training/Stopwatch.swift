import Foundation

/// Štoperica za seriju s trajanjem (kardio, izdržaj): pokreni, pauziraj i nastavi. Kvačica upisuje
/// izmjereno vrijeme u seriju. Vrijeme teče iz datuma početka, pa ne treba timer koji kuca svake sekunde.
public struct Stopwatch: Equatable, Sendable {
    /// Serija koju štoperica mjeri.
    public let setID: UUID
    /// Početak trenutnog mjerenja; nil dok je pauzirana.
    public private(set) var runningSince: Date?
    /// Vrijeme izmjereno prije zadnje pauze.
    public private(set) var accumulated: TimeInterval

    public init(setID: UUID, startedAt: Date) {
        self.setID = setID
        self.runningSince = startedAt
        self.accumulated = 0
    }

    public var isRunning: Bool { runningSince != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Izmjereno vrijeme u cijelim sekundama, za upis u seriju.
    public func elapsedSeconds(at now: Date) -> Int {
        Int(elapsed(at: now).rounded())
    }

    /// Trenutak od kojeg brojač koji raste pokazuje izmjereno vrijeme (`Text(date, style: .timer)`).
    public func displayStart(at now: Date) -> Date {
        now.addingTimeInterval(-elapsed(at: now))
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        runningSince = nil
    }

    public mutating func resume(at now: Date) {
        guard !isRunning else { return }
        runningSince = now
    }

    public mutating func toggle(at now: Date) {
        if isRunning { pause(at: now) } else { resume(at: now) }
    }
}

import Foundation

/// Kako se prikazuje službena vježba: animacija od dviju fotografija (početni i završni položaj),
/// jedna fotografija ili ništa.
public enum ExerciseIllustration: Hashable, Sendable {
    /// Putanje fotografija unutar mape kataloga (free-exercise-db): početni i završni položaj
    /// koji se izmjenjuju pretapanjem.
    case animation(start: String, end: String)
    /// Samo jedna fotografija, prikazuje se mirno.
    case photo(String)
    case unavailable
}

extension CatalogExercise {
    /// Prve dvije fotografije čine animaciju. free-exercise-db ima po dvije za svaku vježbu,
    /// a vježba s jednom fotografijom prikazuje je bez animacije.
    public var illustration: ExerciseIllustration {
        switch images.count {
        case 0: .unavailable
        case 1: .photo(images[0])
        default: .animation(start: images[0], end: images[1])
        }
    }
}

/// Ritam animacije: položaj se zadrži, pa se pretopi u drugi, i tako u krug.
public struct PoseLoopTiming: Hashable, Sendable {
    /// Koliko dugo se svaki položaj prikazuje mirno (sekunde).
    public let hold: TimeInterval
    /// Trajanje pretapanja iz jednog položaja u drugi (sekunde).
    public let fade: TimeInterval

    public init(hold: TimeInterval, fade: TimeInterval) {
        self.hold = max(0, hold)
        self.fade = max(0, fade)
    }

    /// Otprilike tempo jednog ponavljanja: oko 1,6 s gore i 1,6 s dolje.
    public static let standard = PoseLoopTiming(hold: 0.9, fade: 0.7)

    /// Trajanje cijelog kruga: početni → završni → početni.
    public var period: TimeInterval { 2 * (hold + fade) }

    /// Neprozirnost završnog položaja (0...1) u trenutku `elapsed` od početka animacije.
    /// Završni položaj crta se preko potpuno vidljivog početnog. Pretapanje je glatko (ease-in-out).
    public func endOpacity(at elapsed: TimeInterval) -> Double {
        guard period > 0 else { return 0 }
        var time = elapsed.truncatingRemainder(dividingBy: period)
        if time < 0 { time += period }
        func eased(_ progress: Double) -> Double {
            let clamped = min(max(progress, 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }
        if time < hold { return 0 }
        time -= hold
        if time < fade { return fade > 0 ? eased(time / fade) : 1 }
        time -= fade
        if time < hold { return 1 }
        time -= hold
        return fade > 0 ? 1 - eased(time / fade) : 0
    }
}

/// Sat animacije koji se može pauzirati: broji samo vrijeme dok animacija teče,
/// pa se nakon pauze nastavlja iz istog položaja umjesto da skoči.
public struct PoseLoopClock: Hashable, Sendable {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    public init() {}

    public var isRunning: Bool { runningSince != nil }

    /// Koliko je animacija tekla do trenutka `date`.
    public func elapsed(at date: Date) -> TimeInterval {
        guard let runningSince else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(runningSince))
    }

    /// Pokreće sat. Ako već teče, ne mijenja ništa.
    public mutating func start(at date: Date) {
        guard runningSince == nil else { return }
        runningSince = date
    }

    /// Zaustavlja sat i pamti dotad proteklo vrijeme. Ako već stoji, ne mijenja ništa.
    public mutating func pause(at date: Date) {
        accumulated = elapsed(at: date)
        runningSince = nil
    }
}

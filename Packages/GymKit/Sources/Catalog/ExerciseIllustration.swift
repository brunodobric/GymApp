import Foundation

/// Kako se prikazuje službena vježba: animirani crtež (dva položaja) ili fotografije.
public enum ExerciseIllustration: Hashable, Sendable {
    /// Crteži iz asset cataloga: početni i završni položaj, izmjenjuju se pretapanjem.
    case drawing(start: String, end: String)
    /// Putanje fotografija unutar mape kataloga (free-exercise-db).
    case photos([String])
    case unavailable
}

extension CatalogExercise {
    /// Crtež ima prednost pred fotografijama. Crtež bez točno dva položaja se ne koristi,
    /// pa vježba tada zadržava fotografije.
    public var illustration: ExerciseIllustration {
        if let drawings, drawings.count == 2 {
            return .drawing(start: drawings[0], end: drawings[1])
        }
        return images.isEmpty ? .unavailable : .photos(images)
    }
}

/// Ritam animacije crteža: položaj se zadrži, pa se pretopi u drugi, i tako u krug.
public struct DrawingLoopTiming: Hashable, Sendable {
    /// Koliko dugo se svaki položaj prikazuje mirno (sekunde).
    public let hold: TimeInterval
    /// Trajanje pretapanja iz jednog položaja u drugi (sekunde).
    public let fade: TimeInterval

    public init(hold: TimeInterval, fade: TimeInterval) {
        self.hold = max(0, hold)
        self.fade = max(0, fade)
    }

    /// Otprilike tempo jednog ponavljanja: oko 1,6 s gore i 1,6 s dolje.
    public static let standard = DrawingLoopTiming(hold: 0.9, fade: 0.7)

    /// Trajanje cijelog kruga: početni → završni → početni.
    public var period: TimeInterval { 2 * (hold + fade) }

    /// Neprozirnost završnog položaja (0...1) u trenutku `elapsed` od početka animacije.
    /// Početni položaj ima neprozirnost `1 - endOpacity`. Pretapanje je glatko (ease-in-out).
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

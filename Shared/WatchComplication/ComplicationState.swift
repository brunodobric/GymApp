import Foundation

/// Što prikazuju complications na satu (specifikacija, odjeljak 6): sljedeći trening ili aktivni odmor.
/// Aplikacija na satu ga zapisuje u zajednički App Group, a widget extension ga čita.
struct ComplicationState: Codable, Equatable {
    var nextWorkoutName: String?
    var nextScheduleName: String?
    /// Naziv treninga u tijeku.
    var activeWorkoutName: String?
    var restStartedAt: Date?
    var restEndsAt: Date?

    static let suiteName = "group.com.brunodobric.gymapp"
    private static let key = "watchComplicationState"

    static func load() -> ComplicationState {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key),
              let state = try? JSONDecoder().decode(ComplicationState.self, from: data) else { return ComplicationState() }
        return state
    }

    /// Sprema stanje. Vraća true ako se promijenilo (tada treba osvježiti complications).
    @discardableResult
    func save() -> Bool {
        guard self != Self.load(), let data = try? JSONEncoder().encode(self) else { return false }
        UserDefaults(suiteName: Self.suiteName)?.set(data, forKey: Self.key)
        return true
    }

    /// Odmor traje u zadanom trenutku.
    func isResting(at date: Date) -> Bool {
        guard let restEndsAt else { return false }
        return restEndsAt > date
    }
}

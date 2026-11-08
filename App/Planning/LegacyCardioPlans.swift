import Foundation
import OSLog
import WorkoutKit

/// Čišćenje nakon izbačenih kardio planova za sat (WorkoutKit).
///
/// Aplikacija je nekad zakazivala kardio planove u aplikaciju Workout na satu. Planovi koje je zakazala
/// ostali bi na satu i nakon ažuriranja, pa se jednom maknu. Aplikacija vidi i miče samo svoje planove.
/// Treninzi u bazi pretvaraju se posebno (`CardioPlanMigration`, iz `AppServices.migrateStoredData`).
@MainActor
enum LegacyCardioPlans {
    private static let doneKey = "cardioPlans.removedFromWatch"

    static func removeFromWatch() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey), WorkoutScheduler.isSupported else { return }
        let scheduler = WorkoutScheduler.shared
        // Bez dozvole aplikacija nije ništa zakazala, a dozvola se više ne traži.
        if await scheduler.authorizationState == .authorized {
            await scheduler.removeAllWorkouts()
            Logger(subsystem: "com.brunodobric.gymapp", category: "WorkoutKit").info("Stari kardio planovi maknuti sa sata")
        }
        defaults.set(true, forKey: doneKey)
    }
}

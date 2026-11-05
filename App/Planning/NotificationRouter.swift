import Foundation
import UIKit
import UserNotifications

/// Dodir na podsjetnik rasporeda otvara pregled sljedećeg treninga tog rasporeda (`UpcomingWorkoutScreen`).
/// Za kardio je to plan s uputom za pokretanje na satu i gumbom za zakazivanje (faza 10).
///
/// Dok je aplikacija otvorena prikazuje se samo obavijest o kraju odmora, i to samo kad ekran treninga
/// nije otvoren (trening je sažet u karticu ili je korisnik na drugom tabu). Ekran treninga sam svira
/// zvuk i vibrira kad odmor istekne. Podsjetnici rasporeda se u prvom planu ne prikazuju.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Raspored čiji pregled treba otvoriti.
    var openScheduleId: UUID?

    /// Postavlja delegata. Mora biti prije kraja pokretanja aplikacije, da stigne i dodir koji ju je pokrenuo.
    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        return await MainActor.run {
            guard identifier == RestNotifications.identifier, !WorkoutScreenPresence.isVisible else { return [] }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return [.banner, .list, .sound]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo[ReminderScheduler.scheduleIdKey] as? String
        guard let id = raw.flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run {
            // Dok je trening otvoren, pregled sljedećeg treninga ne može se prikazati preko njega, pa bi
            // iskočio tek nakon zatvaranja treninga. Korisnik tada već trenira, pa se dodir zanemaruje.
            guard !WorkoutScreenPresence.isVisible else { return }
            openScheduleId = id
        }
    }
}

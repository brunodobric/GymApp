import Foundation
import UserNotifications

/// Dodir na podsjetnik rasporeda otvara pregled sljedećeg treninga tog rasporeda (`UpcomingWorkoutScreen`).
/// Za kardio je to plan s uputom za pokretanje na satu i gumbom za zakazivanje (faza 10).
///
/// Delegat ne implementira prikaz u prvom planu, pa se obavijesti dok je aplikacija otvorena i dalje
/// ne prikazuju (kao i prije, npr. obavijest o kraju odmora).
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
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo[ReminderScheduler.scheduleIdKey] as? String
        guard let id = raw.flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run { openScheduleId = id }
    }
}

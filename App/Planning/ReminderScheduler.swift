import Foundation
import Models
import Planning
import SwiftData
import UserNotifications

/// Zakazuje lokalne podsjetnike rasporeda. Svaki poziv briše stare i zakazuje nove prema stanju u bazi,
/// pa se poziva pri pokretanju, nakon izmjene rasporeda i nakon početka ili kraja treninga.
/// Tijekom aktivnog treninga `ReminderBuilder` vraća prazan popis, pa se podsjetnici otkazuju.
enum ReminderScheduler {
    private static let prefix = "schedule-"
    /// Ključ u `userInfo` obavijesti: raspored čiji se sljedeći trening otvara dodirom.
    static let scheduleIdKey = "scheduleId"

    @MainActor
    static func refresh(context: ModelContext) {
        // Isključene obavijesti u Postavkama: samo se uklanjaju zakazani podsjetnici.
        let enabled = (try? GymQueries(context: context).settings().notificationsEnabled) ?? true
        let reminders = enabled ? ((try? ReminderBuilder(context: context).reminders()) ?? []) : []
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard !reminders.isEmpty else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                // iOS drži najviše 64 zakazane obavijesti; ostavljamo mjesta za timer pauze.
                for reminder in reminders.prefix(50) {
                    center.add(request(for: reminder))
                }
            }
        }
    }

    private static func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.scheduleName
        if let workout = reminder.workoutName {
            content.body = String(localized: "Vrijeme za trening: \(workout)")
        } else {
            content.body = String(localized: "Vrijeme za trening.")
        }
        content.sound = .default
        content.userInfo = [scheduleIdKey: reminder.scheduleId.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
}

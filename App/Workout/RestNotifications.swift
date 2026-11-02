import Foundation
import UserNotifications

/// Lokalna obavijest o kraju pauze. iOS je ne prikazuje dok je aplikacija otvorena
/// (tada rest timer sam svira zvuk), pa stiže samo kad je zaključan ekran ili aplikacija u pozadini.
enum RestNotifications {
    private static let identifier = "rest-timer-end"

    /// Postavlja obavijest za `endsAt`, a bez termina (ili za prošli termin) uklanja postojeću.
    static func sync(endsAt: Date?, soundEnabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let endsAt, endsAt.timeIntervalSinceNow > 1 else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Pauza je gotova")
            content.body = String(localized: "Vrijeme za sljedeću seriju.")
            content.sound = soundEnabled ? UNNotificationSound.default : nil
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: endsAt.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

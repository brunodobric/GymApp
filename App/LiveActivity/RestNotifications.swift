import Foundation
import UserNotifications

/// Lokalna obavijest o kraju odmora. Kad se zakazuje, odlučuje `RestNotificationPolicy` (GymKit).
/// iOS je ne prikazuje dok je aplikacija otvorena (tada rest timer sam svira zvuk), pa stiže kad je iPhone
/// zaključan ili je aplikacija u pozadini.
@MainActor
enum RestNotifications {
    private static let identifier = "rest-timer-end"
    /// Raste sa svakom izmjenom, da zakazivanje koje čeka dopuštenje ne vrati obavijest koju je novija izmjena maknula.
    private static var generation = 0

    /// Zakazuje obavijest za `fireDate`, a bez termina uklanja postojeću. Svaki poziv zamjenjuje
    /// prethodnu obavijest, pa +10 / −10 premješta obavijest na novi trenutak.
    static func schedule(at fireDate: Date?, body: String, soundEnabled: Bool) {
        generation += 1
        let current = generation
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let fireDate, fireDate.timeIntervalSinceNow > 0 else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                guard current == generation else { return }
                // Između poziva i dopuštenja vrijeme teče: interval se računa tek sad.
                let interval = fireDate.timeIntervalSinceNow
                guard interval > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Odmor je gotov")
                content.body = body
                content.sound = soundEnabled ? UNNotificationSound.default : nil
                content.interruptionLevel = .timeSensitive
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
    }

    static func cancel() {
        generation += 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

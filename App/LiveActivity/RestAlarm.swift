import Foundation
import OSLog
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Kraj odmora kao alarm sustava (AlarmKit, iOS 26). Za razliku od obične obavijesti iskoči u Dynamic Islandu
/// (kao tajmer iz aplikacije Sat), a na zaključanom zaslonu preko cijelog zaslona, s gumbom za gašenje.
/// Alarm zvoni i u tihom načinu rada i kroz Fokus, pa se u postavkama može isključiti.
///
/// Kada se koristi umjesto obavijesti, odlučuje `RestEndAlert` (GymKit). Odbrojavanje tijekom odmora i dalje
/// prikazuje Live Activity treninga, pa alarm nema vlastito odbrojavanje (inače bi u Dynamic Islandu bile dvije).
@MainActor
enum RestAlarm {
    /// Uključeno u postavkama (na ovom uređaju, jer alarm postoji samo na iPhoneu). Zadano uključeno.
    nonisolated static let preferenceKey = "restEndAsAlarm"

    /// Stalni ID, pa svako zakazivanje zamjenjuje prethodni alarm.
    private static let alarmID = UUID(uuidString: "7E5A1A57-0D0C-4B4E-9C8B-5E57A1A2B0D1")!
    private static let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "RestAlarm")

    static var isPreferred: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// Sustav nudi alarme (iOS 26) i korisnik ih je dopustio.
    static var isAvailable: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return false
    }

    /// Sustav nudi alarme, bez obzira na dopuštenje (za prikaz prekidača u postavkama).
    static var isSupported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Trenutak zakazanog alarma, da se isti alarm ne zakazuje iznova pri svakom osvježavanju.
    /// Na početku nepoznat (`distantPast`), jer je alarm mogao ostati od prethodnog pokretanja aplikacije.
    private static var scheduledDate: Date? = .distantPast

    /// Upit za dopuštenje je na ekranu, da se ne prikaže dvaput.
    private static var isRequestingAuthorization = false

    /// Pita za dopuštenje ako još nije pitano, bez čekanja odgovora. Samo dok je aplikacija otvorena:
    /// u pozadini se upit ne može prikazati.
    static func requestAuthorizationIfNeeded() {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *), isPreferred, !isRequestingAuthorization,
              AlarmManager.shared.authorizationState == .notDetermined else { return }
        isRequestingAuthorization = true
        Task {
            do {
                _ = try await AlarmManager.shared.requestAuthorization()
            } catch {
                logger.info("Dopuštenje za alarme nije dobiveno: \(error.localizedDescription)")
            }
            isRequestingAuthorization = false
        }
        #endif
    }

    /// Zakazuje alarm za `fireDate`, a bez termina uklanja postojeći. Pozivi idu jedan za drugim
    /// (`WorkoutLiveUpdates` ih slaže u red), pa se dva zakazivanja ne preklapaju.
    static func schedule(at fireDate: Date?, accent: String?) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        let manager = AlarmManager.shared
        let fireDate = fireDate.flatMap { $0.timeIntervalSinceNow > 0 && isAvailable ? $0 : nil }
        guard fireDate != scheduledDate else { return }
        if scheduledDate != nil {
            // Alarm je možda već zazvonio i ugašen, pa se greška zanemaruje.
            try? manager.cancel(id: alarmID)
            scheduledDate = nil
        }
        guard let fireDate else { return }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("Odmor je gotov"),
            stopButton: AlarmButton(text: LocalizedStringResource("U redu"), textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<RestAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: RestAlarmMetadata(),
            tintColor: RestTimerActivityAttributes.ContentState.accentColor(accent)
        )
        do {
            _ = try await manager.schedule(
                id: alarmID,
                configuration: .alarm(schedule: .fixed(fireDate), attributes: attributes)
            )
            scheduledDate = fireDate
        } catch {
            logger.error("Alarm kraja odmora nije zakazan: \(error.localizedDescription)")
        }
        #endif
    }
}

#if canImport(AlarmKit)
/// Alarm kraja odmora ne nosi dodatne podatke.
@available(iOS 26.0, *)
struct RestAlarmMetadata: AlarmMetadata {}
#endif

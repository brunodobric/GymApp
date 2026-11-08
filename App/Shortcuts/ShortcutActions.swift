import AppIntents
import Foundation
import Models
import OSLog
import Planning
import Stats
import SwiftData
import Units

/// Greške akcija iz Prečaca. Sustav prikazuje tekst greške u Prečacima ili ga Siri izgovori.
enum ShortcutIntentError: Error, CustomLocalizedStringResourceConvertible {
    case templateUnavailable
    case invalidWeight
    case needsOnboarding
    case failed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .templateUnavailable: "Taj trening više ne postoji ili nema vježbi."
        case .invalidWeight: "Težina mora biti između 20 i 400 kg."
        case .needsOnboarding: "Prvo otvori aplikaciju i dovrši uvod."
        case .failed: "Radnja nije uspjela. Pokušaj u aplikaciji."
        }
    }
}

/// Izvedba akcija iz Prečaca, Sirija i Action buttona u procesu aplikacije. Pravila su u GymKitu
/// (`WorkoutShortcuts`, `BodyTracking.addShortcutWeight`), a ovdje se javlja promjena satu, Live Activityju,
/// podsjetnicima i Zdravlju, kao kad se ista radnja napravi na ekranu.
@MainActor
enum ShortcutActions {
    private static let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "Shortcuts")

    /// Baza za akciju. Kad se baza na uređaju nije otvorila, aplikacija radi s privremenom bazom u memoriji
    /// (`AppServices.storeOpenError`): tada akcija javlja grešku, jer bi se upis izgubio.
    private static func makeContext() throws -> ModelContext {
        AppServices.start()
        guard AppServices.storeOpenError == nil else { throw ShortcutIntentError.failed }
        return AppServices.container.mainContext
    }

    /// Treninzi koje akcija nudi za odabir.
    static func templates() -> [WorkoutTemplateEntity] {
        guard let context = try? makeContext() else { return [] }
        let found = (try? WorkoutShortcuts(context: context).startableTemplates()) ?? []
        return found.map { WorkoutTemplateEntity(id: $0.id, name: $0.name) }
    }

    /// Treninzi po id-u, i oni koji se više ne mogu pokrenuti: spremljeni prečac tada dobiva jasnu grešku
    /// iz `startWorkout` umjesto općenite greške sustava da trening nije pronađen.
    static func templates(ids: [UUID]) -> [WorkoutTemplateEntity] {
        guard let context = try? makeContext(),
              let all = try? context.fetch(FetchDescriptor<WorkoutTemplate>()) else { return [] }
        let wanted = Set(ids)
        return all.filter { wanted.contains($0.id) }.map { WorkoutTemplateEntity(id: $0.id, name: $0.name) }
    }

    /// Jedinica težine iz postavki, bez stvaranja postavki (`GymQueries.settings()` bi ih stvorio prije onboardinga).
    private static func settings(in context: ModelContext) -> UserSettings? {
        UserSettings.preferred(in: (try? context.fetch(FetchDescriptor<UserSettings>())) ?? [])
    }

    static func startWorkout(templateId: UUID?) throws -> LocalizedStringResource {
        try handle {
            try $0.start(templateId: templateId, emptyName: String(localized: "Trening"))
        }
    }

    static func startNextScheduled() throws -> LocalizedStringResource {
        try handle { try $0.startNextScheduled() }
    }

    static func finishWorkout() async throws -> LocalizedStringResource {
        let context = try makeContext()
        let result: ShortcutFinishResult
        do {
            result = try WorkoutShortcuts(context: context).finishActive()
        } catch {
            logger.error("Trening iz Prečaca nije završen: \(String(describing: error))")
            throw ShortcutIntentError.failed
        }
        switch result {
        case .noActiveWorkout:
            return "Nijedan trening nije u tijeku."
        case .ledByWatch:
            return "Trening vodi Apple Watch. Završi ga na satu."
        case .nothingCompleted:
            return "Trening još nema nijednu završenu seriju, pa se ne može spremiti."
        case .finished(let session):
            // Sat dobiva završnu snimku, Live Activity se gasi, a podsjetnici se zakazuju iznova.
            PhoneWatchSync.shared.sessionChangedNow(session)
            ReminderScheduler.refresh(context: context)
            await WorkoutLiveUpdates.shared.refreshAndWait()
            await HealthService.shared.saveWorkout(of: session, context: context)
            return "Trening \(session.name) je spremljen."
        }
    }

    static func logBodyWeight(_ value: Double) throws -> LocalizedStringResource {
        let context = try makeContext()
        let unit = settings(in: context)?.weightUnit ?? .kilograms
        let kilograms = WeightConversion.kilograms(from: value, in: unit)
        do {
            try BodyTracking(context: context).addShortcutWeight(kilograms: kilograms)
        } catch BodyTrackingError.invalidValue {
            throw ShortcutIntentError.invalidWeight
        } catch {
            logger.error("Težina iz Prečaca nije spremljena: \(String(describing: error))")
            throw ShortcutIntentError.failed
        }
        let text = WeightFormatter(unit: unit).string(fromKilograms: kilograms)
        return "Težina \(text) je spremljena."
    }

    /// Zajednički dio pokretanja: trening u tijeku ili novi trening otvara se na ekranu.
    private static func handle(_ action: (WorkoutShortcuts) throws -> ShortcutStartResult) throws -> LocalizedStringResource {
        let context = try makeContext()
        // Prije uvoda aplikacija prikazuje onboarding preko cijelog zaslona, pa se trening ne bi mogao otvoriti.
        let hasActive = (try? GymQueries(context: context).activeSession()) != nil
        if !hasActive, !(settings(in: context)?.onboardingCompleted ?? false) {
            throw ShortcutIntentError.needsOnboarding
        }
        let result: ShortcutStartResult
        do {
            result = try action(WorkoutShortcuts(context: context))
        } catch ShortcutError.templateUnavailable {
            throw ShortcutIntentError.templateUnavailable
        } catch {
            logger.error("Trening iz Prečaca nije pokrenut: \(String(describing: error))")
            throw ShortcutIntentError.failed
        }
        switch result {
        case .alreadyActive(let session):
            IntentRouter.shared.openActiveWorkout()
            return "Trening \(session.name) je već u tijeku."
        case .started(let session):
            ReminderScheduler.refresh(context: context)
            PhoneWatchSync.shared.sessionStarted(session)
            WorkoutLiveUpdates.shared.refresh()
            IntentRouter.shared.openActiveWorkout()
            return "Trening \(session.name) je započet."
        case .nothingScheduled:
            return "Nemaš aktivan raspored sa sljedećim treningom."
        }
    }
}

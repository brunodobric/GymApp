import Models
import OSLog
import Planning
import SwiftData
import Training

/// Što se događa nakon završetka ili odbacivanja treninga, na jednom mjestu: sat, Live Activity,
/// raspored, podsjetnici i Zdravlje. Prije je to bilo napisano na pet mjesta, svako s drugim dijelom
/// posla (zaboravljeni trening zatvoren s Početne nije pomicao raspored).
///
/// Prečaci (`ShortcutActions.finishWorkout`) rade isto, ali čekaju svaki korak jer radnja traje u pozadini.
@MainActor
enum WorkoutLifecycle {
    /// Tko je trening završio.
    enum Origin {
        /// Na iPhoneu: ekran treninga ili zatvaranje zaboravljenog treninga.
        case phone
        /// Trening koji vodi iPhone završen je naredbom sa sata. Sat već ima završnu snimku.
        case watchCommand
        /// Trening koji vodi sat: sat ga je već spremio u Zdravlje.
        case watch
    }

    private static let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "Workout")

    /// Trening je spremljen kao završen (`WorkoutEngine.finishSession` ili snimka sa sata).
    static func finished(_ session: Session, context: ModelContext, origin: Origin) {
        switch origin {
        case .phone:
            // Sat dobiva završetak (vodi li trening sat) ili završnu snimku (vodi li ga iPhone), a s njom i novi kontekst.
            PhoneWatchSync.shared.sessionChanged(session)
        case .watchCommand, .watch:
            PhoneWatchSync.shared.refreshContext()
        }
        // Live Activity se gasi, a obavijest o kraju odmora otkazuje.
        WorkoutLiveUpdates.shared.refresh()
        // Raspored napreduje samo ako je ovo bio njegov sljedeći trening; podsjetnici se zakazuju iznova.
        do {
            _ = try ScheduleEngine(context: context).sessionFinished(session)
        } catch {
            logger.error("Napredak rasporeda nakon treninga: \(String(describing: error))")
        }
        ReminderScheduler.refresh(context: context)
        if origin != .watch {
            Task { await HealthService.shared.saveWorkout(of: session, context: context) }
        }
    }

    /// Odbacuje trening s iPhonea (ekran treninga ili ponuda za oporavak na Početnoj).
    static func discard(_ session: Session, context: ModelContext) {
        // Sat mora dobiti odbacivanje prije brisanja, jer se poslije ne zna što je bilo.
        PhoneWatchSync.shared.willDiscard(session)
        do {
            try WorkoutEngine(context: context).discardSession(session)
        } catch {
            logger.error("Odbacivanje treninga: \(String(describing: error))")
        }
        WorkoutLiveUpdates.shared.refresh()
        ReminderScheduler.refresh(context: context)
    }
}

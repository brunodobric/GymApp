import Connectivity
import Foundation
import Models
import OSLog
import SwiftData
import Training
import Units

/// Izvedba gumba iz Live Activityja (`CompleteSetIntent`, `AdjustSetValueIntent`) u procesu aplikacije.
enum LiveActivityActions {
    private static let logger = Logger(subsystem: "com.brunodobric.gymapp", category: "LiveActivity")

    /// Označava seriju završenom kao da je kvačica pritisnuta na ekranu treninga: pokreće odmor,
    /// javlja promjenu satu i osvježava Live Activity i obavijest o kraju odmora.
    @MainActor
    static func completeSet(id: String) async {
        AppServices.start()
        let context = AppServices.container.mainContext
        guard let setID = UUID(uuidString: id),
              let set = try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == setID })).first,
              let session = set.exercise?.session, session.state == .active, !set.isCompleted else {
            // Serija je u međuvremenu promijenjena (npr. na satu): Live Activity samo dobiva novo stanje.
            await WorkoutLiveUpdates.shared.refreshAndWait()
            return
        }
        let restSeconds = (try? GymQueries(context: context).settings())?.defaultRestSeconds ?? 90
        do {
            try WorkoutEngine(context: context).completeSet(set, defaultRestSeconds: restSeconds)
        } catch {
            logger.error("Serija iz Live Activityja nije potvrđena: \(String(describing: error))")
        }
        PhoneWatchSync.shared.sessionChangedNow(session)
        await WorkoutLiveUpdates.shared.refreshAndWait()
    }

    /// Gumb − ili + uz vrijednost sljedeće serije: mijenja je kao da je upisana na ekranu treninga
    /// i javlja promjenu satu. Odmor se ne dira.
    @MainActor
    static func adjustSet(id: String, field rawField: String, steps: Int) async {
        AppServices.start()
        let context = AppServices.container.mainContext
        guard let setID = UUID(uuidString: id), let field = WatchSetField(rawValue: rawField),
              let set = try? context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == setID })).first,
              let session = set.exercise?.session, session.state == .active, !set.isCompleted else {
            await WorkoutLiveUpdates.shared.refreshAndWait()
            return
        }
        let unit = (try? GymQueries(context: context).settings())?.weightUnit ?? .kilograms
        if LiveSetEditor.adjust(set, field: field, steps: steps.signum(), unit: unit) {
            do {
                try WorkoutEngine(context: context).touch(session)
            } catch {
                logger.error("Vrijednost serije iz Live Activityja nije spremljena: \(String(describing: error))")
            }
            PhoneWatchSync.shared.sessionChangedNow(session)
        }
        await WorkoutLiveUpdates.shared.refreshAndWait()
    }
}

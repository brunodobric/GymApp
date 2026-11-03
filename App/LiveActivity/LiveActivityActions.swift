import Foundation
import Models
import OSLog
import SwiftData
import Training

/// Izvedba gumba iz Live Activityja (`CompleteSetIntent`) u procesu aplikacije.
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
}

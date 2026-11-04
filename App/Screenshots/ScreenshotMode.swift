#if DEBUG
import Demo
import Foundation
import Models
import OSLog
import Planning
import SwiftData

/// Način za snimke zaslona za App Store (`scripts/snimke-zaslona.sh`, UI test `ScreenshotTests`).
/// Pokreće se argumentom `-ScreenshotMode`: baza je samo u memoriji i puni se demo podacima, bez
/// iClouda, Zdravlja i obavijesti, pa snimke ne ovise o podacima na simulatoru i ne diraju ih.
enum ScreenshotMode {
    static let argument = "-ScreenshotMode"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try GymPersistence.makeUserContainer(storage: .inMemory)
        } catch {
            fatalError("Baza za snimke zaslona se nije mogla otvoriti: \(error)")
        }
    }

    /// Puni bazu na jeziku sučelja: nazivi programa i treninga iz String Cataloga, vježbe iz kataloga.
    @MainActor
    static func populate(_ container: ModelContainer) {
        let catalogStore = CatalogStore()
        let program = ProgramLibrary.all.first { $0.id == DemoDataGenerator.programId }
        do {
            try DemoDataGenerator(context: container.mainContext).populate(
                scheduleName: program?.title,
                workoutName: \.title
            ) { id in
                catalogStore.catalog?.exercise(withID: id)?.displayName(language: catalogStore.language) ?? id
            }
        } catch {
            Logger(subsystem: "com.brunodobric.gymapp", category: "Screenshots")
                .error("Demo podaci: \(String(describing: error))")
        }
    }
}
#endif

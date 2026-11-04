import Models
import SwiftData
import SwiftUI

@main
struct GymApp: App {
    @State private var catalogStore = CatalogStore()

    init() {
        // Otvaranje baze i pokretanje veza, dio vremena pokretanja (MetricKit ga mjeri i kao cjelinu).
        PerformanceSignpost.measure("AppServicesStart") { AppServices.start() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalogStore)
        }
        .modelContainer(AppServices.container)
        .commands { AppCommands() }

        // Dodatni prozori na iPadu: trening iz povijesti i vježba iz kataloga.
        WindowGroup("Trening", id: DetailWindow.session, for: UUID.self) { $sessionId in
            SessionWindow(sessionId: sessionId)
                .environment(catalogStore)
        }
        .modelContainer(AppServices.container)

        WindowGroup("Vježba", id: DetailWindow.exercise, for: String.self) { $summaryId in
            ExerciseWindow(summaryId: summaryId)
                .environment(catalogStore)
        }
        .modelContainer(AppServices.container)
    }
}

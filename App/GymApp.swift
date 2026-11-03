import Models
import SwiftData
import SwiftUI

@main
struct GymApp: App {
    @State private var catalogStore = CatalogStore()

    init() {
        AppServices.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalogStore)
        }
        .modelContainer(AppServices.container)
    }
}

import Connectivity
import Foundation
import Training
import WidgetKit

/// Stanje sata u datoteci (JSON), da kontekst i trening prežive gašenje aplikacije.
enum WatchStateFile {
    struct State: Codable {
        var context: WatchContextPayload
        var active: SessionSnapshot?
        var mirrorBase: SessionSnapshot?
        /// Trening koji vodi iPhone za koji sat drži sesiju u Zdravlju. Opcionalno, pa se čita i starija datoteka.
        var mirrorHealthSessionID: UUID?
    }

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "watch-state.json")
    }

    static func save(_ state: State) throws {
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try SnapshotStorage.encode(state).write(to: url, options: .atomic)
    }

    static func load() -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SnapshotStorage.decode(State.self, from: data)
    }
}

extension ComplicationState {
    /// Complications prikazuju sljedeći trening, trening u tijeku i odmor; osvježavaju se samo kad se to promijeni.
    static func update(context: WatchContextPayload, active: SessionSnapshot?, restTimer: RestTimer?) {
        let next = context.upcoming.first
        let timer = restTimer.flatMap { $0.isExpired(at: Date()) ? nil : $0 }
        let state = ComplicationState(
            nextWorkoutName: next?.name, nextScheduleName: next?.scheduleName, activeWorkoutName: active?.name,
            restStartedAt: timer?.startedAt, restEndsAt: timer?.endsAt
        )
        if state.save() { WidgetCenter.shared.reloadAllTimelines() }
    }
}

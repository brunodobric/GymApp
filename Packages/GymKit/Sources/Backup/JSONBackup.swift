import Foundation
import Models
import SwiftData

/// Puna sigurnosna kopija svih korisničkih podataka u JSON-u. Katalog vježbi nije uključen (dolazi s aplikacijom).
/// Treninzi u tijeku i odbačeni treninzi se ne izvoze.
public enum JSONBackup {
    public static let format = "gymapp-backup"
    public static let version = 1

    public static func export(from context: ModelContext, now: Date = Date()) throws -> Data {
        let finished = SessionState.finished.rawValue
        let sessions = try context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.stateRaw == finished }, sortBy: [SortDescriptor(\.startedAt)]
        ))
        let file = BackupFile(
            format: format, version: version, exportedAt: now,
            settings: UserSettings.preferred(in: try context.fetch(FetchDescriptor<UserSettings>())).map(SettingsDTO.init),
            customExercises: try context.fetch(FetchDescriptor<CustomExercise>())
                .sorted { $0.id.uuidString < $1.id.uuidString }.map(CustomExerciseDTO.init),
            templates: try context.fetch(FetchDescriptor<WorkoutTemplate>())
                .sorted { $0.id.uuidString < $1.id.uuidString }.map(TemplateDTO.init),
            schedules: try context.fetch(FetchDescriptor<Schedule>())
                .sorted { $0.id.uuidString < $1.id.uuidString }.map(ScheduleDTO.init),
            cycleOverrides: try context.fetch(FetchDescriptor<CycleOverride>())
                .sorted { $0.id.uuidString < $1.id.uuidString }.map(CycleOverrideDTO.init),
            sessions: sessions.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
                .map(SessionDTO.init),
            measurements: try context.fetch(FetchDescriptor<BodyMeasurement>())
                .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }.map(MeasurementDTO.init),
            dashboardCards: try context.fetch(FetchDescriptor<DashboardCard>())
                .sorted { ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString) }
                .map(DashboardCardDTO.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Uvozi sigurnosnu kopiju. Zapisi čiji `id` već postoji se preskaču. Postavke se uvijek preuzimaju iz datoteke.
    @discardableResult
    public static func importBackup(_ data: Data, into context: ModelContext) throws -> BackupImportResult {
        let file: BackupFile
        do {
            file = try JSONDecoder().decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unsupportedFormat
        }
        guard file.format == format else { throw BackupError.unsupportedFormat }
        guard file.version <= version else { throw BackupError.newerVersion(file.version) }

        var result = BackupImportResult()
        if let settings = file.settings {
            settings.apply(to: try GymQueries(context: context).settings())
        }
        func existing<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) throws -> Set<UUID> {
            Set(try context.fetch(FetchDescriptor<T>()).map { $0[keyPath: id] })
        }

        /// Uvozi zapise čiji `id` još ne postoji; ostale preskače.
        func importAll<T: PersistentModel, D>(
            _ items: [D], model: T.Type, id: KeyPath<T, UUID>, itemID: (D) -> UUID, insert: (D) -> Void
        ) throws {
            var known = try existing(model, id: id)
            for item in items {
                if known.insert(itemID(item)).inserted {
                    insert(item)
                    result.added += 1
                } else {
                    result.skipped += 1
                }
            }
        }

        try importAll(file.customExercises, model: CustomExercise.self, id: \.id, itemID: \.id) {
            context.insert($0.make())
        }
        try importAll(file.templates, model: WorkoutTemplate.self, id: \.id, itemID: \.id) {
            _ = $0.make(in: context)
        }
        try importAll(file.schedules, model: Schedule.self, id: \.id, itemID: \.id) {
            _ = $0.make(in: context)
        }
        try importAll(file.cycleOverrides, model: CycleOverride.self, id: \.id, itemID: \.id) {
            context.insert($0.make())
        }
        try importAll(file.sessions, model: Session.self, id: \.id, itemID: \.id) {
            _ = $0.make(in: context)
        }
        try importAll(file.measurements, model: BodyMeasurement.self, id: \.id, itemID: \.id) {
            context.insert($0.make())
        }
        try importAll(file.dashboardCards, model: DashboardCard.self, id: \.id, itemID: \.id) {
            context.insert($0.make())
        }
        try context.save()
        return result
    }
}

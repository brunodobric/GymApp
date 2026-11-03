import Foundation
import Models
import SwiftData

/// "Obriši sve podatke": briše sve korisničke zapise na uređaju. Postavke se brišu zadnje i ponovno nastaju kao zadane.
/// Podatke u iCloudu aplikacija briše prije ovoga (vidi `DataResetScope`).
public enum DataReset {
    public static func deleteAll(in context: ModelContext) throws {
        // Djeca se brišu izričito, da ne ovisimo o ponašanju skupnog brisanja s relacijama.
        try context.delete(model: SetLog.self)
        try context.delete(model: SessionExercise.self)
        try context.delete(model: Session.self)
        try context.delete(model: TemplateSet.self)
        try context.delete(model: TemplateExercise.self)
        try context.delete(model: ScheduleItem.self)
        try context.delete(model: WorkoutTemplate.self)
        try context.delete(model: Schedule.self)
        try context.delete(model: CycleOverride.self)
        try context.delete(model: CustomExercise.self)
        try context.delete(model: BodyMeasurement.self)
        try context.delete(model: DashboardCard.self)
        try context.delete(model: UserSettings.self)
        try context.save()
    }
}

/// Što "Obriši sve podatke" briše, s obzirom na sinkronizaciju.
public enum DataResetScope: Equatable, Sendable {
    /// Sinkronizacija ne radi: brišu se samo podaci na uređaju.
    case deviceOnly
    /// Prvo se brišu podaci u iCloudu, zatim na uređaju.
    case deviceAndCloud
    /// Sinkronizacija radi, ali iCloud nije dostupan. Brisanje bi ostavilo podatke u iCloudu,
    /// a oni bi se vratili na uređaj, pa se ništa ne briše.
    case cloudUnavailable

    public static func resolve(isSyncRunning: Bool, account: CloudAccountState?) -> DataResetScope {
        guard isSyncRunning else { return .deviceOnly }
        return account == .available ? .deviceAndCloud : .cloudUnavailable
    }
}

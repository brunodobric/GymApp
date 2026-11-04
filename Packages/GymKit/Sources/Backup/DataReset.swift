import Foundation
import Models
import SwiftData

/// "Obriši sve podatke": briše sve korisničke zapise na uređaju. Postavke se brišu zadnje i ponovno nastaju kao zadane.
/// Podatke u iCloudu aplikacija briše prije ovoga (vidi `DataResetScope`).
public enum DataReset {
    public static func deleteAll(in context: ModelContext) throws {
        // Djeca se brišu izričito i prva, da ne ovisimo o kaskadnom brisanju relacija.
        try context.deleteEvery(SetLog.self)
        try context.deleteEvery(SessionExercise.self)
        try context.deleteEvery(Session.self)
        try context.deleteEvery(TemplateSet.self)
        try context.deleteEvery(TemplateExercise.self)
        try context.deleteEvery(ScheduleItem.self)
        try context.deleteEvery(WorkoutTemplate.self)
        try context.deleteEvery(Schedule.self)
        try context.deleteEvery(CycleOverride.self)
        try context.deleteEvery(CustomExercise.self)
        try context.deleteEvery(BodyMeasurement.self)
        try context.deleteEvery(DashboardCard.self)
        try context.deleteEvery(UserSettings.self)
        // Lokalna baza podataka iz Zdravlja (u Zdravlju sve ostaje).
        try context.deleteEvery(HealthWorkout.self)
        try context.deleteEvery(HealthMeasurement.self)
        try context.deleteEvery(SessionHealthData.self)
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

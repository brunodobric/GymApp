import Foundation
import SwiftData

/// Pretvara nekadašnje kardio planove za sat u obične treninge s vježbama.
///
/// Aplikacija je nekad imala posebnu vrstu treninga (`WorkoutKind.cardio` s planom u `cardioPlanRaw`)
/// koja se preko WorkoutKita zakazivala u aplikaciju Workout na satu. Ta je mogućnost izbačena:
/// svi treninzi slažu se od vježbi, a kardio je kardio vježba u treningu. Postojeći plan postaje
/// trening istog naziva bez vježbi, pa stavke rasporeda koje na njega upućuju ostaju na mjestu,
/// a korisnik mu doda vježbe ili ga obriše.
///
/// Migracija je idempotentna: pokreće se pri pokretanju, nakon uvoza i nakon sinkronizacije,
/// jer plan sa starog uređaja ili iz sigurnosne kopije može stići kasnije.
public enum CardioPlanMigration {
    /// Vraća broj pretvorenih treninga.
    @discardableResult
    public static func migrate(in context: ModelContext) throws -> Int {
        let plans = try context.fetch(FetchDescriptor<WorkoutTemplate>()).filter { $0.kind == .cardio }
        guard !plans.isEmpty else { return 0 }
        for template in plans {
            template.kind = .strength
            template.cardioPlanRaw = nil
        }
        try context.save()
        return plans.count
    }
}

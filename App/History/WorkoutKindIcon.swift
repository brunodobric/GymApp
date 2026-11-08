import Catalog
import Models
import Stats
import SwiftUI
import Training

// Vrsta treninga za prikaz (`SessionMix`): snaga, kardio ili snaga s kardiom. Računa se iz vježbi
// (`SessionCardio.mix`), pa je ista ikona svugdje gdje se trening prikazuje: povijest, Početna,
// rasporedi, popis treninga i izbor treninga.

extension SessionMix {
    var title: LocalizedStringResource {
        switch self {
        case .strength: "Snaga"
        case .cardio: "Kardio"
        case .mixed: "Snaga + kardio"
        }
    }
}

/// Ikona vrste treninga. Snaga je bučica, kardio trčanje (ili aktivnost kardio plana za sat), a snaga
/// s kardiom bučica s malom oznakom trčanja u kutu.
struct WorkoutKindIcon: View {
    let mix: SessionMix
    /// Simbol aktivnosti kardio plana (npr. bicikl); bez njega trčanje.
    var cardioSymbol: String?

    var body: some View {
        switch mix {
        case .strength:
            Image(systemName: WorkoutKind.strength.symbol)
        case .cardio:
            Image(systemName: cardioSymbol ?? WorkoutKind.cardio.symbol)
        case .mixed:
            Image(systemName: WorkoutKind.strength.symbol)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.caption2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .background(Circle().fill(.background).padding(-1))
                        .offset(x: 6, y: 6)
                }
        }
    }
}

extension CatalogStore {
    /// Je li vježba kardio, po ključu `ExerciseRef.key` (katalog i vlastite vježbe).
    func isCardio(custom: [CustomExercise]) -> (String) -> Bool {
        ExerciseInfoBuilder.isCardio(ExerciseInfoBuilder.provider(catalog: catalog, custom: custom))
    }
}

extension WorkoutTemplate {
    /// Simbol aktivnosti kardio plana za sat; nil za trening s vježbama.
    var cardioPlanSymbol: String? {
        kind == .cardio ? (cardioPlan?.activity.symbol ?? WorkoutKind.cardio.symbol) : nil
    }
}

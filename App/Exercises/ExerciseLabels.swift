import Catalog
import Foundation

// Nazivi za prikaz. Ključevi u katalogu ostaju engleski, a tekst ide kroz lokalizaciju.

extension ExerciseCategory {
    var title: LocalizedStringResource {
        switch self {
        case .chest: "Prsa"
        case .back: "Leđa"
        case .shoulders: "Ramena"
        case .arms: "Ruke"
        case .legs: "Noge"
        case .core: "Trbuh"
        case .cardio: "Kardio"
        }
    }
}

extension Muscle {
    var title: LocalizedStringResource {
        switch self {
        case .chest: "Prsa"
        case .shoulders: "Ramena"
        case .triceps: "Triceps"
        case .biceps: "Biceps"
        case .forearms: "Podlaktice"
        case .lats: "Široki leđni"
        case .middleBack: "Sredina leđa"
        case .lowerBack: "Donja leđa"
        case .traps: "Trapez"
        case .neck: "Vrat"
        case .quadriceps: "Prednja loža"
        case .hamstrings: "Stražnja loža"
        case .glutes: "Gluteusi"
        case .calves: "Listovi"
        case .adductors: "Nutarnja strana bedra"
        case .abductors: "Vanjska strana bedra"
        case .abdominals: "Trbušni mišići"
        }
    }
}

extension Equipment {
    var title: LocalizedStringResource {
        switch self {
        case .barbell: "Šipka"
        case .ezBar: "EZ šipka"
        case .dumbbell: "Bučice"
        case .cable: "Kablovi"
        case .machine: "Sprava"
        case .bodyweight: "Vlastita težina"
        case .kettlebell: "Kettlebell"
        case .bands: "Trake"
        case .other: "Ostalo"
        }
    }
}

extension Level {
    var title: LocalizedStringResource {
        switch self {
        case .beginner: "Početnik"
        case .intermediate: "Srednja razina"
        case .advanced: "Napredno"
        }
    }
}

extension Mechanic {
    var title: LocalizedStringResource {
        switch self {
        case .compound: "Složena"
        case .isolation: "Izolacijska"
        }
    }
}

extension ExerciseInputType {
    var title: LocalizedStringResource {
        switch self {
        case .weightReps: "Težina × ponavljanja"
        case .bodyweight: "Vlastita težina"
        case .weightedBodyweight: "Vlastita težina + teret"
        case .assisted: "Potpomognuta"
        case .duration: "Trajanje"
        case .durationDistance: "Trajanje + udaljenost"
        }
    }
}

extension [Muscle] {
    /// "Prsa i triceps" ili "Prsa, triceps i ramena", prema jeziku uređaja.
    var formattedList: String {
        map { String(localized: $0.title) }.formatted(.list(type: .and))
    }
}

extension ExerciseSearchLabels {
    /// Nazivi kakve korisnik vidi u aplikaciji, za pretragu po kategoriji, mišiću i opremi.
    static let app = ExerciseSearchLabels(
        category: { String(localized: $0.title) },
        muscle: { String(localized: $0.title) },
        equipment: { String(localized: $0.title) }
    )
}

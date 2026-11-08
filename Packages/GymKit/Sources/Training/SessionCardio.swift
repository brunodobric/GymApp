import Foundation
import Models

/// Kako trening izgleda u povijesti: snaga, kardio ili snaga s kardio dijelom.
/// Ne sprema se: računa se iz vježbi, pa vrijedi i za treninge odrađene prije ove podjele.
public enum SessionMix: Equatable, Sendable {
    case strength
    case cardio
    /// Trening snage s barem jednom odrađenom kardio vježbom (npr. bicikl za zagrijavanje).
    case mixed

    /// Vrste pod kojima se trening nalazi u filteru povijesti. Mješoviti trening je u obje.
    public var kinds: Set<WorkoutKind> {
        switch self {
        case .strength: [.strength]
        case .cardio: [.cardio]
        case .mixed: [.strength, .cardio]
        }
    }
}

/// Kardio dio jednog treninga: zbroj odrađenih serija kardio vježbi.
public struct CardioPart: Equatable, Sendable {
    public var seconds: Int
    /// Ukupna udaljenost; nil kad ni jedna serija nema udaljenost.
    public var meters: Double?

    public init(seconds: Int, meters: Double? = nil) {
        self.seconds = seconds
        self.meters = meters
    }
}

/// Kardio vježbe unutar treninga snage. Koja je vježba kardio, zna katalog (`ExerciseKind.cardio`),
/// pa pozivatelj daje `isCardio` po ključu `ExerciseRef.key` (`ExerciseInfoBuilder.isCardio`).
public enum SessionCardio {

    /// Odrađene vježbe: nisu izbačene i imaju barem jednu seriju s kvačicom.
    private static func doneExercises(in session: Session) -> [SessionExercise] {
        session.orderedExercises.filter { exercise in
            !exercise.isRemoved && exercise.orderedSets.contains(where: \.isCompleted)
        }
    }

    /// Zbroj odrađenih kardio vježbi treninga; nil kad ih nema (npr. trening snage bez kardija ili kardio
    /// uvezen iz Zdravlja, koji nema vježbe).
    public static func part(of session: Session, isCardio: (String) -> Bool) -> CardioPart? {
        let cardio = doneExercises(in: session).filter { isCardio($0.exerciseKey) }
        guard !cardio.isEmpty else { return nil }
        let sets = cardio.flatMap(\.orderedSets).filter(\.isCompleted)
        let seconds = sets.reduce(0) { $0 + max(0, $1.durationSeconds ?? 0) }
        let distances = sets.compactMap(\.distanceMeters).filter { $0 > 0 }
        return CardioPart(seconds: seconds, meters: distances.isEmpty ? nil : distances.reduce(0, +))
    }

    /// Vrsta za prikaz. Trening snage u kojem su odrađene samo kardio vježbe prikazuje se kao kardio.
    public static func mix(of session: Session, isCardio: (String) -> Bool) -> SessionMix {
        guard session.kind == .strength else { return .cardio }
        let done = doneExercises(in: session)
        let cardio = done.filter { isCardio($0.exerciseKey) }.count
        if cardio == 0 { return .strength }
        return cardio == done.count ? .cardio : .mixed
    }
}

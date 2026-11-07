import Foundation

/// Rekordi jedne vježbe u jednom treningu, za izbor istaknutih rekorda.
public struct RecordCandidate: Equatable, Sendable {
    public let exerciseKey: String
    public let exerciseName: String
    public let records: [PersonalRecord]
    /// Je li vježba složena (katalog, `Mechanic.compound`). Nil kad se ne zna.
    public let isCompound: Bool?

    public init(exerciseKey: String, exerciseName: String, records: [PersonalRecord], isCompound: Bool?) {
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
        self.records = records
        self.isCompound = isCompound
    }
}

/// Istaknuti rekord u sažetku treninga.
public struct RecordHighlight: Equatable, Sendable {
    public let exerciseKey: String
    public let exerciseName: String
    public let record: PersonalRecord
    /// Značajnost (`PRRanking.significance`): veće je važnije.
    public let score: Double
}

/// Izbor istaknutih rekorda: najviše jedan po vježbi i najviše `summaryLimit` u sažetku, poredani po tome
/// koliko je napredak velik u odnosu na uobičajeno kolebanje vježbe. Tako +5 kg na mrtvom dizanju i
/// jedno ponavljanje više na pregibu dolaze na istu ljestvicu.
public enum PRRanking {
    public static let summaryLimit = 3

    /// Redoslijed vrsta kad vježba ima više rekorda u istom treningu: prvi postojeći se ističe.
    public static let priority: [PRKind] = [
        .estimatedOneRepMax, .repMax, .maxWeight, .maxReps, .lowestAssistance, .longestDistance, .longestDuration, .exerciseVolume
    ]

    /// Uobičajeno kolebanje rezultata između treninga (udio). Polazne procjene iz pouzdanosti mjerenja 1RM
    /// (Grgic i sur. 2020) i grubljih koraka težine kod izolacijskih vježbi; nisu izmjerene norme.
    public static func noise(of kind: PRKind, isCompound: Bool?) -> Double {
        switch kind {
        case .estimatedOneRepMax, .repMax, .maxWeight, .exerciseVolume, .lowestAssistance:
            isCompound == true ? 0.03 : 0.05
        case .maxReps: 0.08
        case .longestDuration, .longestDistance: 0.05
        }
    }

    /// Složene vježbe imaju veću težinu od izolacijskih, nepoznate su između.
    public static func exerciseWeight(isCompound: Bool?) -> Double {
        switch isCompound {
        case true?: 1
        case false?: 0.7
        case nil: 0.85
        }
    }

    /// Značajnost rekorda: ln(novo / staro) podijeljeno s kolebanjem, puta težina vrste vježbe.
    /// Za pomoć je manje bolje, pa se omjer okreće.
    public static func significance(_ record: PersonalRecord, isCompound: Bool?) -> Double {
        guard let previous = record.previousBest, previous > 0, record.value > 0 else { return 0 }
        let ratio = record.kind == .lowestAssistance ? previous / record.value : record.value / previous
        guard ratio > 0 else { return 0 }
        return log(ratio) / noise(of: record.kind, isCompound: isCompound) * exerciseWeight(isCompound: isCompound)
    }

    /// Glavni rekord vježbe: prvi po `priority` među onima koji idu u sažetak.
    public static func headline(of records: [PersonalRecord]) -> PersonalRecord? {
        let shown = records.filter(\.showsInSummary)
        for kind in priority {
            if let record = shown.first(where: { $0.kind == kind }) { return record }
        }
        return nil
    }

    /// Istaknuti rekordi (najviše `limit`, od najznačajnijeg) i broj ostalih rekorda tog treninga.
    public static func highlights(
        _ candidates: [RecordCandidate], limit: Int = summaryLimit
    ) -> (shown: [RecordHighlight], hiddenCount: Int) {
        let best = candidates.compactMap { candidate -> RecordHighlight? in
            guard let record = headline(of: candidate.records) else { return nil }
            return RecordHighlight(
                exerciseKey: candidate.exerciseKey, exerciseName: candidate.exerciseName, record: record,
                score: significance(record, isCompound: candidate.isCompound)
            )
        }
        let shown = Array(best.sorted { $0.score != $1.score ? $0.score > $1.score : $0.exerciseName < $1.exerciseName }.prefix(limit))
        let total = candidates.reduce(0) { $0 + $1.records.count }
        return (shown, total - shown.count)
    }
}

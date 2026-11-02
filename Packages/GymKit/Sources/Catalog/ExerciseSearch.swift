import Foundation

/// Sažetak vježbe za popis i pretragu: isti oblik za službene i vlastite vježbe.
public struct ExerciseSummary: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case catalog(id: String)
        case custom(id: UUID)
    }

    public let source: Source
    public let name: String
    public let category: ExerciseCategory?
    public let muscles: [Muscle]
    public let equipment: Equipment?
    public let isArchived: Bool
    let searchText: String

    public var id: String {
        switch source {
        case .catalog(let id): "c:\(id)"
        case .custom(let id): "u:\(id.uuidString)"
        }
    }

    public var isCustom: Bool {
        if case .custom = source { true } else { false }
    }

    /// `alternativeNames` su nazivi na drugim jezicima: pretraga pronalazi vježbu i po engleskom i po hrvatskom nazivu.
    public init(
        source: Source,
        name: String,
        alternativeNames: [String] = [],
        category: ExerciseCategory?,
        muscles: [Muscle],
        equipment: Equipment?,
        isArchived: Bool
    ) {
        self.source = source
        self.name = name
        self.category = category
        self.muscles = muscles
        self.equipment = equipment
        self.isArchived = isArchived
        self.searchText = ExerciseSearch.normalize(([name] + alternativeNames).joined(separator: " "))
    }
}

public struct ExerciseFilter: Equatable, Sendable {
    public enum Origin: Sendable {
        case all, official, custom
    }

    public var query = ""
    public var categories: Set<ExerciseCategory> = []
    public var muscles: Set<Muscle> = []
    public var equipment: Set<Equipment> = []
    public var origin: Origin = .all
    public var includeArchived = false

    public init() {}

    public var isActive: Bool {
        !categories.isEmpty || !muscles.isEmpty || !equipment.isEmpty || origin != .all
    }
}

public enum ExerciseSearch {

    /// Mala slova, bez dijakritika i s đ → d, pa "cucanj" pronalazi "Čučanj", a "dizanje" "Dizanje".
    public static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// Filtrira i poredava: najprije nazivi koji počinju upitom, zatim riječi koje počinju upitom, pa ostalo.
    /// Svaka riječ upita mora se pojaviti u nazivu. Bez upita rezultat je abecedni.
    public static func apply(_ filter: ExerciseFilter, to items: [ExerciseSummary]) -> [ExerciseSummary] {
        let tokens = normalize(filter.query).split(whereSeparator: \.isWhitespace).map(String.init)

        var scored: [(item: ExerciseSummary, score: Int)] = []
        for item in items {
            if item.isArchived && !filter.includeArchived { continue }
            switch filter.origin {
            case .all: break
            case .official: if item.isCustom { continue }
            case .custom: if !item.isCustom { continue }
            }
            if !filter.categories.isEmpty {
                guard let category = item.category, filter.categories.contains(category) else { continue }
            }
            if !filter.muscles.isEmpty && filter.muscles.isDisjoint(with: item.muscles) { continue }
            if !filter.equipment.isEmpty {
                guard let equipment = item.equipment, filter.equipment.contains(equipment) else { continue }
            }
            guard let score = relevance(of: tokens, in: item.searchText) else { continue }
            scored.append((item, score))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
            }
            .map(\.item)
    }

    /// nil ako neka riječ ne postoji u tekstu. Manje je bolje.
    private static func relevance(of tokens: [String], in text: String) -> Int? {
        guard !tokens.isEmpty else { return 0 }
        var worst = 0
        for (position, token) in tokens.enumerated() {
            guard let range = text.range(of: token) else { return nil }
            let atStart = range.lowerBound == text.startIndex
            let atWordStart = atStart || text[text.index(before: range.lowerBound)] == " "
            let score = atStart && position == 0 ? 0 : (atWordStart ? 1 : 2)
            worst = max(worst, score)
        }
        return worst
    }
}

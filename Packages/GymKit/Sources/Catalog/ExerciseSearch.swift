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
    public let kind: ExerciseKind
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

    /// Vrsta se računa iz kategorije kad je izvor ne zna (vlastite vježbe).
    /// `alternativeNames` su nazivi na drugim jezicima: pretraga pronalazi vježbu i po engleskom i po hrvatskom nazivu.
    public init(
        source: Source,
        name: String,
        alternativeNames: [String] = [],
        category: ExerciseCategory?,
        kind: ExerciseKind? = nil,
        muscles: [Muscle],
        equipment: Equipment?,
        isArchived: Bool
    ) {
        self.source = source
        self.name = name
        self.category = category
        self.kind = kind ?? .fallback(for: category)
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
    /// Vrsta vježbe (stranica vrste na početnoj kataloga). Nije dio `isActive`: postavlja je ekran, a ne list s filterima.
    public var kinds: Set<ExerciseKind> = []
    public var categories: Set<ExerciseCategory> = []
    public var muscles: Set<Muscle> = []
    public var equipment: Set<Equipment> = []
    public var origin: Origin = .all
    public var includeArchived = false

    public init() {}

    public var isActive: Bool {
        !categories.isEmpty || !muscles.isEmpty || !equipment.isEmpty || origin != .all
    }

    /// Razlikuje li se filter od početnog filtera popisa (`base`), ne gledajući upit.
    public func differs(from base: ExerciseFilter) -> Bool {
        var compared = self
        compared.query = base.query
        return compared != base
    }

    /// Vraća početni filter popisa, a zadržava upit.
    public mutating func reset(to base: ExerciseFilter) {
        let query = query
        self = base
        self.query = query
    }

    public init(query: String = "", kinds: Set<ExerciseKind>, origin: Origin = .all) {
        self.query = query
        self.kinds = kinds
        self.origin = origin
    }
}

/// Nazivi kategorija, mišića i opreme kako ih korisnik vidi. Pretraga ih uspoređuje s upitom,
/// pa "sprava" pronalazi sve vježbe na spravi, a "triceps" sve vježbe za triceps.
public struct ExerciseSearchLabels: Sendable {
    let categories: [ExerciseCategory: String]
    let muscles: [Muscle: String]
    let equipment: [Equipment: String]

    public init(
        category: (ExerciseCategory) -> String,
        muscle: (Muscle) -> String,
        equipment: (Equipment) -> String
    ) {
        categories = Dictionary(uniqueKeysWithValues: ExerciseCategory.allCases.map { ($0, ExerciseSearch.normalize(category($0))) })
        muscles = Dictionary(uniqueKeysWithValues: Muscle.allCases.map { ($0, ExerciseSearch.normalize(muscle($0))) })
        self.equipment = Dictionary(uniqueKeysWithValues: Equipment.allCases.map { ($0, ExerciseSearch.normalize(equipment($0))) })
    }

    /// Bez naziva: pretraga samo po nazivu vježbe.
    public static let none = ExerciseSearchLabels(category: { _ in "" }, muscle: { _ in "" }, equipment: { _ in "" })

    /// Svi nazivi vježbe u jednom tekstu, odvojeni razmakom.
    func text(for item: ExerciseSummary) -> String {
        var parts: [String] = []
        if let category = item.category, let title = categories[category] { parts.append(title) }
        parts += item.muscles.compactMap { muscles[$0] }
        if let value = item.equipment, let title = equipment[value] { parts.append(title) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
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

    /// Broj vježbi po vrsti, bez arhiviranih (kartice na početnoj kataloga).
    public static func countsByKind(_ items: [ExerciseSummary]) -> [ExerciseKind: Int] {
        items.reduce(into: [:]) { counts, item in
            if !item.isArchived { counts[item.kind, default: 0] += 1 }
        }
    }

    /// Filtrira i poredava: najprije nazivi koji počinju upitom, zatim riječi koje počinju upitom, pa ostalo,
    /// a na kraju vježbe koje upitu odgovaraju tek po kategoriji, mišiću ili opremi.
    /// Svaka riječ upita mora se pojaviti u nazivu ili u `labels`. Bez upita rezultat je abecedni.
    public static func apply(
        _ filter: ExerciseFilter, to items: [ExerciseSummary], labels: ExerciseSearchLabels = .none
    ) -> [ExerciseSummary] {
        let tokens = normalize(filter.query).split(whereSeparator: \.isWhitespace).map(String.init)

        var scored: [(item: ExerciseSummary, score: Int)] = []
        for item in items {
            if item.isArchived && !filter.includeArchived { continue }
            switch filter.origin {
            case .all: break
            case .official: if item.isCustom { continue }
            case .custom: if !item.isCustom { continue }
            }
            if !filter.kinds.isEmpty && !filter.kinds.contains(item.kind) { continue }
            if !filter.categories.isEmpty {
                guard let category = item.category, filter.categories.contains(category) else { continue }
            }
            if !filter.muscles.isEmpty && filter.muscles.isDisjoint(with: item.muscles) { continue }
            if !filter.equipment.isEmpty {
                guard let equipment = item.equipment, filter.equipment.contains(equipment) else { continue }
            }
            guard let score = relevance(of: tokens, in: item.searchText, labels: tokens.isEmpty ? "" : labels.text(for: item))
            else { continue }
            scored.append((item, score))
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
            }
            .map(\.item)
    }

    /// nil ako neka riječ ne postoji ni u nazivu ni u `labels`. Manje je bolje.
    private static func relevance(of tokens: [String], in text: String, labels: String) -> Int? {
        guard !tokens.isEmpty else { return 0 }
        var worst = 0
        for (position, token) in tokens.enumerated() {
            let score: Int
            if let range = text.range(of: token) {
                let atStart = range.lowerBound == text.startIndex
                let atWordStart = atStart || text[text.index(before: range.lowerBound)] == " "
                score = atStart && position == 0 ? 0 : (atWordStart ? 1 : 2)
            } else if labels.range(of: token) != nil {
                score = 3
            } else {
                return nil
            }
            worst = max(worst, score)
        }
        return worst
    }
}

import Foundation
import SwiftData

/// Vrste kartica koje korisnik može dodati na Početnu. Nepoznate vrste (iz novije verzije aplikacije)
/// ostaju u bazi, ali se ne prikazuju.
public enum DashboardCardKind: String, CaseIterable, Sendable {
    case thisWeek
    /// Tekući mjesec, kao Ovaj tjedan, s prosjekom treninga tjedno; dodir otvara Pregled na mjesecu.
    case thisMonth
    /// Tekuća godina s treninzima po mjesecima; dodir otvara Pregled na godini.
    case thisYear
    case lastWorkout
    case bodyWeight
    case plateCalculator

    /// Mala kartica: dvije uzastopne male kartice stoje jedna do druge (`DashboardLayout.rows`).
    public var isCompact: Bool {
        switch self {
        case .bodyWeight, .plateCalculator: true
        case .thisWeek, .thisMonth, .thisYear, .lastWorkout: false
        }
    }

    /// Vrste koje Početna dobiva na praznom početku, ovim redom.
    public static let defaults: [DashboardCardKind] = [.thisWeek, .lastWorkout]

    /// Ukinute vrste. Tjedni volumen (tonaža) je zamijenila kartica Ovaj tjedan, a sljedeći trening
    /// ponavljao je ono što već piše u kartici Započni.
    static let retiredWeeklyVolume = "weeklyVolume"
    static let retiredNextWorkout = "nextWorkout"
}

public extension DashboardCard {
    var kind: DashboardCardKind? { DashboardCardKind(rawValue: kindRaw) }
}

/// Slaganje kartica na Početnoj: dodavanje, uklanjanje i premještanje. Redoslijed je u `orderIndex`.
public struct DashboardLayout {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Sve kartice po redoslijedu (i one nepoznate vrste).
    public func allCards() throws -> [DashboardCard] {
        try context.fetch(FetchDescriptor<DashboardCard>(sortBy: [SortDescriptor(\.orderIndex)]))
    }

    /// Kartice koje se prikazuju: poznate vrste, najviše jedna po vrsti (duplikati iz sinkronizacije se preskaču).
    public func cards() throws -> [DashboardCard] {
        Self.visible(try allCards())
    }

    /// Kao `cards()`, za kartice koje je ekran već dohvatio (`@Query` po `orderIndex`).
    public static func visible(_ all: [DashboardCard]) -> [DashboardCard] {
        var seen = Set<DashboardCardKind>()
        return all.filter { card in
            guard let kind = card.kind else { return false }
            return seen.insert(kind).inserted
        }
    }

    /// Vrste koje još nisu na Početnoj.
    public func availableKinds() throws -> [DashboardCardKind] {
        let present = Set(try cards().compactMap(\.kind))
        return DashboardCardKind.allCases.filter { !present.contains($0) }
    }

    /// Dodaje karticu na kraj. Ako ta vrsta već postoji, ne radi ništa.
    @discardableResult
    public func add(_ kind: DashboardCardKind) throws -> DashboardCard? {
        guard try availableKinds().contains(kind) else { return nil }
        let next = (try allCards().last?.orderIndex ?? -1) + 1
        let card = DashboardCard(kindRaw: kind.rawValue, orderIndex: next)
        context.insert(card)
        try context.save()
        return card
    }

    /// Početna bez ijedne kartice dobiva zadane kartice (`DashboardCardKind.defaults`).
    ///
    /// Samo na praznoj Početnoj: ako kartice već postoje (npr. stigle su s drugog uređaja), korisnik ih je
    /// složio sam, pa se kartica koju je uklonio ne vraća. Duplikat s drugog uređaja uklanja deduplikacija.
    @discardableResult
    public func seedDefaults() throws -> [DashboardCard] {
        guard try allCards().isEmpty else { return [] }
        let cards = DashboardCardKind.defaults.enumerated().map { index, kind in
            DashboardCard(kindRaw: kind.rawValue, orderIndex: index)
        }
        cards.forEach(context.insert)
        try context.save()
        return cards
    }

    /// Prijelaz na kartice nove Početne (jednom po uređaju): kartica tjednog volumena postaje kartica
    /// Ovaj tjedan na istom mjestu, kartica sljedećeg treninga se uklanja, a Početna koja nema karticu
    /// Ovaj tjedan dobiva je na vrhu. Prazna Početna ostaje prazna (puni je `seedDefaults`).
    public func upgradeToWeekCard() throws {
        let all = try allCards()
        guard !all.isEmpty else { return }
        let week = DashboardCardKind.thisWeek.rawValue
        var hasWeek = all.contains { $0.kindRaw == week }
        var cards: [DashboardCard] = []
        for card in all {
            switch card.kindRaw {
            case DashboardCardKind.retiredWeeklyVolume where !hasWeek:
                card.kindRaw = week
                hasWeek = true
                cards.append(card)
            case DashboardCardKind.retiredWeeklyVolume, DashboardCardKind.retiredNextWorkout:
                context.delete(card)
            default:
                cards.append(card)
            }
        }
        if !hasWeek {
            let card = DashboardCard(kindRaw: week, orderIndex: 0)
            context.insert(card)
            cards.insert(card, at: 0)
        }
        try renumber(cards)
        try context.save()
    }

    /// Redovi Početne: velika kartica je sama u redu, a dvije uzastopne male kartice dijele red.
    public static func rows(_ kinds: [DashboardCardKind]) -> [[DashboardCardKind]] {
        var rows: [[DashboardCardKind]] = []
        for kind in kinds {
            if kind.isCompact, let last = rows.last, last.count == 1, last[0].isCompact {
                rows[rows.count - 1].append(kind)
            } else {
                rows.append([kind])
            }
        }
        return rows
    }

    public func remove(_ card: DashboardCard) throws {
        context.delete(card)
        try renumber(try allCards().filter { $0.persistentModelID != card.persistentModelID })
        try context.save()
    }

    /// Premješta prikazane kartice (`offsets` i `destination` su indeksi u `cards()`, kao kod `onMove`).
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        var visible = try cards()
        visible.moveElements(fromOffsets: offsets, toOffset: destination)
        let hidden = try allCards().filter { card in !visible.contains { $0.persistentModelID == card.persistentModelID } }
        try renumber(visible + hidden)
        try context.save()
    }

    private func renumber(_ cards: [DashboardCard]) throws {
        for (index, card) in cards.enumerated() where card.orderIndex != index {
            card.orderIndex = index
        }
    }
}

import Foundation
import SwiftData

/// Vrste kartica koje korisnik može dodati na Početnu. Nepoznate vrste (iz novije verzije aplikacije)
/// ostaju u bazi, ali se ne prikazuju.
public enum DashboardCardKind: String, CaseIterable, Sendable {
    case lastWorkout
    case plateCalculator
    case nextWorkout
    case weeklyVolume
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
        var seen = Set<DashboardCardKind>()
        return try allCards().filter { card in
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

    /// Početna bez ijedne kartice dobiva karticu zadnjeg treninga.
    ///
    /// Samo na praznoj Početnoj: ako kartice već postoje (npr. stigle su s drugog uređaja), korisnik ih je
    /// složio sam, pa se kartica zadnjeg treninga koju je uklonio ne vraća. Duplikat s drugog uređaja
    /// uklanja deduplikacija.
    @discardableResult
    public func seedLastWorkout() throws -> DashboardCard? {
        guard try allCards().isEmpty else { return nil }
        let card = DashboardCard(kindRaw: DashboardCardKind.lastWorkout.rawValue, orderIndex: 0)
        context.insert(card)
        try context.save()
        return card
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

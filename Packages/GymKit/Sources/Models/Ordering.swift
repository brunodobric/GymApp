import Foundation

extension Array {
    /// Premješta elemente kao SwiftUI `move(fromOffsets:toOffset:)`, koji u paketu nije dostupan (GymKit ne uvozi
    /// SwiftUI). `destination` je indeks prije premještanja, kao u `onMove`. Nepostojeći indeksi se preskaču.
    public mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        let moving = valid.sorted().map { self[$0] }
        let target = destination - valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) { remove(at: index) }
        insert(contentsOf: moving, at: Swift.min(Swift.max(target, 0), count))
    }
}

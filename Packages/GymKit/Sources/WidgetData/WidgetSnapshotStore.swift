import Foundation

/// Snimka za widgete u datoteci zajedničkog App Groupa. Aplikacija piše, widget extension čita.
public struct WidgetSnapshotStore: Sendable {
    public static let appGroup = "group.com.brunodobric.gymapp"
    static let fileName = "widget-snapshot.json"

    /// Mapa u kojoj je datoteka; nil kad App Group nije dostupan (npr. build bez potpisivanja).
    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    /// Mapa App Groupa.
    public static var shared: WidgetSnapshotStore {
        WidgetSnapshotStore(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup))
    }

    private var url: URL? { directory?.appending(path: Self.fileName) }

    public func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Sprema snimku. Vraća true kad se sadržaj promijenio (tada treba osvježiti widgete).
    /// Vrijeme izrade se ne uspoređuje, inače bi se widgeti osvježavali pri svakom spremanju baze.
    @discardableResult
    public func save(_ snapshot: WidgetSnapshot) throws -> Bool {
        guard let url, let directory else { return false }
        if var old = load() {
            old.generatedAt = snapshot.generatedAt
            if old == snapshot { return false }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
        return true
    }

    // Zadani zapis datuma (sekunde od 2001.) se čita natrag bez gubitka preciznosti, pa usporedba
    // stare i nove snimke ne vidi promjenu tamo gdje je nema. Sekunde od 1970. bi pomaknule razlomke sekunde.
    private static var encoder: JSONEncoder { JSONEncoder() }
    private static var decoder: JSONDecoder { JSONDecoder() }
}

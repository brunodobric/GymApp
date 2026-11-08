import Foundation

/// Poveznice kojima widgeti otvaraju aplikaciju (`widgetURL` i `Link`). Shema `apolon` je u `project.yml`,
/// a `RootView` ih prima u `onOpenURL`. `trening` je ista poveznica kao iz Live Activityja.
public enum WidgetLink: Equatable, Sendable {
    /// Početna.
    case home
    /// Pokreće sljedeći trening (ili nastavlja trening u tijeku), kao ⌘N.
    case startWorkout
    /// Puni ekran treninga u tijeku.
    case activeWorkout
    /// Pregled tekućeg tjedna.
    case week
    /// Praćenje tijela (unos težine).
    case bodyWeight
    /// Zadnji odrađeni trening.
    case lastWorkout
    /// Određeni odrađeni trening (npr. onaj s rekordom).
    case session(UUID)

    public static let scheme = "apolon"

    private var host: String {
        switch self {
        case .session: "povijest"
        case .home: "pocetna"
        case .startWorkout: "zapocni"
        case .activeWorkout: "trening"
        case .week: "tjedan"
        case .bodyWeight: "tezina"
        case .lastWorkout: "zadnji-trening"
        }
    }

    public var url: URL {
        if case .session(let id) = self {
            return URL(string: "\(Self.scheme)://\(host)/\(id.uuidString)")!
        }
        return URL(string: "\(Self.scheme)://\(host)")!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        if host == "povijest" {
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .session(id)
            return
        }
        let all: [WidgetLink] = [.home, .startWorkout, .activeWorkout, .week, .bodyWeight, .lastWorkout]
        guard let link = all.first(where: { $0.host == host }) else { return nil }
        self = link
    }
}

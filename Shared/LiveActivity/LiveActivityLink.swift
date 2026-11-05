import Foundation

/// Poveznica kojom Live Activity otvara aplikaciju (`widgetURL`). Shema `apolon` je u `project.yml`
/// (`CFBundleURLTypes`), a `RootView` je prima u `onOpenURL` i otvara puni ekran aktivnog treninga.
enum LiveActivityLink {
    static let scheme = "apolon"
    static let activeWorkout = URL(string: "\(scheme)://trening")!

    static func isActiveWorkout(_ url: URL) -> Bool {
        url.scheme == scheme && url.host() == activeWorkout.host()
    }
}

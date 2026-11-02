import ActivityKit
import Foundation

/// Podaci Live Activityja tijekom treninga (specifikacija, odjeljak 6).
/// Dijele ih aplikacija (pokreće i ažurira) i widget extension (prikazuje).
/// Puna implementacija dolazi u fazi 9.
struct RestTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Kraj odmora. `nil` znači da odmor nije u tijeku.
        var restEndsAt: Date?
        var exerciseName: String
        /// Npr. "Serija 3 od 4".
        var setDescription: String
    }

    var workoutName: String
}

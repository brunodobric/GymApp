import ActivityKit
import Foundation

/// Podaci Live Activityja tijekom treninga (specifikacija, odjeljak 6).
/// Dijele ih aplikacija (pokreće, ažurira i gasi) i widget extension (prikazuje).
/// Widget ne ovisi o GymKitu, pa su ovdje samo jednostavne vrijednosti koje aplikacija složi.
struct RestTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Vježba sljedeće serije. `nil` kad su sve serije završene.
        var exerciseName: String?
        var nextExerciseName: String?
        /// Redni broj sljedeće serije u vježbi (od 1) i broj serija vježbe.
        var setNumber: Int
        var setCount: Int
        var completedSets: Int
        var totalSets: Int
        /// Serija koju potvrđuje gumb (UUID kao tekst). `nil` kad nema što potvrditi.
        var nextSetID: String?
        /// Serija ima sve vrijednosti. Bez njih gumb se ne prikazuje, a dodir otvara aplikaciju.
        var canConfirm: Bool
        /// Odmor u tijeku. `nil` kad odmora nema.
        var restStartedAt: Date?
        var restEndsAt: Date?
        /// Trening vodi Apple Watch.
        var isLedByWatch: Bool
    }

    var sessionID: String
    var workoutName: String
}

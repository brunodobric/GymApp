import ActivityKit
import Foundation

/// Podaci Live Activityja tijekom treninga (specifikacija, odjeljak 6).
/// Dijele ih aplikacija (pokreće, ažurira i gasi) i widget extension (prikazuje).
/// Widget ne ovisi o GymKitu, pa su ovdje samo jednostavne vrijednosti koje aplikacija složi.
struct RestTimerActivityAttributes: ActivityAttributes {
    /// Jedna vrijednost sljedeće serije (težina, ponavljanja, trajanje ili udaljenost), već formatirana.
    struct SetValue: Codable, Hashable {
        /// `WatchSetField.rawValue`, šalje se natrag u `AdjustSetValueIntent`.
        var field: String
        /// Broj bez jedinice, npr. "82,5", "8", "1:30". "–" kad nije upisan.
        var text: String
        /// "kg", "lbs" ili "m". Prazno za ponavljanja i trajanje.
        var unitSymbol: String
        var canDecrease: Bool
        var canIncrease: Bool
    }

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
        /// Vrijednosti serije koju gumb potvrđuje, s gumbima − i +. Prazno kad nema sljedeće serije.
        var setValues: [SetValue]
        /// Ista serija u prethodnom treningu, npr. "30 kg\n12 ×" (dva reda). Opcionalno i zbog stanja starije verzije.
        var previousText: String?
        /// Serija ima sve vrijednosti. Bez njih gumb se ne prikazuje, a dodir otvara aplikaciju.
        var canConfirm: Bool
        /// Odmor u tijeku. `nil` kad odmora nema.
        var restStartedAt: Date?
        var restEndsAt: Date?
        /// Početak treninga, za trajanje na vrhu. Opcionalno da se dekodira i stanje starije verzije.
        var workoutStartedAt: Date?
        /// Trening vodi Apple Watch.
        var isLedByWatch: Bool
    }

    var sessionID: String
    var workoutName: String
}

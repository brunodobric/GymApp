import Stats

/// Ekrani koje otvaraju kartice Početne i Statistike (`DetailLink`).
///
/// U jednom stupcu se guraju u stog taba, a u podijeljenom prikazu (iPad, otvoreni iPhone Duo)
/// otvaraju se u desnom stupcu. Svaki tab sam odlučuje što prikazuje za koju vrijednost.
enum CardDestination: Hashable {
    /// Pregled tjedna, mjeseca ili godine.
    case overview(OverviewPeriod)
    /// Detalji zadnjeg odrađenog treninga (samo Početna).
    case lastWorkout
    /// Praćenje tijela.
    case body
    /// Kalkulator ploča (samo Početna).
    case plateCalculator
    /// Svi osobni rekordi (samo Statistika).
    case records
    /// Odabir vježbe za graf napretka (samo Statistika).
    case exerciseProgress
}

import Foundation

/// Kako se prikazuje službena vježba: MoveKit klip u petlji s posterom, samo poster ili ništa.
public enum ExerciseIllustration: Hashable, Sendable {
    /// Klip u petlji. Poster se prikazuje dok se klip učitava i uz Smanji kretanje.
    case video(String, poster: String?)
    /// Samo mirna slika.
    case poster(String)
    case unavailable
}

extension CatalogExercise {
    /// Ilustracija iz putanja u katalogu. `isAvailable` kaže postoji li datoteka u buildu: build bez
    /// MoveKit paketa (CI, klon repozitorija) nema medije, pa vježba nema ni klip ni poster.
    public func illustration(isAvailable: (String) -> Bool) -> ExerciseIllustration {
        let poster = poster.flatMap { isAvailable($0) ? $0 : nil }
        if let video, isAvailable(video) {
            return .video(video, poster: poster)
        }
        if let poster { return .poster(poster) }
        return .unavailable
    }
}

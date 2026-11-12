import Models

/// Kartica "Postavi profil" na Početnoj: naknadno ispunjavanje onboardinga kad ga je korisnik preskočio
/// ili ostavio prazan, a još nema nijedan raspored. Zatvara se križićem ili sama nestaje kad korisnik
/// odgovori o treningu ili doda raspored.
public enum ProfileSetupPrompt {
    public static func isShown(settings: UserSettings?, scheduleCount: Int, dismissed: Bool) -> Bool {
        guard let settings, settings.onboardingCompleted, !dismissed, scheduleCount == 0 else { return false }
        return !TrainingProfile(settings: settings).hasAnswers
    }
}

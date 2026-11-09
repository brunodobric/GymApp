import Models
import Planning
import SwiftUI

/// Postavke > Profil: isti podaci kao u onboardingu (cilj, dani, iskustvo, oprema, spol) i prijedlog rasporeda.
struct ProfileSettingsSection: View {
    @Bindable var settings: UserSettings

    var body: some View {
        TrainingProfileSections(
            goal: $settings.goal, daysPerWeek: $settings.trainingDaysPerWeek,
            experience: $settings.experience, equipment: $settings.equipment
        )
        Section {
            Picker("Spol", selection: $settings.sex) {
                Text("Bez odgovora").tag(Sex?.none)
                ForEach(Sex.allCases, id: \.self) { Text($0.title).tag(Sex?.some($0)) }
            }
        } footer: {
            Text("Spol treba samo za DOTS bodove u detaljnoj statistici.")
        }
        Section {
            NavigationLink("Predloži raspored") {
                ProgramRecommendationScreen(settings: settings)
            }
        } footer: {
            Text("Gotov raspored prema cilju, danima, iskustvu i opremi. Postojeći rasporedi ostaju kakvi jesu.")
        }
    }
}

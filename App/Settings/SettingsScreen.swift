import Models
import SwiftData
import SwiftUI

/// Kategorije postavki: svaka je redak na prvom ekranu i otvara vlastitu stranicu.
enum SettingsCategory: Hashable, CaseIterable {
    case appearance, training, plates, notifications, health, sync, data, about

    var title: LocalizedStringKey {
        switch self {
        case .appearance: "Prikaz"
        case .training: "Trening"
        case .plates: "Ploče i šipka"
        case .notifications: "Obavijesti"
        case .health: "Zdravlje"
        case .sync: "iCloud"
        case .data: "Podaci"
        case .about: "O aplikaciji"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintbrush"
        case .training: "dumbbell"
        case .plates: "scalemass"
        case .notifications: "bell"
        case .health: "heart"
        case .sync: "icloud"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }

    /// Grupe na prvom ekranu: trening i izgled, veze sa sustavom, podaci te podaci o aplikaciji.
    static let groups: [[SettingsCategory]] = [
        [.appearance, .training, .plates],
        [.notifications, .health, .sync],
        [.data],
        [.about]
    ]
}

/// Postavke: popis kategorija, a svaka kategorija je zasebna stranica u istom `NavigationStack`u.
///
/// Na iPadu je to isti list (form sheet), pa stranice idu jedna na drugu kao na iPhoneu.
struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    // Postavke iz upita, a ne zapamćeni objekt: nakon sinkronizacije duplikat postavki može biti obrisan.
    @Query private var settingsList: [UserSettings]
    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    @State private var dataSettings = DataSettingsModel()

    private var systemScheme: ColorScheme? {
        guard settings != nil else { return nil }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(SettingsCategory.groups, id: \.self) { group in
                    Section {
                        ForEach(group, id: \.self) { category in
                            NavigationLink(value: category) {
                                Label(category.title, systemImage: category.systemImage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Postavke")
            .navigationDestination(for: SettingsCategory.self) { category in
                destination(for: category)
            }
            .task { _ = try? GymQueries(context: context).settings() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotovo") { dismiss() }
                }
            }
        }
        // Na cijelom stogu, da vrijede i na otvorenim stranicama kategorija.
        // Otvoreni list ne preuzima promjenu teme i boje iz korijena dok je prikazan, pa ih primjenjuje sam.
        // Za "Sustav" nil ne poništava već prisilno postavljenu shemu na prikazanom listu, pa se šalje
        // sistemska shema izričito.
        .preferredColorScheme(settings?.theme.colorScheme ?? systemScheme)
        .tint(settings?.accent.color ?? AccentChoice.blue.color)
    }

    @ViewBuilder
    private func destination(for category: SettingsCategory) -> some View {
        switch category {
        case .appearance:
            UserSettingsPage(category) { AppearanceSettingsSection(settings: $0) }
        case .training:
            UserSettingsPage(category) { TrainingSettingsSection(settings: $0) }
        case .plates:
            UserSettingsPage(category) { PlatesSettingsSection(settings: $0) }
        case .notifications:
            UserSettingsPage(category) { NotificationSettingsSection(settings: $0) }
        case .health:
            UserSettingsPage(category) { HealthSettingsSection(settings: $0) }
        case .sync:
            Form { SyncSettingsSection() }
                .settingsPageTitle(category)
        case .data:
            DataSettingsScreen(model: dataSettings) {
                // Nakon brisanja svih podataka Početna prikazuje onboarding, pa se cijeli list zatvara.
                let fresh = try? GymQueries(context: context).settings()
                if fresh?.onboardingCompleted == false { dismiss() }
            }
        case .about:
            AboutScreen()
        }
    }
}

private extension View {
    func settingsPageTitle(_ category: SettingsCategory) -> some View {
        navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Stranica kategorije koja uređuje `UserSettings`. Postavke dohvaća sama, iz istog razloga kao `SettingsScreen`.
private struct UserSettingsPage<Content: View>: View {
    let category: SettingsCategory
    let content: (UserSettings) -> Content

    @Query private var settingsList: [UserSettings]

    init(_ category: SettingsCategory, @ViewBuilder content: @escaping (UserSettings) -> Content) {
        self.category = category
        self.content = content
    }

    var body: some View {
        Form {
            if let settings = UserSettings.preferred(in: settingsList) {
                content(settings)
            }
        }
        .settingsPageTitle(category)
    }
}

/// Postavke > Podaci. Prozori su na ovom `Form`u, jednom (vidi `DataSettingsSection`).
private struct DataSettingsScreen: View {
    let model: DataSettingsModel
    let onReset: () -> Void

    var body: some View {
        Form {
            DataSettingsSection(model: model)
        }
        .dataSettingsPresentations(model, onReset: onReset)
        .settingsPageTitle(.data)
    }
}

/// Postavke > O aplikaciji: verzija, atribucije, pravila privatnosti i dijagnostika.
private struct AboutScreen: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Verzija", value: version)
            }
            Section {
                // Atribucija kataloga (specifikacija, odjeljak 10), iako je javno vlasništvo.
                Link(destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!) {
                    LabeledContent("Katalog vježbi", value: "free-exercise-db")
                }
                // Atribucija crteža tijela (MIT licenca zahtijeva copyright napomenu i tekst licence).
                NavigationLink {
                    MuscleMapLicenseScreen()
                } label: {
                    LabeledContent("Crteži tijela", value: "MuscleMap")
                }
            }
            Section {
                Link("Pravila privatnosti", destination: PrivacyPolicy.url)
                NavigationLink("Dijagnostika") { DiagnosticsScreen() }
            }
        }
        .settingsPageTitle(.about)
    }
}

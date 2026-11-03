import Models
import SwiftUI
import Units

extension AppTheme {
    /// nil znači da aplikacija prati sustav.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Sustav"
        case .light: "Svijetla"
        case .dark: "Tamna"
        }
    }
}

extension AccentChoice {
    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .pink: .pink
        case .teal: .teal
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .blue: "Plava"
        case .green: "Zelena"
        case .orange: "Narančasta"
        case .red: "Crvena"
        case .purple: "Ljubičasta"
        case .pink: "Roza"
        case .teal: "Tirkizna"
        }
    }
}

/// Tipovi rekorda koje korisnik uključuje pojedinačno (vidi `PRKind.kinds(fromSettings:)`).
enum PRSettingOption: String, CaseIterable, Identifiable {
    case maxWeight, maxVolume, maxReps

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .maxWeight: "Najveća težina"
        case .maxVolume: "Najveći volumen"
        case .maxReps: "Najviše ponavljanja"
        }
    }

    func binding(for settings: UserSettings) -> Binding<Bool> {
        Binding(
            get: { settings.trackedPRKinds.contains(rawValue) },
            set: { isOn in
                var kinds = settings.trackedPRKinds.filter { $0 != rawValue }
                if isOn { kinds.append(rawValue) }
                // Stalan redoslijed, da se zapis u postavkama ne mijenja bez potrebe.
                settings.trackedPRKinds = PRSettingOption.allCases.map(\.rawValue).filter(kinds.contains)
            }
        )
    }
}

/// Tema, naglasna boja i tijelo na prikazu mišića.
struct AppearanceSettingsSection: View {
    @Bindable var settings: UserSettings

    var body: some View {
        Section("Prikaz") {
            Picker("Tema", selection: $settings.theme) {
                ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            AccentPicker(selection: $settings.accent)
            Picker("Tijelo na prikazu mišića", selection: $settings.bodyMapFemale) {
                Text("Muško").tag(false)
                Text("Žensko").tag(true)
            }
        }
    }
}

/// Izbor naglasne boje kao red obojenih krugova (izbornik bi ih obojio trenutnom bojom).
private struct AccentPicker: View {
    @Binding var selection: AccentChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boja")
            HStack {
                ForEach(AccentChoice.allCases, id: \.self) { choice in
                    Button {
                        selection = choice
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if selection == choice {
                                    Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(choice.title))
                    .accessibilityAddTraits(selection == choice ? .isSelected : [])
                    if choice != AccentChoice.allCases.last { Spacer(minLength: 0) }
                }
            }
        }
    }
}

/// Šipka i dostupne ploče za kalkulator ploča. Spremaju se u kg; za funte se koriste uobičajene ploče.
struct PlatesSettingsSection: View {
    @Bindable var settings: UserSettings

    private static let options: [Double] = [0.5, 1.25, 2.5, 5, 10, 15, 20, 25]

    var body: some View {
        Section {
            Stepper(value: $settings.barbellWeightKg, in: 5...30, step: 2.5) {
                LabeledContent("Šipka") {
                    Text("\(NumberInput.format(settings.barbellWeightKg)) kg")
                }
            }
            ForEach(Self.options, id: \.self) { plate in
                Toggle("\(NumberInput.format(plate)) kg", isOn: binding(for: plate))
            }
        } header: {
            Text("Ploče i šipka")
        } footer: {
            Text("Kalkulator ploča koristi ove ploče kad su jedinice kilogrami. Za funte koristi uobičajene ploče.")
        }
    }

    private func binding(for plate: Double) -> Binding<Bool> {
        Binding(
            get: { settings.availablePlatesKg.contains(plate) },
            set: { isOn in
                var plates = settings.availablePlatesKg.filter { $0 != plate }
                if isOn { plates.append(plate) }
                settings.availablePlatesKg = plates.sorted()
            }
        )
    }
}

/// Podsjetnici rasporeda i obavijest o kraju pauze.
struct NotificationSettingsSection: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var context

    var body: some View {
        Section {
            Toggle("Obavijesti", isOn: $settings.notificationsEnabled)
                .onChange(of: settings.notificationsEnabled) { _, enabled in
                    if !enabled { RestNotifications.cancel() }
                    ReminderScheduler.refresh(context: context)
                }
        } footer: {
            Text("Podsjetnici rasporeda i obavijest o kraju pauze kad je aplikacija u pozadini. Dopuštenje se traži kad prvi put zatrebaju.")
        }
    }
}

/// Apple Zdravlje: spremanje treninga te uvoz kardio treninga, težine i visine.
struct HealthSettingsSection: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var context

    private var isAvailable: Bool { HealthService.shared.isAvailable }

    var body: some View {
        Section {
            Toggle("Apple Zdravlje", isOn: $settings.wantsHealthKit)
                .disabled(!isAvailable)
                .onChange(of: settings.wantsHealthKit) { _, connected in
                    try? context.save()
                    guard connected else { return }
                    Task {
                        await HealthService.shared.requestAuthorization()
                        await HealthService.shared.importNewData(context: context)
                    }
                }
        } header: {
            Text("Zdravlje")
        } footer: {
            if isAvailable {
                Text("Treninzi s iPhonea spremaju se u Zdravlje, a kardio treninzi iz aplikacije Trening, težina i visina uvoze se u aplikaciju. Što smije čitati i pisati mijenjaš u aplikaciji Zdravlje: Profil > Aplikacije > GymApp.")
            } else {
                Text("Zdravlje nije dostupno na ovom uređaju.")
            }
        }
    }
}

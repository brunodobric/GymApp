import Models
import SwiftUI
import Training
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
        Section {
            Picker("Tema", selection: $settings.theme) {
                ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            AccentPicker(selection: $settings.accent)
            Picker("Tijelo na prikazu mišića", selection: $settings.bodyMapFemale) {
                Text("Muško").tag(false)
                Text("Žensko").tag(true)
            }
        }
        LiveActivityAppearanceSection(settings: settings)
    }
}

/// Tema i naglasna boja Live Activityja: prate aplikaciju ili su vlastite.
private struct LiveActivityAppearanceSection: View {
    @Bindable var settings: UserSettings

    private var followsApp: Binding<Bool> {
        Binding(
            get: { settings.liveActivityFollowsApp },
            set: { settings.setLiveActivityFollowsApp($0) }
        )
    }

    var body: some View {
        Section {
            Toggle("Prati aplikaciju", isOn: followsApp)
            if !settings.liveActivityFollowsApp {
                Picker("Tema", selection: $settings.liveActivityTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                AccentPicker(selection: $settings.liveActivityAccent)
            }
        } header: {
            Text("Live Activity")
        } footer: {
            Text("Tema vrijedi za zaključani zaslon. Dynamic Island je uvijek crn, pa se ondje mijenja samo boja.")
        }
        // Promjena se odmah vidi u Live Activityju ako je trening u tijeku.
        .onChange(of: settings.effectiveLiveActivityTheme) { WorkoutLiveUpdates.shared.refresh() }
        .onChange(of: settings.effectiveLiveActivityAccent) { WorkoutLiveUpdates.shared.refresh() }
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
            Text("Šipka i ploče")
        } footer: {
            Text("Kalkulator ploča koristi ove ploče kad su jedinice kilogrami. Za funte koristi uobičajene ploče.")
        }
    }

    private func binding(for plate: Double) -> Binding<Bool> {
        Binding(
            get: { settings.availablePlatesKg.contains(plate) },
            set: { isOn in
                settings.availablePlatesKg = PlateCalculator.setting(plate, enabled: isOn, in: settings.availablePlatesKg)
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
            Toggle("Podsjetnici rasporeda", isOn: $settings.notificationsEnabled)
                .onChange(of: settings.notificationsEnabled) {
                    try? context.save()
                    ReminderScheduler.refresh(context: context)
                }
            Toggle("Kraj odmora", isOn: $settings.restNotificationEnabled)
                .onChange(of: settings.restNotificationEnabled) {
                    try? context.save()
                    WorkoutLiveUpdates.shared.refresh()
                }
            NavigationLink {
                FocusTipScreen()
            } label: {
                Label("Fokus tijekom treninga", systemImage: "moon.fill")
            }
        } footer: {
            Text("Obavijest o kraju odmora stiže kad je iPhone zaključan ili je trening sažet u karticu, i prolazi kroz Fokus. Dopuštenje se traži kad prvi put zatreba.")
        }
    }
}

/// Apple Zdravlje: spremanje treninga te uvoz kardio treninga, težine i visine.
struct HealthSettingsSection: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var context

    @State private var isImporting = false

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
            if isAvailable && settings.wantsHealthKit {
                // Uvoz inače ide sam pri otvaranju aplikacije; gumb je za slučaj kad korisnik ne želi čekati.
                Button {
                    importNow()
                } label: {
                    HStack {
                        Text("Uvezi iz Zdravlja sada")
                        Spacer()
                        if isImporting { ProgressView() }
                    }
                }
                .disabled(isImporting)
            }
        } footer: {
            if isAvailable {
                Text("Treninzi s iPhonea spremaju se u Zdravlje, a kardio treninzi, težina i visina uvoze se iz njega. Dozvole mijenjaš u Zdravlju: Profil > Aplikacije > Apolon.")
            } else {
                Text("Zdravlje nije dostupno na ovom uređaju.")
            }
        }
    }

    private func importNow() {
        isImporting = true
        Task {
            await HealthService.shared.importNewData(context: context)
            isImporting = false
        }
    }
}

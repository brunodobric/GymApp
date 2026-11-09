import Models
import SwiftUI
import Training
import Units

/// Postavke treninga: jedinice, zadana pauza, RPE ili RIR, zvuk kraja odmora, rekordi i prikaz statistike.
struct TrainingSettingsSection: View {
    @Bindable var settings: UserSettings

    private var excludedSummary: String {
        let count = settings.prExcludedExerciseKeys.count
        return count == 0 ? String(localized: "Sve") : String(localized: "Isključeno: \(count)")
    }

    var body: some View {
        Section {
            Picker("Jedinice", selection: $settings.weightUnit) {
                Text("Kilogrami").tag(WeightUnit.kilograms)
                Text("Funte").tag(WeightUnit.pounds)
            }
            Picker("Napor", selection: $settings.effortScale) {
                Text("RPE").tag(EffortScale.rpe)
                Text("RIR").tag(EffortScale.rir)
            }
            Toggle("Zvuk kraja odmora", isOn: $settings.restEndSoundEnabled)
        }
        Section {
            Stepper(value: $settings.compoundRestSeconds, in: 15...600, step: 15) {
                LabeledContent("Složene vježbe") {
                    Text(Duration.seconds(settings.compoundRestSeconds), format: .time(pattern: .minuteSecond))
                }
            }
            Stepper(value: $settings.defaultRestSeconds, in: 15...600, step: 15) {
                LabeledContent("Ostale vježbe") {
                    Text(Duration.seconds(settings.defaultRestSeconds), format: .time(pattern: .minuteSecond))
                }
            }
        } header: {
            Text("Zadana pauza")
        } footer: {
            Text("Složene vježbe, poput čučnja, mrtvog dizanja i potiska, traže dulji odmor od izolacijskih. Pauza postavljena na vježbi ima prednost.")
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            Section {
                Toggle("Pokreni trening i na satu", isOn: $settings.startsWatchWorkout)
            } footer: {
                Text("Kad trening pokreneš na iPhoneu, Apple Watch mjeri puls i kalorije, ostaje otvoren tijekom treninga i vibrira na kraju odmora.")
            }
        }
        Section {
            Toggle("Rekordi (PR)", isOn: $settings.prEnabled)
            if settings.prEnabled {
                ForEach(PRSettingOption.allCases) { option in
                    Toggle(option.title, isOn: option.binding(for: settings))
                        .padding(.leading)
                }
                NavigationLink {
                    RecordExercisesScreen(settings: settings)
                } label: {
                    LabeledContent("Vježbe u rekordima", value: excludedSummary)
                }
            }
        } header: {
            Text("Rekordi")
        } footer: {
            Text("Rekord se računa od četvrtog izvođenja vježbe i kad je napredak barem 1 posto. Glavni rekord je procjena 1RM, a sažetak treninga ističe najviše tri rekorda.")
        }
        Section {
            Picker("Prikaz statistike", selection: $settings.statsDetail) {
                Text("Osnovni").tag(StatsDetail.basic)
                Text("Detaljni").tag(StatsDetail.pro)
            }
        } header: {
            Text("Statistika")
        } footer: {
            Text("""
                Detaljni prikaz dodaje savjete, mišiće (mapu i serije), trend snage, napor i intenzitet serija i \
                DOTS bodove. Na grafu vježbe dodaje 1RM, volumen, izbor raspona, usporedbu, tablicu rekorda po \
                ponavljanjima i relativnu snagu, a u treningu odmor između serija i ocjenu napora.
                """)
                + Text(verbatim: " ") + Text("DOTS bodovi se pojave kad je u Profilu odabran spol, a u Tijelu upisana tjelesna težina.")
        }
    }
}

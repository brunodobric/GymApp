import Models
import SwiftUI
import Training
import Units

/// Postavke treninga: jedinice, zadana pauza, RPE ili RIR, zvuk kraja odmora i rekordi.
struct TrainingSettingsSection: View {
    @Bindable var settings: UserSettings

    var body: some View {
        Section {
            Picker("Jedinice", selection: $settings.weightUnit) {
                Text("Kilogrami").tag(WeightUnit.kilograms)
                Text("Funte").tag(WeightUnit.pounds)
            }
            Stepper(value: $settings.defaultRestSeconds, in: 15...600, step: 15) {
                LabeledContent("Zadana pauza") {
                    Text(Duration.seconds(settings.defaultRestSeconds), format: .time(pattern: .minuteSecond))
                }
            }
            Picker("Napor", selection: $settings.effortScale) {
                Text("RPE").tag(EffortScale.rpe)
                Text("RIR").tag(EffortScale.rir)
            }
            Toggle("Zvuk kraja odmora", isOn: $settings.restEndSoundEnabled)
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            Section {
                Toggle("Pokreni trening i na satu", isOn: $settings.startsWatchWorkout)
            } footer: {
                Text("Kad trening pokreneš na iPhoneu, Apple Watch mjeri puls i kalorije, ostaje otvoren tijekom treninga i vibrira na kraju odmora.")
            }
        }
        Section("Rekordi") {
            Toggle("Rekordi (PR)", isOn: $settings.prEnabled)
            if settings.prEnabled {
                ForEach(PRSettingOption.allCases) { option in
                    Toggle(option.title, isOn: option.binding(for: settings))
                        .padding(.leading)
                }
            }
        }
    }
}

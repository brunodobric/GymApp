import Catalog
import Models
import SwiftData
import SwiftUI
import Units

/// Vlastiti korak težine vježbe na stranici vježbe. "Prema opremi" znači korak iz Postavki > Korak težine.
/// Vrijedi za kotačić, gumbe + i − u Live Activityju i na Početnoj te krunu na satu.
struct ExerciseWeightStepRow: View {
    let exercise: ExerciseRef
    let equipment: Equipment?

    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings? { UserSettings.preferred(in: settingsList) }
    private var unit: WeightUnit { settings?.weightUnit ?? .kilograms }
    private var steps: WeightStepSettings { settings?.weightSteps ?? WeightStepSettings() }

    var body: some View {
        let equipmentStep = steps.step(for: equipment, unit: unit)
        Picker("Korak težine", selection: selection) {
            Text("Prema opremi (\(WeightStepText.text(equipmentStep, unit: unit)))").tag(Double?.none)
            ForEach(WeightStepSettings.choices(for: unit), id: \.self) { step in
                Text(verbatim: WeightStepText.text(step, unit: unit)).tag(Double?.some(step))
            }
        }
    }

    private var selection: Binding<Double?> {
        Binding(
            get: { steps.override(forExercise: exercise.key, unit: unit) },
            set: { step in
                guard let settings = settings ?? (try? GymQueries(context: context).settings()) else { return }
                var steps = settings.weightSteps
                steps.setOverride(step, forExercise: exercise.key, unit: unit)
                settings.weightSteps = steps
                try? context.save()
            }
        )
    }
}

extension ExerciseInputType {
    /// Vrsta unosa s težinom (težina, dodatna težina ili pomoć), za koju korak težine ima smisla.
    var hasWeight: Bool {
        self == .weightReps || self == .weightedBodyweight || self == .assisted
    }
}

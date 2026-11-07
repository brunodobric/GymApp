import Catalog
import Models
import Stats
import SwiftUI
import Training
import Units

// MARK: - Rekordi

extension PRKind {
    var title: String {
        switch self {
        case .estimatedOneRepMax: String(localized: "Procjena 1RM")
        case .repMax: String(localized: "Najteža serija")
        case .maxWeight: String(localized: "Najveća težina")
        case .exerciseVolume: String(localized: "Volumen vježbe")
        case .maxReps: String(localized: "Najviše ponavljanja")
        case .lowestAssistance: String(localized: "Najmanja pomoć")
        case .longestDuration: String(localized: "Najduže trajanje")
        case .longestDistance: String(localized: "Najveća udaljenost")
        }
    }
}

enum RecordFormat {
    static func value(_ record: PersonalRecord, unit: WeightUnit) -> String {
        let formatter = WeightFormatter(unit: unit)
        switch record.kind {
        case .estimatedOneRepMax, .maxWeight, .exerciseVolume, .lowestAssistance:
            return formatter.string(fromKilograms: record.value)
        case .repMax:
            let weight = formatter.string(fromKilograms: record.value)
            return String(localized: "\(weight) × \(record.reps ?? 1)")
        case .maxReps:
            return String(localized: "\(Int(record.value)) pon.")
        case .longestDuration:
            return DurationInput.format(Int(record.value))
        case .longestDistance:
            return record.value >= 1000
                ? String(localized: "\((record.value / 1000).formatted(.number.precision(.fractionLength(0...2)))) km")
                : String(localized: "\(Int(record.value)) m")
        }
    }

    /// Naslov rekorda; za rekord po ponavljanjima s rasponom ("Najteža serija od 5 ponavljanja").
    static func title(_ record: PersonalRecord) -> String {
        guard record.kind == .repMax, let reps = record.reps else { return record.kind.title }
        return String(localized: "Najteža serija od \(reps)+ ponavljanja")
    }

    /// Napredak prema dosadašnjem najboljem, npr. "+2,8 %". Za pomoć je manje bolje.
    static func change(_ record: PersonalRecord) -> String? {
        guard let previous = record.previousBest, previous > 0, record.value > 0 else { return nil }
        let change = record.kind == .lowestAssistance ? previous / record.value - 1 : record.value / previous - 1
        return ChangeFormat.percent(change)
    }
}

enum ChangeFormat {
    /// Relativna promjena s predznakom, npr. "+2,8 %" ili "−1 %".
    static func percent(_ change: Double) -> String {
        change.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    static func color(_ change: Double?, threshold: Double = 0.005) -> Color {
        guard let change else { return .secondary }
        return change >= threshold ? .green : change <= -threshold ? .red : .secondary
    }
}

// MARK: - Status i pregled

extension ExerciseStatus {
    var title: String {
        switch self {
        case .improving: String(localized: "Napreduje")
        case .stable: String(localized: "Stoji")
        case .plateau: String(localized: "Plato")
        case .declining: String(localized: "Pada")
        case .insufficientData: String(localized: "Premalo podataka")
        }
    }

    var systemImage: String {
        switch self {
        case .improving: "arrow.up.right"
        case .stable: "arrow.right"
        case .plateau: "equal"
        case .declining: "arrow.down.right"
        case .insufficientData: "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .improving: .green
        case .stable: .secondary
        case .plateau: .orange
        case .declining: .red
        case .insufficientData: .secondary
        }
    }
}

extension ReviewLevel {
    var title: String {
        switch self {
        case .good: String(localized: "Dobro")
        case .fair: String(localized: "Može bolje")
        case .attention: String(localized: "Treba pažnju")
        case .noData: String(localized: "Nema podataka")
        }
    }

    var systemImage: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .fair: "minus.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .noData: "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .good: .green
        case .fair: .yellow
        case .attention: .orange
        case .noData: .secondary
        }
    }
}

extension Suggestion {
    /// Tekst prijedloga i kratko objašnjenje s izvorom.
    var text: (title: String, detail: String) {
        switch self {
        case let .deload(exercises):
            return (
                String(localized: "Napravi lakši tjedan"),
                String(localized: "Procjena 1RM pada na \(exercises) vježbe. Tjedan s pola serija i lakšom težinom pomaže oporavku (Bell i sur. 2023).")
            )
        case let .fewerDays(perWeek, planned):
            let average = perWeek.formatted(.number.precision(.fractionLength(0...1)))
            return (
                String(localized: "Probaj raspored s manje dana"),
                String(localized: "U zadnja 4 tjedna prosjek je \(average) treninga tjedno od planiranih \(planned) ukupno. Raspored koji stvarno odradiš daje više od zahtjevnijeg.")
            )
        case let .addSets(region, exercise):
            return (
                String(localized: "Dodaj 2 serije tjedno: \(BodyRegion.title(region))"),
                String(localized: "\(exercise) stoji 4 tjedna, a mišić ima manje od 10 tvrdih serija tjedno. Više serija daje više napretka (Pelland i sur. 2024).")
            )
        case let .reduceVolume(region, exercise):
            return (
                String(localized: "Smanji volumen: \(BodyRegion.title(region))"),
                String(localized: "\(exercise) stoji 4 tjedna uz više od 20 tvrdih serija tjedno. Manje serija ili lakši tjedan može pomoći oporavku.")
            )
        case let .increaseLoad(exercise):
            return (
                String(localized: "Povećaj težinu: \(exercise)"),
                String(localized: "Zadnja tri treninga s istom težinom imala su 4 ili više ponavljanja u rezervi. Dodaj jedan korak težine.")
            )
        case let .missedMuscle(region, days):
            return (
                String(localized: "\(BodyRegion.title(region)): \(days) dana bez treninga"),
                String(localized: "Mišić je ranije bio u treninzima. Ako to nije namjerno, vrati ga u raspored.")
            )
        }
    }
}

// MARK: - Serija

enum SetFormat {
    /// Kratki zapis serije, npr. "80 kg × 8".
    static func text(_ set: SetValues, inputType: ExerciseInputType, unit: WeightUnit) -> String {
        let formatter = WeightFormatter(unit: unit)
        let reps = set.reps ?? 0
        switch inputType {
        case .weightReps:
            return "\(formatter.string(fromKilograms: set.weightKg ?? 0)) × \(reps)"
        case .bodyweight:
            return "× \(reps)"
        case .weightedBodyweight:
            return "+\(formatter.string(fromKilograms: set.extraWeightKg ?? 0)) × \(reps)"
        case .assisted:
            return "−\(formatter.string(fromKilograms: set.extraWeightKg ?? 0)) × \(reps)"
        case .duration:
            return DurationInput.format(set.durationSeconds ?? 0)
        case .durationDistance:
            let time = DurationInput.format(set.durationSeconds ?? 0)
            guard let meters = set.distanceMeters else { return time }
            return "\(time) · \(NumberInput.format(meters / 1000)) km"
        }
    }

    static func rest(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}

// MARK: - Retci za sažetak i detalje treninga

/// Rezultat vježbe: najbolja serija, procjena 1RM i promjena prema prošlom izvođenju; u detaljnom prikazu i odmor.
struct ExerciseResultRow: View {
    let result: ExerciseResult
    let unit: WeightUnit
    let showsRest: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.itemTitle)
                if let best = result.bestSet {
                    Text(SetFormat.text(best, inputType: result.inputType, unit: unit))
                        .font(.rowValueSmall).foregroundStyle(.secondary)
                }
                if showsRest, let rest = result.restSeconds {
                    Text("Odmor oko \(SetFormat.rest(rest))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let oneRepMax = result.oneRepMaxKg {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("1RM ≈ \(WeightFormatter(unit: unit).string(fromKilograms: oneRepMax))")
                        .font(.rowValueSmall)
                    if let change = result.change {
                        Text(ChangeFormat.percent(change))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ChangeFormat.color(change))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Usporedba s prošlim izvođenjem istog treninga.
struct SessionComparisonSection: View {
    let comparison: SessionComparison
    let unit: WeightUnit

    var body: some View {
        Section {
            LabeledContent("Tvrde serije", value: setsText)
            if let change = comparison.volumeChange {
                LabeledContent("Tonaža") {
                    Text(ChangeFormat.percent(change)).foregroundStyle(ChangeFormat.color(change))
                }
            }
            if let now = comparison.durationSeconds, let before = comparison.previousDurationSeconds {
                LabeledContent("Trajanje", value: minutesText(now - before))
            }
        } header: {
            Text("Prema prošlom treningu")
        } footer: {
            Text("Isti trening \(comparison.previousDate.formatted(date: .abbreviated, time: .omitted)).")
        }
    }

    private var setsText: String {
        let difference = comparison.hardSets - comparison.previousHardSets
        guard difference != 0 else { return String(localized: "Isto (\(comparison.hardSets))") }
        return String(localized: "\(comparison.hardSets) (\(difference.formatted(.number.sign(strategy: .always()))))")
    }

    private func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes != 0 else { return String(localized: "Isto") }
        return String(localized: "\(minutes.formatted(.number.sign(strategy: .always()))) min")
    }
}

/// Istaknuti rekord u sažetku treninga.
struct RecordHighlightRow: View {
    let exerciseName: String
    let record: PersonalRecord
    let unit: WeightUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName).font(.itemTitle)
                    Text(RecordFormat.title(record)).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RecordFormat.value(record, unit: unit)).font(.rowValueSmall)
                if let change = RecordFormat.change(record) {
                    Text(change).font(.caption.monospacedDigit()).foregroundStyle(.green)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

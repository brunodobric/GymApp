import Charts
import Models
import Stats
import SwiftUI
import Units

/// Savjeti za zadnja 4 tjedna: ocjena četiri dijela (snaga, volumen, redovitost, napor) i prijedlog za dalje.
/// Brojke iza ocjena su na svojim karticama (Pregled, Mišići, Trend snage), pa se ovdje ne ponavljaju; uz
/// ocjenu stoji samo uputa kad podataka nema. Dio detaljnog prikaza.
struct WeeklyReviewCard: View {
    let review: WeeklyReview
    let suggestions: [Suggestion]

    var body: some View {
        StatisticsCard(title: "Savjeti") {
            HStack {
                Text("Zadnja 4 tjedna")
                if review.ratedCount > 0 {
                    Spacer()
                    Text("Dobro: \(review.goodCount) od \(review.ratedCount)")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                row("Snaga", level: review.strength.level, hint: Text("Treba barem 4 izvođenja iste vježbe u 8 tjedana."))
                row("Volumen", level: review.volume.level, hint: Text("Još nema tvrdih serija."))
                row("Redovitost", level: review.consistency.level, hint: nil)
                row("Napor", level: review.effort.level, hint: Text("Upiši RPE ili RIR u barem 10 serija."))
            }
            if !suggestions.isEmpty {
                Divider()
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                    let text = suggestion.text
                    VStack(alignment: .leading, spacing: 2) {
                        Label(text.title, systemImage: "lightbulb")
                            .font(.subheadline.weight(.semibold))
                        Text(text.detail)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Savjeti su opći i temelje se na istraživanjima treninga snage, nisu medicinska preporuka.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func row(_ title: LocalizedStringKey, level: ReviewLevel, hint: Text?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: level.systemImage)
                .foregroundStyle(level.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(level.title).font(.caption).foregroundStyle(.secondary)
                }
                if level == .noData, let hint {
                    hint.font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Napor i intenzitet radnih serija u zadnja 4 tjedna (detaljni prikaz): ponavljanja u rezervi ili udio
/// najbolje procjene 1RM vježbe, s izborom prikaza.
struct EffortIntensityCard: View {
    let effort: EffortDistribution
    let intensity: IntensityDistribution

    private enum Mode: Hashable { case effort, intensity }
    @State private var mode: Mode?

    private struct Entry: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    /// Bez izbora korisnika prikazuje se napor kad ima ocijenjenih serija, inače intenzitet.
    private var shownMode: Mode { mode ?? (effort.rated > 0 ? .effort : .intensity) }

    private var effortEntries: [Entry] {
        ["0", "1", "2", "3", "4+"].enumerated().map { Entry(label: $1, count: effort.counts[$0]) }
    }

    private var intensityEntries: [Entry] {
        ["< 60 %", "60–75 %", "75–85 %", "> 85 %"].enumerated().map { Entry(label: $1, count: intensity.counts[$0]) }
    }

    private var effortFootnote: String {
        let research = String(
            localized: "Ponavljanja u rezervi, zadnja 4 tjedna. Za rast mišića najbolje rade serije blizu otkaza (0 do 3), a za snagu blizina otkaza manje znači (Robinson i sur. 2024)."
        )
        return research + " " + String(localized: "Bez ocjene: \(effort.unrated).")
    }

    var body: some View {
        StatisticsCard(title: "Napor i intenzitet") {
            Picker("Prikaz", selection: Binding(get: { shownMode }, set: { mode = $0 })) {
                Text("Napor").tag(Mode.effort)
                Text("Intenzitet").tag(Mode.intensity)
            }
            .pickerStyle(.segmented)
            switch shownMode {
            case .effort:
                if effort.rated == 0 {
                    Text("Upiši RPE ili RIR uz serije da vidiš koliko blizu otkaza treniraš.")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(effortEntries) { entry in
                        BarMark(x: .value("Ponavljanja u rezervi", entry.label), y: .value("Serije", entry.count))
                    }
                    .chartHeight(160, regular: 220)
                    .accessibilityLabel(Text("Graf serija po ponavljanjima u rezervi"))
                    Text(effortFootnote)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            case .intensity:
                if intensity.total == 0 {
                    Text("Intenzitet se pojavi uz vježbe s težinom.").foregroundStyle(.secondary)
                } else {
                    Chart(intensityEntries) { entry in
                        BarMark(x: .value("Udio 1RM", entry.label), y: .value("Serije", entry.count))
                    }
                    .chartHeight(160, regular: 220)
                    .accessibilityLabel(Text("Graf serija po udjelu procjene 1RM"))
                    Text("Težina serije prema najboljoj procjeni 1RM vježbe, zadnja 4 tjedna. Iznad 85 posto je trening maksimalne snage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// DOTS bodovi iz čučnja, potiska s klupe i mrtvog dizanja (detaljni prikaz). Kartica se prikaže tek kad su
/// upisani spol i tjelesna težina i kad u zadnjih 12 tjedana ima barem jedno od tri dizanja.
struct DotsCard: View {
    let score: DotsScore
    let unit: WeightUnit

    var body: some View {
        StatisticsCard(title: "DOTS bodovi") {
            if let points = score.points {
                Text(points.formatted(.number.precision(.fractionLength(0))))
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Dots.lifts, id: \.self) { lift in
                    LabeledContent(Self.title(of: lift)) {
                        if let kilograms = score.liftsKg[lift] {
                            Text(WeightFormatter(unit: unit).string(fromKilograms: kilograms)).font(.rowValueSmall)
                        } else {
                            Text("Nije rađeno").foregroundStyle(.secondary)
                        }
                    }
                }
                if let total = score.totalKg {
                    LabeledContent("Zbroj") {
                        Text(WeightFormatter(unit: unit).string(fromKilograms: total)).font(.rowValueSmall)
                    }
                }
            }
            Text(footnote(score)).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func footnote(_ score: DotsScore) -> String {
        let weight = WeightFormatter(unit: unit).string(fromKilograms: score.bodyWeightKg)
        let explanation = String(
            localized: "Zbroj najbolje procjene 1RM triju dizanja u zadnjih 12 tjedana, prilagođen tjelesnoj težini (\(weight)). Služi za usporedbu s drugima; za vlastiti napredak gledaj trend vježbe."
        )
        guard score.points == nil else { return explanation }
        return String(localized: "Bodovi se računaju kad su u razdoblju rađena sva tri dizanja.") + " " + explanation
    }

    static func title(of lift: String) -> LocalizedStringKey {
        switch lift {
        case "barbell-squat": "Čučanj"
        case "barbell-bench-press": "Potisak s klupe"
        default: "Mrtvo dizanje"
        }
    }
}

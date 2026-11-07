import Charts
import Models
import Stats
import SwiftUI
import Units

/// Tjedni pregled: četiri dijela (snaga, volumen, redovitost, napor) i prijedlog za dalje. Osnovni prikaz
/// pokazuje jedan prijedlog, detaljni sve s objašnjenjem i zbroj dobrih dijelova.
struct WeeklyReviewCard: View {
    let review: WeeklyReview
    let suggestions: [Suggestion]
    let isPro: Bool

    var body: some View {
        StatisticsCard(title: "Zadnja 4 tjedna") {
            if isPro, review.ratedCount > 0 {
                Text("Dobro: \(review.goodCount) od \(review.ratedCount)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                row("Snaga", level: review.strength.level, detail: strengthDetail)
                row("Volumen", level: review.volume.level, detail: volumeDetail)
                row("Redovitost", level: review.consistency.level, detail: consistencyDetail)
                row("Napor", level: review.effort.level, detail: effortDetail)
            }
            let shown = isPro ? suggestions : Array(suggestions.prefix(1))
            if !shown.isEmpty {
                Divider()
                ForEach(Array(shown.enumerated()), id: \.offset) { _, suggestion in
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

    private func row(_ title: LocalizedStringKey, level: ReviewLevel, detail: String) -> some View {
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
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var strengthDetail: String {
        let strength = review.strength
        guard strength.level != .noData else {
            return String(localized: "Treba barem 4 izvođenja iste vježbe u 8 tjedana.")
        }
        var text = String(localized: "Napreduje \(strength.improving), stoji \(strength.stable), plato \(strength.plateau), pada \(strength.declining).")
        if isPro, let change = strength.medianMonthlyChange {
            text += " " + String(localized: "Medijan \(ChangeFormat.percent(change)) mjesečno.")
        }
        return text
    }

    private var volumeDetail: String {
        let volume = review.volume
        guard volume.level != .noData else { return String(localized: "Još nema tvrdih serija.") }
        let lower = Int(volume.zone.lowerBound)
        if volume.zone.upperBound <= 20 {
            let upper = Int(volume.zone.upperBound)
            return String(localized: "\(volume.inZone) od \(volume.regions) glavnih mišića ima \(lower) do \(upper) tvrdih serija tjedno.")
        }
        return String(localized: "\(volume.inZone) od \(volume.regions) glavnih mišića ima barem \(lower) tvrdih serija tjedno.")
    }

    private var consistencyDetail: String {
        let consistency = review.consistency
        let average = consistency.sessionsPerWeek.formatted(.number.precision(.fractionLength(0...1)))
        if let planned = consistency.planned {
            return String(localized: "\(consistency.sessions) od \(planned) planiranih treninga, prosjek \(average) tjedno.")
        }
        return String(localized: "Prosjek \(average) treninga tjedno.")
    }

    private var effortDetail: String {
        let effort = review.effort
        guard let share = effort.closeToFailureShare else {
            return String(localized: "Upiši RPE ili RIR u barem 10 serija.")
        }
        let percent = share.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(percent) serija s 0 do 3 ponavljanja u rezervi.")
    }
}

/// Raspodjela radnih serija po ponavljanjima u rezervi, zadnja 4 tjedna (detaljni prikaz).
struct EffortCard: View {
    let distribution: EffortDistribution

    private struct Entry: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    private var entries: [Entry] {
        ["0", "1", "2", "3", "4+"].enumerated().map { Entry(label: $1, count: distribution.counts[$0]) }
    }

    private var footnote: String {
        let research = String(
            localized: "Ponavljanja u rezervi, zadnja 4 tjedna. Za rast mišića najbolje rade serije blizu otkaza (0 do 3), a za snagu blizina otkaza manje znači (Robinson i sur. 2024)."
        )
        return research + " " + String(localized: "Bez ocjene: \(distribution.unrated).")
    }

    var body: some View {
        StatisticsCard(title: "Napor serija") {
            if distribution.rated == 0 {
                Text("Upiši RPE ili RIR uz serije da vidiš koliko blizu otkaza treniraš.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(entries) { entry in
                    BarMark(x: .value("Ponavljanja u rezervi", entry.label), y: .value("Serije", entry.count))
                }
                .chartHeight(160, regular: 220)
                .accessibilityLabel(Text("Graf serija po ponavljanjima u rezervi"))
                Text(footnote)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Raspodjela radnih serija po udjelu najbolje procjene 1RM vježbe, zadnja 4 tjedna (detaljni prikaz).
struct IntensityCard: View {
    let distribution: IntensityDistribution

    private struct Entry: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    private var entries: [Entry] {
        ["< 60 %", "60–75 %", "75–85 %", "> 85 %"].enumerated().map { Entry(label: $1, count: distribution.counts[$0]) }
    }

    var body: some View {
        StatisticsCard(title: "Intenzitet serija") {
            if distribution.total == 0 {
                Text("Intenzitet se pojavi uz vježbe s težinom.").foregroundStyle(.secondary)
            } else {
                Chart(entries) { entry in
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

/// DOTS bodovi iz čučnja, potiska s klupe i mrtvog dizanja (detaljni prikaz). Trebaju spol i tjelesnu težinu.
struct DotsCard: View {
    let score: DotsScore?
    let sex: Sex?
    let hasBodyWeight: Bool
    let unit: WeightUnit

    var body: some View {
        StatisticsCard(title: "DOTS bodovi") {
            if sex == nil {
                Text("Odaberi spol u Postavkama, u dijelu Profil, da vidiš DOTS bodove.").foregroundStyle(.secondary)
            } else if !hasBodyWeight {
                Text("Upiši tjelesnu težinu u Tijelu da vidiš DOTS bodove.").foregroundStyle(.secondary)
            } else if let score {
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
            } else {
                Text("DOTS se pojavi kad u zadnjih 12 tjedana radiš čučanj, potisak s klupe ili mrtvo dizanje sa šipkom.")
                    .foregroundStyle(.secondary)
            }
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

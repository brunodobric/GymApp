import SwiftUI
import WidgetData
import WidgetKit

/// Tjelesna težina (prijedlog 3 i 9): zadnja vrijednost, promjena u 30 dana i krivulja zadnjih mjerenja.
/// Dodir otvara praćenje tijela, gdje se upisuje nova težina.
struct BodyWeightWidget: Widget {
    static let kind = "BodyWeight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            BodyWeightView(snapshot: entry.snapshot)
                .tint(entry.snapshot.accentColor)
                .containerBackground(for: .widget) { CardBackground() }
                .widgetURL(WidgetLink.bodyWeight.url)
        }
        .configurationDisplayName("Težina")
        .description("Zadnja izmjerena težina i promjena u 30 dana.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct BodyWeightView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            circular
        } else {
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeading("Težina", symbol: "figure.stand")
            if let weight = snapshot.bodyWeight {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(snapshot.weightFormatter.number(fromKilograms: weight.latestKg)).font(.metric)
                    Text(snapshot.weightUnit.symbol).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                if let change = weight.changeKg {
                    Text("\(changeText(change)) u 30 dana")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Sparkline(points: weight.normalizedPoints)
                    .frame(height: 36)
            } else {
                Spacer(minLength: 0)
                Text("Upiši težinu").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let weight = snapshot.bodyWeight {
                VStack(spacing: -2) {
                    Text(snapshot.weightUnit.symbol).font(.caption2)
                    Text(snapshot.weightFormatter.number(fromKilograms: weight.latestKg))
                        .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                    if let change = weight.changeKg {
                        Text(verbatim: signed(change)).font(.caption2.monospacedDigit())
                    }
                }
                .padding(4)
            } else {
                Image(systemName: "figure.stand").font(.title3)
            }
        }
        .widgetAccentable()
    }

    /// Promjena s predznakom i jedinicom, npr. "−0,6 kg".
    private func changeText(_ change: Double) -> String {
        "\(signed(change)) \(snapshot.weightUnit.symbol)"
    }

    private func signed(_ change: Double) -> String {
        let number = snapshot.weightFormatter.number(fromKilograms: abs(change))
        if number == snapshot.weightFormatter.number(fromKilograms: 0) { return number }
        return change > 0 ? "+\(number)" : "−\(number)"
    }
}

/// Krivulja zadnjih mjerenja: točke su između 0 (najniža) i 1 (najviša), zadnja je istaknuta.
struct Sparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if points.count >= 2 {
                let step = size.width / CGFloat(points.count - 1)
                let location = { (index: Int) in
                    CGPoint(x: CGFloat(index) * step, y: (1 - CGFloat(points[index])) * (size.height - 6) + 3)
                }
                Path { path in
                    path.move(to: location(0))
                    for index in points.indices.dropFirst() {
                        path.addLine(to: location(index))
                    }
                }
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .widgetAccentable()
                Circle()
                    .fill(.tint)
                    .frame(width: 7, height: 7)
                    .position(location(points.count - 1))
                    .widgetAccentable()
            }
        }
        .accessibilityHidden(true)
    }
}

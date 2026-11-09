import Connectivity
import Models
import SwiftUI
import Training

// Zajednički dijelovi izgleda na satu, usklađeni s aplikacijom na iPhoneu: naglasna boja iz postavki,
// ikona vrste treninga, oznaka broja serije i zaglavlje s trajanjem i pulsom.

extension AccentChoice {
    /// Ista boja kao na iPhoneu (`AccentChoice.color` u aplikaciji).
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
}

extension SessionMix {
    var title: LocalizedStringKey {
        switch self {
        case .strength: "Snaga"
        case .cardio: "Kardio"
        case .mixed: "Snaga + kardio"
        }
    }
}

/// Ikona vrste treninga kao na iPhoneu (`WorkoutKindIcon`): bučica, trčanje ili bučica s oznakom trčanja.
struct WatchWorkoutMixIcon: View {
    let mix: SessionMix

    var body: some View {
        Group {
            switch mix {
            case .strength:
                Image(systemName: "dumbbell.fill")
            case .cardio:
                Image(systemName: "figure.run")
            case .mixed:
                Image(systemName: "dumbbell.fill")
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 9))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .background(Circle().fill(.black).padding(-1))
                            .offset(x: 5, y: 5)
                    }
            }
        }
        .foregroundStyle(.tint)
        .accessibilityLabel(Text(mix.title))
    }
}

/// Oznaka serije kao na iPhoneu: broj radne serije u krugu, a zagrijavanje je narančasto Z.
struct WatchSetBadge: View {
    let number: Int?
    var isCurrent = false
    @ScaledMetric(relativeTo: .footnote) var size: CGFloat = 22

    var body: some View {
        Group {
            if let number {
                Text(number, format: .number)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
            } else {
                Text("Z")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Zagrijavanje"))
            }
        }
        .font(.system(.footnote, design: .rounded, weight: .bold).monospacedDigit())
        .frame(width: size, height: size)
        .background(Circle().fill(number == nil ? Color.orange.opacity(0.2) : Color.white.opacity(0.14)))
    }
}

/// Trajanje treninga i puls u zaglavlju ekrana serije i odmora, da se vide bez listanja na kontrole.
struct WatchHeaderMetrics: View {
    @Environment(WatchWorkoutStore.self) private var store

    var body: some View {
        if let active = store.active {
            HStack(spacing: 6) {
                Text(active.startedAt, style: .timer)
                    .foregroundStyle(.yellow)
                if store.showsHealthMetrics {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").foregroundStyle(.red).imageScale(.small)
                        Text(store.health.heartRate.map { "\(Int($0.rounded()))" } ?? "–")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
            .lineLimit(1)
        }
    }
}

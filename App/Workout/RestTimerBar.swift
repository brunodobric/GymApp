import Foundation
import SwiftUI
import Training

/// Traka rest timera pri dnu ekrana, kao zaobljeni otok: oznaka "Odmor" i veliko odbrojavanje lijevo,
/// okrugli −10 i +10 i Preskoči desno, a vrijeme koje teče je tanka linija uz gornji rub.
struct RestTimerBar: View {
    let timer: RestTimer
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void
    let onExpire: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Kod najvećih veličina teksta gumbi idu ispod odbrojavanja.
                VStack(alignment: .leading, spacing: 10) {
                    countdown
                    HStack(spacing: 10) { buttons }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    countdown
                    Spacer(minLength: 8)
                    buttons
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.vertical, 14)
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .overlay(alignment: .top) { progressLine }
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 12)
        // Pri istjeku (ili promjeni završetka zbog +10 / −10) čeka se do novog trenutka.
        .task(id: timer.endsAt) {
            let wait = timer.remaining(at: Date())
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { onExpire() }
        }
    }

    /// Tanka linija uz gornji rub otoka koja se prazni kako odmor teče.
    private var progressLine: some View {
        ProgressView(timerInterval: timer.startedAt...max(timer.endsAt, timer.startedAt.addingTimeInterval(1)), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .accessibilityHidden(true)
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Odmor")
                .font(.caption.bold())
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(timer.endsAt, style: .timer)
                .font(.largeTitle.bold().monospacedDigit())
                .frame(minWidth: 80, alignment: .leading)
                .accessibilityLabel(Text("Preostali odmor"))
                .accessibilityValue(Text(timer.endsAt, style: .timer))
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("−10") { onAdjust(-10) }
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Skrati odmor za 10 sekundi"))
        Button("+10") { onAdjust(10) }
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Produlji odmor za 10 sekundi"))
        Button("Preskoči", action: onSkip)
            .buttonBorderShape(.capsule)
    }
}

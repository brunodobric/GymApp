import Foundation
import SwiftUI
import Training

/// Traka rest timera pri dnu ekrana: odbrojavanje, linija koja teče, +10 / −10 i preskakanje.
struct RestTimerBar: View {
    let timer: RestTimer
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void
    let onExpire: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                // Kod najvećih veličina teksta gumbi idu ispod odbrojavanja.
                countdown
                HStack(spacing: 12) { buttons }
                    .buttonStyle(.bordered)
            } else {
                HStack(spacing: 12) {
                    countdown
                    Spacer()
                    buttons
                }
                .buttonStyle(.bordered)
            }

            ProgressView(timerInterval: timer.startedAt...max(timer.endsAt, timer.startedAt.addingTimeInterval(1)), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .padding(.horizontal)
        // Pri istjeku (ili promjeni završetka zbog +10 / −10) čeka se do novog trenutka.
        .task(id: timer.endsAt) {
            let wait = timer.remaining(at: Date())
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { onExpire() }
        }
    }

    private var countdown: some View {
        Text(timer.endsAt, style: .timer)
            .font(.title2.bold().monospacedDigit())
            .frame(minWidth: 70, alignment: .leading)
            .accessibilityLabel(Text("Preostali odmor"))
            .accessibilityValue(Text(timer.endsAt, style: .timer))
    }

    @ViewBuilder
    private var buttons: some View {
        Button("−10") { onAdjust(-10) }
            .accessibilityLabel(Text("Skrati odmor za 10 sekundi"))
        Button("+10") { onAdjust(10) }
            .accessibilityLabel(Text("Produlji odmor za 10 sekundi"))
        Button("Preskoči", systemImage: "forward.end.fill", action: onSkip)
            .labelStyle(.iconOnly)
    }
}

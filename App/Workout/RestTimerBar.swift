import Foundation
import SwiftUI
import Training

/// Traka rest timera pri dnu ekrana: odbrojavanje, linija koja teče, +10 / −10 i preskakanje.
struct RestTimerBar: View {
    let timer: RestTimer
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void
    let onExpire: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(timer.endsAt, style: .timer)
                    .font(.title2.bold().monospacedDigit())
                    .frame(minWidth: 70, alignment: .leading)
                Spacer()
                Button("−10") { onAdjust(-10) }
                    .accessibilityLabel(Text("Skrati odmor za 10 sekundi"))
                Button("+10") { onAdjust(10) }
                    .accessibilityLabel(Text("Produlji odmor za 10 sekundi"))
                Button("Preskoči", systemImage: "forward.end.fill", action: onSkip)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)

            ProgressView(timerInterval: timer.startedAt...max(timer.endsAt, timer.startedAt.addingTimeInterval(1)), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        // Pri istjeku (ili promjeni završetka zbog +10 / −10) čeka se do novog trenutka.
        .task(id: timer.endsAt) {
            let wait = timer.remaining(at: Date())
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { onExpire() }
        }
    }
}

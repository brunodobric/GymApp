import Catalog
import SwiftUI

/// Crtež vježbe (Everkinetic, CC BY-SA 4.0) koji se u krug pretapa iz početnog u završni položaj i natrag.
/// Uz Smanji kretanje nema animacije: oba položaja stoje jedan do drugoga.
/// Crteži su template slike, pa linije prate boju teksta: tamne u svijetlom, a svijetle u tamnom načinu.
struct ExerciseDrawingView: View {
    let start: String
    let end: String
    let accessibilityText: String
    var timing: DrawingLoopTiming = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startDate = Date.now
    @State private var isVisible = false

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 12) {
                    pose(start, label: "Početni položaj")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    pose(end, label: "Završni položaj")
                }
            } else {
                // Animacija stoji dok crtež nije na ekranu ili je aplikacija u pozadini.
                TimelineView(.animation(paused: !isVisible || scenePhase != .active)) { context in
                    let endOpacity = timing.endOpacity(at: context.date.timeIntervalSince(startDate))
                    ZStack {
                        drawing(start).opacity(1 - endOpacity)
                        drawing(end).opacity(endOpacity)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
        .onAppear {
            startDate = .now
            isVisible = true
        }
        .onDisappear { isVisible = false }
    }

    private func drawing(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }

    private func pose(_ name: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            drawing(name)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

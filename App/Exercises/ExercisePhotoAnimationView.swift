import Catalog
import SwiftUI
import UIKit

/// Animacija vježbe od dviju fotografija (free-exercise-db): početni i završni položaj
/// se u krug pretapaju jedan u drugi. Gumb u kutu pauzira i nastavlja animaciju.
/// Uz Smanji kretanje nema animacije: oba položaja stoje jedan do drugoga.
struct ExercisePhotoAnimationView: View {
    let start: URL
    let end: URL
    let accessibilityText: String
    var timing: PoseLoopTiming = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var images: (start: UIImage, end: UIImage)?
    @State private var clock = PoseLoopClock()
    @State private var isVisible = false
    @State private var isPausedByUser = false

    /// Animacija teče samo dok je na ekranu, aplikacija je aktivna i korisnik je nije pauzirao.
    private var shouldRun: Bool {
        isVisible && scenePhase == .active && !isPausedByUser && !reduceMotion
    }

    var body: some View {
        Group {
            if let images {
                if reduceMotion {
                    HStack(spacing: 8) {
                        pose(images.start, label: "Početni položaj")
                        pose(images.end, label: "Završni položaj")
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText)
                    .accessibilityAddTraits(.isImage)
                } else {
                    animation(images)
                }
            } else {
                Color(.tertiarySystemFill)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .accessibilityHidden(true)
            }
        }
        .task(id: [start, end]) {
            images = await Self.load(start: start, end: end)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: shouldRun, initial: true) { _, running in
            if running {
                clock.start(at: .now)
            } else {
                clock.pause(at: .now)
            }
        }
    }

    private func animation(_ images: (start: UIImage, end: UIImage)) -> some View {
        TimelineView(.animation(paused: !shouldRun)) { context in
            let endOpacity = timing.endOpacity(at: clock.elapsed(at: context.date))
            ZStack {
                photo(images.start).opacity(1 - endOpacity)
                photo(images.end).opacity(endOpacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
        .overlay(alignment: .bottomTrailing) {
            pauseButton
                .padding(10)
        }
    }

    private var pauseButton: some View {
        Button {
            isPausedByUser.toggle()
        } label: {
            if isPausedByUser {
                Label("Pokreni animaciju", systemImage: "play.fill")
            } else {
                Label("Pauziraj animaciju", systemImage: "pause.fill")
            }
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .frame(width: 44, height: 44)
        .background(.regularMaterial, in: Circle())
        .contentShape(Circle())
        .buttonStyle(.plain)
    }

    private func photo(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
    }

    private func pose(_ image: UIImage, label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            photo(image)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Fotografije se učitaju jednom, izvan glavne niti, a ne pri svakom kadru animacije.
    private static func load(start: URL, end: URL) async -> (start: UIImage, end: UIImage)? {
        await Task.detached(priority: .userInitiated) { () -> (start: UIImage, end: UIImage)? in
            guard let first = UIImage(contentsOfFile: start.path),
                  let second = UIImage(contentsOfFile: end.path) else { return nil }
            return (first, second)
        }.value
    }
}

import AVFoundation
import SwiftUI
import UIKit

/// MoveKit klip vježbe u petlji, bez zvuka. Gumb u kutu pauzira i nastavlja.
///
/// Klip teče samo dok je na ekranu i aplikacija je aktivna. Uz Smanji kretanje klip ne kreće sam:
/// prikazuje se poster, a korisnik ga može pokrenuti gumbom.
struct ExerciseVideoView: View {
    let video: URL
    let poster: URL?
    let accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = LoopingPlayer()
    @State private var isVisible = false
    /// Korisnikov izbor; nil dok ga nije bilo (tada odlučuje Smanji kretanje).
    @State private var wantsPlaying: Bool?
    @State private var posterImage: UIImage?

    /// Omjer stranica MoveKit klipova (1936 × 1072).
    static let aspectRatio: CGFloat = 1936 / 1072

    private var isPlaying: Bool {
        isVisible && scenePhase == .active && (wantsPlaying ?? !reduceMotion)
    }

    var body: some View {
        ZStack {
            Color(white: 0.93)
            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFit()
            }
            PlayerLayerView(player: player.player)
                .opacity(player.hasStarted ? 1 : 0)
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
        .overlay(alignment: .bottomTrailing) {
            playButton
                .padding(10)
        }
        .task(id: poster) {
            guard let poster else { return }
            posterImage = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: poster.path)
            }.value
        }
        .onAppear {
            player.load(video)
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onChange(of: isPlaying, initial: true) { _, playing in
            if playing { player.play() } else { player.pause() }
        }
    }

    private var playButton: some View {
        Button {
            wantsPlaying = !isPlaying
        } label: {
            if isPlaying {
                Label("Pauziraj animaciju", systemImage: "pause.fill")
            } else {
                Label("Pokreni animaciju", systemImage: "play.fill")
            }
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .foregroundStyle(.black)
        .frame(width: 44, height: 44)
        .background(.white.opacity(0.85), in: Circle())
        .contentShape(Circle())
        .buttonStyle(.plain)
    }
}

/// AVQueuePlayer s AVPlayerLooperom: klip se vrti bez pauze na kraju.
@MainActor
@Observable
final class LoopingPlayer {
    let player = AVQueuePlayer()
    private(set) var hasStarted = false
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        player.isMuted = true
        // Klip vježbe ne smije prekinuti glazbu koju korisnik sluša.
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
    }

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        loadedURL = url
        hasStarted = false
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing else { return }
            Task { @MainActor in self?.hasStarted = true }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }
}

/// Sloj za prikaz AVPlayera u SwiftUI-ju (VideoPlayer bi dodao kontrole koje ovdje ne trebaju).
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        // layerClass je AVPlayerLayer, pa je pretvorba uvijek uspješna.
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }
}

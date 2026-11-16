import AVKit
import SwiftUI

/// AVKit's own player (its audio menu, scrubber, picture in picture and AirPlay), no custom
/// controls. The view controller comes from `PlayerController`, which keeps it while picture in
/// picture plays with the cover hidden, so the cover coming back shows the same one.
struct PlayerView: UIViewControllerRepresentable {
    let controller: PlayerController
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        controller.playerViewController(for: player)
    }

    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        if viewController.player !== player { viewController.player = player }
    }
}

/// The full-screen cover: the player, a spinner while loading, or the error with Close. With
/// timing, a "Map" control beside Close shows the map and tower as floating panels over the
/// picture (inside the safe area), remembered per posture as in the multiview.
struct PlayerCover: View {
    let controller: PlayerController
    let fold: FoldState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = controller.player {
                PlayerView(controller: controller, player: player).ignoresSafeArea()
            }
            if controller.player != nil, controller.errorText == nil, !controller.isLoading {
                PlayerPanelsLayer(timing: controller.timing, fold: fold)
            }
            if controller.isLoading {
                // Covers a ready picture until playback starts ("From the start" seeks first).
                Color.black.ignoresSafeArea()
                ProgressView().controlSize(.large).tint(.white)
            }
            if let text = controller.errorText {
                VStack(spacing: 16) {
                    Text(text)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Close") { controller.close() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .padding(24)
            }
        }
        .overlay(alignment: .topLeading) {
            if controller.errorText == nil {
                HStack(spacing: 8) {
                    Button {
                        controller.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .accessibilityLabel("Close")
                    if controller.player != nil, !controller.isLoading {
                        TimingMapButton(timing: controller.timing, onInteraction: {})
                    }
                }
                .padding(12)
            }
        }
        .statusBarHidden(controller.player != nil)
    }
}

/// The floating panels over the single feed, only while one shows, so AVKit's own controls get
/// every touch otherwise. Its own view: the cover's body never reads the timing.
private struct PlayerPanelsLayer: View {
    let timing: TimingController
    let fold: FoldState

    var body: some View {
        if timing.showsData, !timing.panels.isEmpty {
            GeometryReader { proxy in
                FloatingPanels(
                    timing: timing,
                    bounds: CGRect(origin: .zero, size: proxy.size),
                    postureKey: PanelLayout.postureKey(posture: fold.posture.rawValue, size: proxy.size),
                    onCar: { _ in })
            }
        }
    }
}

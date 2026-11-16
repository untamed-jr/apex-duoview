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
/// picture (inside the safe area), remembered per posture as in the multiview. Tapping a car there
/// switches to its onboard at the same moment; an onboard shows its driver card under Close.
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
                PlayerPanelsLayer(controller: controller, fold: fold)
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
                VStack(alignment: .leading, spacing: 8) {
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
                    if controller.player != nil, !controller.isLoading {
                        PlayerCardLayer(controller: controller)
                    }
                }
                .padding(12)
            }
        }
        .overlay(alignment: .top) {
            PlayerNotice(controller: controller)
        }
        .statusBarHidden(controller.player != nil)
    }
}

/// The floating panels over the single feed, only while one shows, so AVKit's own controls get
/// every touch otherwise. Its own view: the cover's body never reads the timing.
private struct PlayerPanelsLayer: View {
    let controller: PlayerController
    let fold: FoldState

    var body: some View {
        let timing = controller.timing
        if timing.showsData, !timing.panels.isEmpty {
            GeometryReader { proxy in
                FloatingPanels(
                    timing: timing,
                    bounds: CGRect(origin: .zero, size: proxy.size),
                    postureKey: PanelLayout.postureKey(posture: fold.posture.rawValue, size: proxy.size),
                    onCar: { number in
                        // Racing numbers are whole numbers; anything else has no onboard.
                        guard let racingNumber = Int(number) else { return }
                        Task { await controller.showOnboard(racingNumber: racingNumber) }
                    })
            }
        }
    }
}

/// The onboard's driver card, under Close: its own view, so the cover's body never reads the
/// 2 Hz values. Long-press it for "Hide card".
private struct PlayerCardLayer: View {
    let controller: PlayerController

    var body: some View {
        if let onboard = controller.onboard, controller.timing.showsData {
            DriverCardSlot(timing: controller.timing, channelId: onboard.channelId, number: onboard.number)
        }
    }
}

/// Tap-a-car's notice ("No onboard for car 44 in this session."): tap it away, or it goes after 6 s.
private struct PlayerNotice: View {
    let controller: PlayerController

    var body: some View {
        if let text = controller.notice {
            Button {
                controller.dismissNotice()
            } label: {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 60)
            .padding(.horizontal, 16)
            .accessibilityHint("Dismisses this message")
        }
    }
}

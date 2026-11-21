import AVKit
import SwiftUI

/// The picture: a player layer, no controls of its own (`PlayerChrome` has the app's). Picture in
/// picture uses this layer. The view comes from `PlayerController`, which keeps it while picture in
/// picture plays with the cover hidden, so the cover coming back shows the same one.
struct PlayerView: UIViewRepresentable {
    let controller: PlayerController
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        controller.surfaceView(for: player)
    }

    func updateUIView(_ view: PlayerSurfaceView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// A view whose own layer is the `AVPlayerLayer`, so it resizes with the view.
final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // layerClass guarantees the type.
        layer as! AVPlayerLayer
    }
}

/// The full-screen cover: the player, a spinner while loading, or the error with Close, under the
/// app's own controls (`PlayerChrome`: ✕, Map, AirPlay, the scrubber, LIVE, speed and audio).
/// Map shows the map and tower as floating panels over the picture (inside the safe area),
/// remembered per posture as in the multiview. Tapping a car there switches to its onboard at the
/// same moment; an onboard shows its driver card under the top bar.
/// While a live programme plays, the next one that goes live is offered at the top
/// (`NextLivePrompt`).
struct PlayerCover: View {
    let controller: PlayerController
    let fold: FoldState
    /// For the next live programme's prompt.
    let model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = controller.player {
                PlayerView(controller: controller, player: player).ignoresSafeArea()
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
            // The error has its own Close.
            if controller.errorText == nil {
                PlayerChrome(controller: controller, fold: fold)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                // While a live programme plays: another one that went live (never in picture in
                // picture).
                NextLivePrompt(model: model, inPictureInPicture: controller.isInPictureInPicture)
                PlayerNotice(controller: controller)
            }
            .animation(.snappy, value: model.nextLive.offer?.contentId)
        }
        // Settings › Debug › "Show haptics on screen": "Haptic: Yellow flag" as one plays.
        .overlay(alignment: .top) {
            HapticDebugLabel(haptics: model.haptics, settings: model.companion)
                .padding(.top, 110)
        }
        .statusBarHidden(controller.player != nil)
        // The companion follows this player while it shows: haptics only (no pager, no cards); the
        // Radio panel is the chrome's.
        .onAppear { model.companionController.attach(host: controller) }
        .onDisappear { model.companionController.detach(host: controller) }
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

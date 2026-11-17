import F1TV
import SwiftUI

/// The next live programme (0.95): while a live programme is watched, F1 TV's "live now" list is
/// checked every 60 s (`AppModel`, `NextLiveState`); a programme that started since this one was
/// opened, or any live one once this broadcast has ended, is offered at the top of the video:
/// "Switch" opens it with the same multiview or single-feed choice, at the live edge; "Not now"
/// is remembered for that programme. Never in picture in picture.
struct NextLivePrompt: View {
    let model: AppModel
    /// The player is in picture in picture: the prompt waits.
    let inPictureInPicture: Bool
    /// Room above it for the player's own top controls.
    var topInset: CGFloat = 56

    var body: some View {
        if !inPictureInPicture, let offer = model.nextLive.offer {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live now")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(offer.title.isEmpty ? "Another live programme" : offer.title)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Not now") {
                    model.declineNextLive()
                }
                .buttonStyle(.bordered)
                .tint(Theme.textPrimary)
                Button("Switch") {
                    Task { await model.switchToNextLive() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 520)
            .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(.top, topInset)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

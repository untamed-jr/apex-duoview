import LiveTiming
import SwiftUI

/// The closed phone's event card, at the top of every page: the newest card, with older ones
/// stacked behind it ("+2"). "Unfold to see" on the Duo while closed; on a phone with no fold the
/// tap makes the jump (it does on the Duo too). Swiped sideways, the card goes and unfolding
/// simply carries on. The type scales with the screen's height (`height`).
struct EventCardsView: View {
    let companion: CompanionController
    let timing: TimingController
    /// The Duo is closed: "Unfold to see" applies.
    let foldable: Bool
    let height: CGFloat

    @State private var offset: CGFloat = 0

    var body: some View {
        if let card = companion.cards.first {
            let title = CompanionModels.cardTitle(card, drivers: timing.loadedSession?.drivers ?? [:])
            let older = max(companion.cards.count - 1, 0)
            ZStack(alignment: .top) {
                // The older cards, peeking out under the top one.
                if older > 0 {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous))
                        .padding(.horizontal, 14)
                        .offset(y: 8)
                        .accessibilityHidden(true)
                }
                Button {
                    companion.tapCard()
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: max(17, height * 0.034), weight: .bold))
                                .fontWidth(.condensed)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            if foldable {
                                Text(CompanionModels.unfoldToSee)
                                    .font(.system(size: max(13, height * 0.022)))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer(minLength: 4)
                        if let more = CompanionModels.moreText(older) {
                            Text(more)
                                .font(.system(size: max(13, height * 0.022), weight: .bold))
                                .fontWidth(.condensed)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .videoGlass(in: Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous))
                .accessibilityLabel(older > 0 ? "\(title), and \(older) more" : title)
                .accessibilityHint("Jumps to just before it")
                .accessibilityAction(named: "Dismiss") { companion.dismissTop() }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) { offset = value.translation.width }
                    }
                    .onEnded { value in
                        let away = abs(value.translation.width) > 80 && abs(value.translation.width) > abs(value.translation.height)
                        withAnimation(.snappy) {
                            if away { companion.dismissTop() }
                            offset = 0
                        }
                    })
            .id(card.t)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

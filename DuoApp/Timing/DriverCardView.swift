import LiveTiming
import SwiftUI

/// The broadcast-style card over an onboard, in multiview or a single feed (Android's DriverCard),
/// at picture time (2 Hz):
/// - a position box, the number and surname in the team colour, then "PIT" in the pits, the lap
///   just finished for 6 s after the line (purple, green or white), or the running lap clock;
/// - below, three sector bars (purple, green, yellow, grey for none yet), the interval ("Fastest"
///   gap in qualifying), and the speed in km/h or mph following the phone's region, hidden when
///   its data is more than 5 s old or not there yet.
///
/// Reads only `timing.cards[number]` and `timing.hiddenCards`, so the tile around it never
/// follows the 2 Hz values.
struct DriverCardSlot: View {
    let timing: TimingController
    /// The onboard's channel: a card is hidden per channel ("Hide card").
    let channelId: Int
    /// Its racing number.
    let number: String

    var body: some View {
        if timing.hiddenCards.contains(channelId) {
            Button {
                timing.toggleCard(channelId: channelId)
            } label: {
                Image(systemName: "person.text.rectangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show card")
        } else if let state = timing.cards[number] {
            DriverCardView(state: state)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contextMenu {
                    Button("Hide card", systemImage: "eye.slash") {
                        timing.toggleCard(channelId: channelId)
                    }
                }
                .accessibilityAction(named: "Hide card") { timing.toggleCard(channelId: channelId) }
        }
    }
}

/// The card itself, from plain values.
struct DriverCardView: View {
    let state: DriverCardState

    var body: some View {
        let card = state.card
        let team = Theme.teamColour(card.teamColour)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(card.position.map(String.init) ?? "–")
                    .font(.caption)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(Color.black)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text("\(card.number) \(card.surname)")
                    .font(.caption)
                    .bold()
                    .fontWidth(.condensed)
                    .foregroundStyle(team)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                lapCell(card)
            }
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(Array(card.sectors.enumerated()), id: \.offset) { _, pace in
                        Capsule()
                            .fill(TimingColours.sector(pace))
                            .frame(width: 16, height: 4)
                    }
                }
                .accessibilityHidden(true)
                if !card.gap.isEmpty {
                    Text(card.gap)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let kmh = state.speedKmh {
                    Text(TimingText.speed(kmh: kmh, metric: TimingText.usesKilometres(Locale.current.measurementSystem)))
                        .font(.caption2)
                        .bold()
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: 240, alignment: .leading)
        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(team).frame(width: 2).padding(.vertical, 4).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func lapCell(_ card: DriverCardModel) -> some View {
        if card.inPit {
            Text("PIT")
                .font(.caption)
                .bold()
                .foregroundStyle(Theme.flagYellow)
        } else if let flash = card.flash {
            Text(flash.text)
                .font(.caption)
                .bold()
                .monospacedDigit()
                .foregroundStyle(TimingColours.lap(flash.pace))
        } else if let clock = card.lapClock {
            Text(clock)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

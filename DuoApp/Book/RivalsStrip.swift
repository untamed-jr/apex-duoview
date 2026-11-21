import LiveTiming
import SwiftUI

/// One of Ear-Matched Rivals' strips (`DataRegions.leftStrip`, `rightStrip`), under its screen's
/// onboard: the driver is the onboard in that screen's slot (0 left, 1 right), so the strip, the
/// picture and the ear always agree, even after a tile tap swaps the two.
/// ```
/// ┌───────────── strip ─────────────┐
/// │ ▌Left ear · HAM ⌄               │
/// │ LAP 38                          │
/// │ "Box, box. Confirm plan B."  ▶  │
/// └─────────────────────────────────┘
/// ```
/// - The last clip the picture has reached (`clips(for:limit:)`), with its transcript through the
///   gated queue; "No radio from {CODE} yet." until there is one. ▶ plays it in this screen's ear
///   (`BookModels.pan`; centred without headphones), ■ stops it.
/// - A tap on the header opens the running order: the driver picked goes on this screen
///   (`MultiviewController.setRival`). Picking the other screen's driver trades the two.
/// - The left strip says "Put on headphones to hear each driver in one ear" while there are none.
struct RivalsStrip: View {
    let controller: MultiviewController
    let radio: RadioController
    let timing: TimingController
    /// 0: the left screen (left ear); 1: the right.
    let side: Int

    var body: some View {
        let number = controller.onboardNumber(inSlot: side)
        DataRegionFrame {
            VStack(alignment: .leading, spacing: 6) {
                header(number: number)
                if let number {
                    lastClip(number: number)
                } else {
                    Text(BookModels.pickOnboard)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if side == 0, !radio.headphones {
                    Text(BookModels.headphonesHint)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(side == 0 ? "Left rival" : "Right rival")
    }

    /// The driver's code ("HAM"), or "—" with no onboard on this screen.
    private func code(_ number: String?) -> String {
        guard let number else { return ConsoleText.absent }
        return CompanionModels.code(number, drivers: timing.loadedSession?.drivers ?? [:])
    }

    /// "Left ear · HAM ⌄": a menu of the running order; the one picked goes on this screen.
    private func header(number: String?) -> some View {
        let drivers = timing.loadedSession?.drivers ?? [:]
        return Menu {
            ForEach(order, id: \.self) { car in
                Button {
                    if let racingNumber = Int(car) { controller.setRival(side: side, racingNumber: racingNumber) }
                } label: {
                    if car == number {
                        Label(CompanionModels.code(car, drivers: drivers), systemImage: "checkmark")
                    } else {
                        Text(CompanionModels.code(car, drivers: drivers))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.teamColour(number.flatMap { drivers[$0]?.teamColour } ?? ""))
                    .frame(width: 3, height: 18)
                Text(BookModels.earLabel(left: side == 0, tla: code(number)))
                    .font(.subheadline)
                    .bold()
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Changes the driver on this screen")
    }

    /// The running order now: every car the session names.
    private var order: [String] {
        guard let session = timing.loadedSession else { return [] }
        return ClosedPager.raceOrder(at: timing.pictureTime ?? .min, session: session)
    }

    /// The last clip's lap and words, with ▶ (■ while it plays).
    @ViewBuilder
    private func lastClip(number: String) -> some View {
        let last = radio.clips(for: number, limit: 1).last
        if let last {
            let playing = radio.playing == last.path
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let label = last.label {
                        Text(label)
                            .font(.caption2)
                            .bold()
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(TranscriptState.rowText(last.transcript) ?? last.label ?? last.tla)
                        .font(.footnote)
                        .foregroundStyle(playing ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(last.isNew ? 0.14 : 0))
                }
                .animation(.easeInOut(duration: 0.6), value: last.isNew)
                Button {
                    if playing {
                        radio.stop()
                    } else {
                        radio.play(path: last.path, pan: BookModels.pan(left: side == 0, headphones: radio.headphones))
                    }
                } label: {
                    Image(systemName: playing ? "stop.fill" : "play.fill")
                        .font(.body.bold())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(playing ? Theme.accent : Theme.raised)
                .accessibilityLabel(playing ? "Stop the clip" : "Play \(last.tla)'s last clip")
            }
            .accessibilityElement(children: .contain)
        } else {
            Text(BookModels.noRadio(code(number)))
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        if let notice = radio.notice {
            Text(notice)
                .font(.caption2)
                .foregroundStyle(Theme.flagYellow)
        }
    }
}

/// Rivals' one listener for the pair (`radio.listen` takes one set, so the strips don't each set
/// their own): the two screens' drivers are listened to, and with "Play radio as it happens" on, a
/// clip that normal play crosses (`radio.crossed`, never rows appearing, a seek or a scrub) plays
/// by itself in the ear of the screen its driver is on when it plays (centred without headphones).
/// Commentary stays centred: only clips are panned. Rivals counts as a radio view, so transcripts
/// are made while it shows.
struct RivalsListener: View {
    let controller: MultiviewController
    let radio: RadioController
    let settings: CompanionSettings

    var body: some View {
        let pair = [controller.onboardNumber(inSlot: 0), controller.onboardNumber(inSlot: 1)]
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { radio.setSurface(BookModels.rivalsSurface, shown: true) }
            .onDisappear {
                radio.stopListening(by: BookModels.rivalsSurface)
                radio.setSurface(BookModels.rivalsSurface, shown: false)
            }
            .task(id: pair) {
                let cars = Set(pair.compactMap { $0 })
                radio.listen(cars, by: BookModels.rivalsSurface)
                guard !cars.isEmpty else { return }
                for await clip in radio.crossed {
                    guard settings.autoPlayRadio else { continue }
                    // The screen the driver is on now (a tile tap may have swapped the two).
                    guard let side = [0, 1].first(where: { controller.onboardNumber(inSlot: $0) == clip.racingNumber })
                    else { continue }
                    radio.play(path: clip.path, pan: BookModels.pan(left: side == 0, headphones: radio.headphones))
                }
            }
    }
}

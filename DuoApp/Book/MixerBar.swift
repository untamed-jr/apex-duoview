import Multiview
import SwiftUI

/// The hinge mixer's bar, "Commentary ◀━━●━━▶ Radio" with the ● at the radio's share, or "No radio
/// to mix yet" while the session has no clip at the cut. Clear glass over the video; never takes
/// a touch.
struct MixerBar: View {
    let levels: MixLevels
    let hasRadio: Bool

    var body: some View {
        Text(hasRadio ? BookModels.mixBar(levels) : BookModels.noRadioToMix)
            .font(.footnote.monospaced())
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .videoGlass(in: Capsule())
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasRadio
                ? "Mix: \(Int((levels.radio * 100).rounded())) percent radio"
                : BookModels.noRadioToMix)
    }
}

/// Drives the hinge mixer and shows its bar, over the multiview. A leaf view, so the hinge's
/// readings redraw only it.
/// - Active only in book and laptop (the fold's posture) with Settings' "Hinge mixer" on
///   (`BookModels.mixerActive`). Coming on, a fresh `HingeMixer` takes the angle (its first reading
///   always applies); then every change of `FoldState.hingeAngle` is a reading (smoothed, with its
///   5° dead zone). A nil angle (no hinge, not reported yet) is never a reading: the levels stay.
/// - The hinge reports only changes, so after each reading the mixer settles on a 100 ms timer
///   (`HingeMixer.settle()`) until it reaches the angle the hinge stopped at; a new reading or
///   going off cancels the timer.
/// - Each new set of levels goes to the radio (`setMixer`) and shows the bar for 2 s.
/// - Going off (another posture, the setting off) or this view going away: `setMixer(nil)`, so a
///   clip silences the feeds again and nothing carries over to the single-feed player.
/// - Clips are the mixer's only source (owner check T-R1 decides whether a continuous team-radio
///   track is crossfaded later): with no clip playing the feeds are at full level.
struct HingeMixerOverlay: View {
    let fold: FoldState
    let radio: RadioController
    let settings: CompanionSettings

    /// How often the mixer steps towards a hinge at rest, and for how many steps at most (about
    /// 1.5 s takes it from one end to the other; the cap is a guard, never reached).
    private static let settleStep: Duration = .milliseconds(100)
    private static let settleStepLimit = 60

    @State private var mixer = HingeMixer()
    @State private var levels: MixLevels?
    /// Bumped by each change of the mix: the bar shows for 2 s from the last one.
    @State private var changes = 0
    @State private var barShown = false

    private struct Input: Equatable {
        var active: Bool
        var angle: Double?
    }

    var body: some View {
        let input = Input(active: BookModels.mixerActive(posture: fold.posture, on: settings.hingeMixer),
                          angle: fold.hingeAngle)
        ZStack {
            if barShown, let levels {
                MixerBar(levels: levels, hasRadio: !radio.allRows.isEmpty)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: barShown)
        .onChange(of: input, initial: true) { old, new in
            reading(new, comingOn: new.active && (!old.active || old == new))
        }
        // After a reading: keep stepping until the mix reaches where the hinge came to rest.
        .task(id: input) {
            var steps = 0
            while input.active, !mixer.isSettled, steps < Self.settleStepLimit {
                do {
                    try await Task.sleep(for: Self.settleStep)
                } catch {
                    return
                }
                steps += 1
                apply(mixer.settle())
            }
        }
        .task(id: changes) {
            guard changes > 0 else { return }
            barShown = true
            do {
                try await Task.sleep(for: .seconds(BookModels.mixBarSeconds))
            } catch {
                return
            }
            barShown = false
        }
        .onDisappear {
            radio.setMixer(nil)
            levels = nil
            mixer = HingeMixer()
            barShown = false
        }
    }

    /// One look at the posture, the setting and the angle.
    private func reading(_ input: Input, comingOn: Bool) {
        guard input.active else {
            if levels != nil || radio.mixer != nil {
                levels = nil
                mixer = HingeMixer()
                radio.setMixer(nil)
                barShown = false
            }
            return
        }
        if comingOn { mixer = HingeMixer() }
        // No reading without an angle: the levels stay as they are.
        guard let angle = input.angle else { return }
        apply(mixer.update(angle: angle))
    }

    /// New levels from a reading or a settling step go to the radio, and a change shows the bar.
    private func apply(_ new: MixLevels?) {
        guard let next = new else { return }
        let changed = next != levels
        levels = next
        radio.setMixer(next)
        if changed { changes &+= 1 }
    }
}

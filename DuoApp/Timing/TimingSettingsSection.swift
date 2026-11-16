import LiveTiming
import SwiftUI

/// Settings › Track map: the timing offset with "Reset to −7 s", "Show the whole race on the
/// Scrub Deck" (off by default: no data ahead of the picture; it also shows every flag period on
/// the multiview timeline), and "Speed readouts on mobile data" (on by default). The values live in `TimingSettings`, through the timing controller so
/// an open map follows at once.
struct TimingSettingsSection: View {
    let timing: TimingController

    var body: some View {
        Section {
            Stepper(
                "Timing offset " + OffsetText.text(timing.offsetMs),
                onIncrement: { timing.nudge(1) },
                onDecrement: { timing.nudge(-1) })
            Button("Reset to \u{2212}7 s") {
                timing.resetOffset()
            }
            .disabled(timing.offsetMs == PictureClock.defaultOffsetMs)
            Toggle("Show the whole race on the Scrub Deck", isOn: Binding(
                get: { timing.showWholeRace },
                set: { timing.setShowWholeRace($0) }))
            .tint(Theme.accent)
            Toggle("Speed readouts on mobile data", isOn: Binding(
                get: { timing.speedOnMobileData },
                set: { timing.setSpeedOnMobileData($0) }))
            .tint(Theme.accent)
        } header: {
            Text("Track map").sectionLabel()
        } footer: {
            Text("Timing follows the picture: the stream's own clock less 7 s, as F1 stamps its video "
                + "about 7 s after its timing. If the cars on the map run ahead of the video or behind "
                + "it, move the offset here or with the map's \u{2212}1 s and +1 s. Safety car and red "
                + "flag periods show on the timeline only as far as you've watched, unless you show "
                + "the whole race (for rewatching).")
        }
    }
}

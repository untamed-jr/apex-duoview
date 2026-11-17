import Multiview
import SwiftUI

/// Settings › Multiview: what to do when a feed is missing, and (for accounts with multiview)
/// your driver and the tracker delay: how far the sync holds the TRACKER and DATA tiles behind
/// the main feed, in 0.5 s steps (0 to 20 s), stored in `TimingSettings` through the timing
/// controller so an open multiview follows at once.
struct MultiviewSettingsSection: View {
    let model: AppModel

    private var hasMultiview: Bool {
        if case .signedIn(let account) = model.auth { return account.hasMultiview }
        return false
    }

    var body: some View {
        Section {
            Picker("When a feed is missing", selection: Binding(
                get: { model.multiview.fewerFeeds },
                set: { model.multiview.setFewerFeeds($0) })
            ) {
                Text("Ask").tag(FewerFeeds.ask)
                Text("Keep four spots").tag(FewerFeeds.keepSpots)
                Text("Fit to the screen").tag(FewerFeeds.fit)
            }
            if hasMultiview {
                NavigationLink {
                    MyDriverList(model: model)
                } label: {
                    LabeledContent("My driver", value: model.favouriteDriver ?? "None")
                }
                Stepper(
                    "Tracker delay " + TrackerDelay.text(halfSeconds: model.timing.trackerDelayHalfSeconds),
                    onIncrement: { model.timing.nudgeTrackerDelay(by: 1) },
                    onDecrement: { model.timing.nudgeTrackerDelay(by: -1) })
            }
        } header: {
            Text("Multiview").sectionLabel()
        } footer: {
            if hasMultiview {
                Text("F1's tracker feed runs a little ahead of the race pictures. The tracker delay "
                    + "holds the TRACKER and DATA tiles that far behind the main feed.")
            }
        }
    }
}

import Multiview
import SwiftUI

/// Settings › Closed phone: "Event cards" (one switch per group: "Flags", "My driver's stops and
/// radio", "My driver's position changes", "Chequered flag"; all on) and "Rewind when opening"
/// (3, 5, 10 or 15 s; 5). The values live in `CompanionSettings`, which isn't observed, so the
/// controls keep their own copy; the companion reads them when a card comes and when it jumps.
struct ClosedSettingsSection: View {
    let settings: CompanionSettings

    @State private var groups: [CardGroup: Bool]
    @State private var rewind: Int

    init(settings: CompanionSettings) {
        self.settings = settings
        var on: [CardGroup: Bool] = [:]
        for group in CardGroup.allCases { on[group] = settings.cardGroupOn(group) }
        _groups = State(initialValue: on)
        _rewind = State(initialValue: settings.rewindSeconds)
    }

    var body: some View {
        Section {
            Text("Event cards")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.textPrimary)
            ForEach(CardGroup.allCases, id: \.self) { group in
                Toggle(Self.name(group), isOn: Binding(
                    get: { groups[group] ?? true },
                    set: { on in
                        groups[group] = on
                        settings.setCardGroup(group, on: on)
                    }))
                .tint(Theme.accent)
            }
            Picker("Rewind when opening", selection: Binding(
                get: { rewind },
                set: { seconds in
                    rewind = seconds
                    settings.rewindSeconds = seconds
                })
            ) {
                ForEach(CompanionSettings.rewindChoices, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
        } header: {
            Text("Closed phone").sectionLabel()
        } footer: {
            Text("Cards come only when the picture reaches the moment. Open the phone while one shows "
                + "and every feed goes back to just before it.")
        }
    }

    static func name(_ group: CardGroup) -> String {
        switch group {
        case .flags: return "Flags"
        case .myStopsAndRadio: return "My driver's stops and radio"
        case .myPositions: return "My driver's position changes"
        case .chequered: return "Chequered flag"
        }
    }
}

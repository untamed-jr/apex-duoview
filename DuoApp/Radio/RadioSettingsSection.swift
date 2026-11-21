import Multiview
import SwiftUI

/// Settings › Team radio: "Transcripts" (on: clips are turned into text on the phone while a radio
/// view shows; off: none made, none shown) and "Play radio as it happens" (on; the Radio Scanner
/// and Rivals only) and "Hinge mixer" (off; build 21: in book and laptop the hinge sets the
/// balance of commentary and radio while a clip plays). The values live in `CompanionSettings`,
/// which isn't observed, so the switches keep their own copy; the radio reads "Transcripts" on
/// every tick, and the multiview reads "Hinge mixer" with each change of the fold.
struct RadioSettingsSection: View {
    let settings: CompanionSettings

    @State private var transcripts: Bool
    @State private var autoPlay: Bool
    @State private var hingeMixer: Bool

    init(settings: CompanionSettings) {
        self.settings = settings
        _transcripts = State(initialValue: settings.transcripts)
        _autoPlay = State(initialValue: settings.autoPlayRadio)
        _hingeMixer = State(initialValue: settings.hingeMixer)
    }

    var body: some View {
        Section {
            Toggle("Transcripts", isOn: Binding(
                get: { transcripts },
                set: { on in
                    transcripts = on
                    settings.transcripts = on
                }))
            .tint(Theme.accent)
            Toggle("Play radio as it happens", isOn: Binding(
                get: { autoPlay },
                set: { on in
                    autoPlay = on
                    settings.autoPlayRadio = on
                }))
            .tint(Theme.accent)
            Toggle(isOn: Binding(
                get: { hingeMixer },
                set: { on in
                    hingeMixer = on
                    settings.hingeMixer = on
                })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BookModels.mixerSetting)
                    Text(BookModels.mixerFooter)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Team radio").sectionLabel()
        } footer: {
            Text("Clips show only once the picture reaches them. Transcripts are made on this iPhone; the "
                + "audio is never sent anywhere. The first time, iOS may download its English speech model "
                + "from Apple. Play radio as it happens is for the Radio Scanner and Rivals.")
        }
    }
}

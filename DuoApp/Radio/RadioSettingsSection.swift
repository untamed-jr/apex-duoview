import Multiview
import SwiftUI

/// Settings › Team radio: "Transcripts" (on) and "Play radio as it happens" (on; the Radio Scanner
/// and Rivals only). The values live in `CompanionSettings`, which isn't observed, so the switches
/// keep their own copy.
struct RadioSettingsSection: View {
    let settings: CompanionSettings

    @State private var transcripts: Bool
    @State private var autoPlay: Bool

    init(settings: CompanionSettings) {
        self.settings = settings
        _transcripts = State(initialValue: settings.transcripts)
        _autoPlay = State(initialValue: settings.autoPlayRadio)
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
        } header: {
            Text("Team radio").sectionLabel()
        } footer: {
            Text("Clips show only once the picture reaches them. Transcripts are made on this iPhone; the "
                + "audio is never sent anywhere. Play radio as it happens is for the Radio Scanner and Rivals.")
        }
    }
}

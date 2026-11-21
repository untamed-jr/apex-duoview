import LiveTiming
import Multiview
import SwiftUI

/// Settings › Haptics: "Haptics" (on), then one switch per event in the spec's order, each with
/// "Feel it", and the footer. Shown only on a phone that can play haptics (`SettingsView` asks
/// `HapticsPlayer.supported`). The values live in `CompanionSettings`, which isn't observed, so
/// the switches keep their own copy; the companion reads them each time an event is crossed.
/// "Feel it" plays its row's haptic whatever the switches say.
struct HapticsSettingsSection: View {
    let settings: CompanionSettings
    let haptics: HapticsPlayer

    @State private var master: Bool
    @State private var kinds: [HapticKind: Bool]

    init(settings: CompanionSettings, haptics: HapticsPlayer) {
        self.settings = settings
        self.haptics = haptics
        _master = State(initialValue: settings.haptics)
        var on: [HapticKind: Bool] = [:]
        for kind in HapticKind.allCases { on[kind] = settings.hapticOn(kind) }
        _kinds = State(initialValue: on)
    }

    var body: some View {
        Section {
            Toggle(HapticPatterns.masterSwitch, isOn: Binding(
                get: { master },
                set: { on in
                    master = on
                    settings.haptics = on
                }))
            .tint(Theme.accent)
            ForEach(HapticPatterns.settingsOrder, id: \.self) { kind in
                HStack(spacing: 12) {
                    Toggle(HapticPatterns.label(for: kind), isOn: Binding(
                        get: { kinds[kind] ?? true },
                        set: { on in
                            kinds[kind] = on
                            settings.setHaptic(kind, on: on)
                        }))
                    .tint(Theme.accent)
                    .disabled(!master)
                    Button(HapticPatterns.feelIt) { haptics.play(kind) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        // A Form row with two controls: only the button takes its own taps.
                        .fixedSize()
                        .accessibilityLabel("\(HapticPatterns.feelIt), \(HapticPatterns.label(for: kind))")
                }
            }
        } header: {
            Text(HapticPatterns.sectionTitle).sectionLabel()
        } footer: {
            Text(HapticPatterns.footer)
        }
    }
}

/// "Show haptics on screen" (Settings › Debug): "Haptic: Yellow flag" for 2 s each time a haptic
/// plays, set on the same path as the real one (`HapticsPlayer.lastShown`), so it also shows on
/// a phone without haptics. Its own view, so only it redraws when a haptic plays. Never takes a
/// touch.
struct HapticDebugLabel: View {
    let haptics: HapticsPlayer
    let settings: CompanionSettings

    /// The haptic whose 2 s are up.
    @State private var expired: Date?

    var body: some View {
        let shown = haptics.lastShown
        Group {
            // The switch is read as each haptic plays (`CompanionSettings` isn't observed).
            if let shown, settings.showHapticsOnScreen, expired != shown.1,
               HapticPatterns.debugLabelShows(shown: shown.1, now: Date()) {
                Text(HapticPatterns.debugText(shown.0))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .videoGlass(in: Capsule())
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.snappy, value: expired)
        .task(id: shown?.1) {
            guard let at = shown?.1 else { return }
            let left = HapticPatterns.debugLabelSeconds - Date().timeIntervalSince(at)
            if left > 0 {
                do {
                    try await Task.sleep(for: .seconds(left))
                } catch {
                    return
                }
            }
            expired = at
        }
    }
}

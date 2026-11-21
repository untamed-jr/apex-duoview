import Foundation
import LiveTiming
import Multiview

/// One haptic's feel as plain values, for `HapticsPlayer` to turn into a Core Haptics pattern.
/// Each event starts `time` seconds into the pattern; a `duration` makes it a continuous buzz of
/// that many seconds, nil a transient tap. `intensity` and `sharpness` are 0...1.
struct HapticPattern: Equatable, Sendable {
    var events: [(time: Double, duration: Double?, intensity: Float, sharpness: Float)]

    /// When the last event ends, in seconds (a tap counts as an instant).
    var length: Double { events.map { $0.time + ($0.duration ?? 0) }.max() ?? 0 }

    // Tuples aren't Equatable, so field by field.
    static func == (a: HapticPattern, b: HapticPattern) -> Bool {
        a.events.count == b.events.count && zip(a.events, b.events).allSatisfy {
            $0.time == $1.time && $0.duration == $1.duration && $0.intensity == $1.intensity && $0.sharpness == $1.sharpness
        }
    }
}

/// The haptic vocabulary (spec §5): one feel per event, its name in Settings › Haptics, and the
/// section's copy. Pure, so the Linux harness checks it.
enum HapticPatterns {
    // MARK: Copy (verbatim from the spec)

    static let sectionTitle = "Haptics"
    static let masterSwitch = "Haptics"
    static let feelIt = "Feel it"
    static let footer = "Haptics follow the picture, so they never come before what you see."
    static let showOnScreen = "Show haptics on screen"

    /// The rows of Settings › Haptics, in the spec's order (not the priority order).
    static let settingsOrder: [HapticKind] = [.yellow, .safetyCar, .vsc, .red, .pits, .purpleSector, .chequered]

    /// The event's name, as the spec's table and Settings › Haptics give it.
    static func label(for kind: HapticKind) -> String {
        switch kind {
        case .yellow: return "Yellow flag"
        case .safetyCar: return "Safety car"
        case .vsc: return "Virtual safety car"
        case .red: return "Red flag"
        case .pits: return "Your driver pits"
        case .purpleSector: return "Purple sector"
        case .chequered: return "Chequered flag"
        }
    }

    /// "Show haptics on screen": "Haptic: Yellow flag".
    static func debugText(_ kind: HapticKind) -> String { "Haptic: " + label(for: kind) }

    /// How long the on-screen label stays after a haptic.
    static let debugLabelSeconds: TimeInterval = 2

    /// Whether the label for a haptic shown at `shown` still shows at `now`.
    static func debugLabelShows(shown: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(shown)
        return age >= 0 && age < debugLabelSeconds
    }

    /// Whether an event of this kind is felt: the master switch and the kind's own switch, both
    /// on. (Whether the phone can play haptics is the player's question, so the on-screen label
    /// still shows on a phone without them.)
    static func wanted(_ kind: HapticKind, settings: CompanionSettings) -> Bool {
        settings.haptics && settings.hapticOn(kind)
    }

    // MARK: Patterns

    /// The spec's table. Every pattern ends well inside `HapticSchedule.spacing`, so two never
    /// overlap.
    static func pattern(for kind: HapticKind) -> HapticPattern {
        switch kind {
        case .yellow:
            // Two short soft taps.
            return HapticPattern(events: [
                (time: 0, duration: nil, intensity: 0.45, sharpness: 0.3),
                (time: 0.14, duration: nil, intensity: 0.45, sharpness: 0.3),
            ])
        case .safetyCar:
            // Three firm pulses.
            return HapticPattern(events: [
                (time: 0, duration: 0.12, intensity: 0.9, sharpness: 0.6),
                (time: 0.25, duration: 0.12, intensity: 0.9, sharpness: 0.6),
                (time: 0.5, duration: 0.12, intensity: 0.9, sharpness: 0.6),
            ])
        case .vsc:
            // Three soft pulses.
            return HapticPattern(events: [
                (time: 0, duration: 0.12, intensity: 0.4, sharpness: 0.2),
                (time: 0.25, duration: 0.12, intensity: 0.4, sharpness: 0.2),
                (time: 0.5, duration: 0.12, intensity: 0.4, sharpness: 0.2),
            ])
        case .red:
            // One long strong buzz, 0.8 s.
            return HapticPattern(events: [
                (time: 0, duration: 0.8, intensity: 1, sharpness: 0.5),
            ])
        case .pits:
            // A rising ramp: back-to-back steps, each stronger and a little sharper.
            let steps = 6
            let step = 0.1
            return HapticPattern(events: (0..<steps).map { i in
                let rise = Float(i) / Float(steps - 1)
                return (time: Double(i) * step, duration: step, intensity: 0.2 + 0.8 * rise, sharpness: 0.2 + 0.5 * rise)
            })
        case .purpleSector:
            // One crisp tick.
            return HapticPattern(events: [
                (time: 0, duration: nil, intensity: 0.7, sharpness: 1),
            ])
        case .chequered:
            // A slow triple.
            return HapticPattern(events: [
                (time: 0, duration: nil, intensity: 0.8, sharpness: 0.5),
                (time: 0.4, duration: nil, intensity: 0.8, sharpness: 0.5),
                (time: 0.8, duration: nil, intensity: 0.8, sharpness: 0.5),
            ])
        }
    }
}

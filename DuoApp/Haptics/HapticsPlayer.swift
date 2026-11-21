import CoreHaptics
import Foundation
import LiveTiming
import Observation

/// Plays the haptic vocabulary (`HapticPatterns`) with Core Haptics: haptics-only patterns, one
/// engine for the app, made on the first haptic. The companion's schedule decides what plays and
/// when (`CompanionController.playHaptic`); "Feel it" in Settings › Haptics plays one directly.
///
/// - `lastShown` is set first on every `play`, the same path as the real haptic, so "Show haptics
///   on screen" works on a phone without haptics (the simulator) too.
/// - The engine restarts from its reset handler, and from its stopped handler unless the app was
///   suspended (Core Haptics stops then, and the next haptic starts it again). Its callbacks are
///   `@Sendable` and hop to the main actor with plain values.
/// - A haptic the engine refuses is tried once more on a freshly started engine, then dropped.
@MainActor
@Observable
final class HapticsPlayer {
    /// The phone can play haptics (`capabilitiesForHardware().supportsHaptics`). Without them,
    /// Settings › Haptics is hidden and no engine is made.
    let supported: Bool
    /// The last haptic played (or that would have played, without haptics) and when.
    private(set) var lastShown: (HapticKind, Date)?

    @ObservationIgnored private var engine: CHHapticEngine?
    /// The engine is started; false after it stopped, until the next haptic starts it again.
    @ObservationIgnored private var running = false

    init() {
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Plays `kind`'s pattern now. The caller has checked the switches (the schedule does; "Feel
    /// it" plays whatever its row is).
    func play(_ kind: HapticKind) {
        lastShown = (kind, Date())
        guard supported, let pattern = try? CHHapticPattern(events: Self.events(HapticPatterns.pattern(for: kind)), parameters: []) else { return }
        if start(pattern) { return }
        // The engine may have stopped before its stopped handler reached the main actor (idle,
        // suspended): start it again and try once more.
        running = false
        _ = start(pattern)
    }

    /// Plays `pattern` on the started engine; false when Core Haptics refused.
    private func start(_ pattern: CHHapticPattern) -> Bool {
        guard let engine = startedEngine() else { return false }
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            running = false
            return false
        }
    }

    // MARK: The engine

    /// The engine, made and started if it isn't; nil when Core Haptics refuses.
    private func startedEngine() -> CHHapticEngine? {
        if engine == nil { engine = makeEngine() }
        guard let engine else { return nil }
        if !running {
            do {
                try engine.start()
                running = true
            } catch {
                return nil
            }
        }
        return engine
    }

    private func makeEngine() -> CHHapticEngine? {
        guard let engine = try? CHHapticEngine() else { return nil }
        engine.playsHapticsOnly = true
        // Haptics are seconds or minutes apart: let the hardware sleep between them. It reports
        // `.idleTimeout` when it does, and the next haptic starts it again.
        engine.isAutoShutdownEnabled = true
        // Core Haptics calls these on its own queue: hop to the main actor with plain values.
        engine.stoppedHandler = { @Sendable [weak self] reason in
            let code = reason.rawValue
            Task { @MainActor [weak self] in self?.engineStopped(code) }
        }
        engine.resetHandler = { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.engineReset() }
        }
        return engine
    }

    /// The engine stopped. Suspended (or stopped for being idle): it starts again with the next
    /// haptic. Destroyed: a new one is made then. Otherwise (an interruption, a system error) it
    /// restarts now.
    private func engineStopped(_ code: Int) {
        running = false
        switch CHHapticEngine.StoppedReason(rawValue: code) {
        case .applicationSuspended?, .idleTimeout?, .notifyWhenFinished?:
            return
        case .engineDestroyed?:
            engine = nil
        default:
            restart()
        }
    }

    /// The haptic server reset: its players are gone and the engine must start again.
    private func engineReset() {
        running = false
        restart()
    }

    private func restart() {
        guard let engine else { return }
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    // MARK: Patterns

    /// The plain pattern as Core Haptics events: a tap for no duration, a continuous buzz else.
    private static func events(_ pattern: HapticPattern) -> [CHHapticEvent] {
        pattern.events.map { event in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
            ]
            if let duration = event.duration {
                return CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                     relativeTime: event.time, duration: duration)
            }
            return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: event.time)
        }
    }
}

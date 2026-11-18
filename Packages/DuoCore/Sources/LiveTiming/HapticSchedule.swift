import Foundation

/// The seven haptics, declared strongest first: that order is the priority.
public enum HapticKind: String, CaseIterable, Sendable {
    case red, safetyCar, vsc, chequered, yellow, pits, purpleSector

    /// 0 is the strongest; a stronger kind replaces a weaker one that is waiting.
    public var priority: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    /// The haptic for an event; none for radio, a car being out and a pass.
    public static func from(_ kind: CompanionEventKind) -> HapticKind? {
        switch kind {
        case .yellow: return .yellow
        case .safetyCar: return .safetyCar
        case .vsc: return .vsc
        case .red: return .red
        case .chequered: return .chequered
        case .pit: return .pits
        case .purpleSector: return .purpleSector
        case .radio, .out, .passed: return nil
        }
    }
}

/// No haptic more often than every `spacing` seconds. One slot waits; a stronger kind replaces a
/// weaker one in it, a weaker or equal one is dropped. `now` is any steady clock in seconds (the
/// app's, not picture time); a `now` that is not finite is ignored.
public struct HapticSchedule: Sendable {
    public static let spacing: TimeInterval = 2

    private var waiting: HapticKind?
    private var lastPlayed: TimeInterval?

    public init() {}

    /// The kind waiting, if any.
    public var pending: HapticKind? { waiting }

    public mutating func offer(_ kind: HapticKind, now: TimeInterval) {
        guard now.isFinite else { return }
        if let current = waiting, current.priority <= kind.priority { return }
        waiting = kind
    }

    /// The waiting kind once `spacing` has passed since the last one played (at once if none
    /// has); it is then played, so the slot empties and the spacing starts again.
    public mutating func due(now: TimeInterval) -> HapticKind? {
        guard now.isFinite, let kind = waiting else { return nil }
        // A clock that went backwards is not a reason to hold a haptic for ever.
        if let last = lastPlayed, now >= last, now - last < Self.spacing { return nil }
        waiting = nil
        lastPlayed = now
        return kind
    }

    /// Forgets what waits and when one last played (a seek, or the player stopping).
    public mutating func reset() {
        waiting = nil
        lastPlayed = nil
    }
}

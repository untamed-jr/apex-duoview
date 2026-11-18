import Foundation

/// How loud each of the two audio sources is, 0...1. `commentary + radio` is always 1.
public struct MixLevels: Sendable, Equatable {
    public var commentary: Float
    public var radio: Float

    public init(commentary: Float, radio: Float) {
        self.commentary = commentary
        self.radio = radio
    }
}

/// Maps the hinge angle to the commentary/radio balance: fully radio at or below 70 degrees,
/// fully commentary at or above 160, linear in between. A reading is smoothed, and new levels
/// are returned only when the smoothed angle has moved past the dead zone from the last one
/// applied (or reached an end of the curve), so a hand's jitter doesn't make the audio waver.
public struct HingeMixer: Sendable {
    public static let allRadioAngle = 70.0
    public static let allCommentaryAngle = 160.0
    /// Degrees the smoothed angle must move from the last applied one before levels change.
    public static let deadZone = 5.0
    /// The share of the way to a new reading the smoothed angle moves each time.
    public static let smoothing = 0.3

    private var smoothed: Double?
    private var applied: Double?

    public init() {}

    /// Clamped and linear between the two ends.
    public static func levels(angle: Double) -> MixLevels {
        let f = (angle - allRadioAngle) / (allCommentaryAngle - allRadioAngle)
        let commentary = Float(min(max(f, 0), 1))
        return MixLevels(commentary: commentary, radio: 1 - commentary)
    }

    /// Takes a reading. Returns the levels to apply, or nil to leave them as they are. The first
    /// reading always applies. Afterwards: when the smoothed angle is more than `deadZone` from the
    /// last applied one, or has reached an end of the curve that the applied one hadn't.
    public mutating func update(angle: Double) -> MixLevels? {
        let next = smoothed.map { $0 + Self.smoothing * (angle - $0) } ?? angle
        smoothed = next
        guard let last = applied else {
            applied = next
            return Self.levels(angle: next)
        }
        let atEnd = next <= Self.allRadioAngle || next >= Self.allCommentaryAngle
        let crossedEnd = atEnd && Self.levels(angle: next) != Self.levels(angle: last)
        guard abs(next - last) > Self.deadZone || crossedEnd else { return nil }
        applied = next
        return Self.levels(angle: next)
    }
}

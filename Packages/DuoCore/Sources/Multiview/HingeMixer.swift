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
///
/// The hinge reports an angle only when it changes, so once it comes to rest no more readings
/// come and smoothing alone would stop short of it. `settle()` keeps stepping towards the latest
/// reading in their place (the app calls it on a short timer until `isSettled`): a move past the
/// dead zone then ends exactly at the angle the hinge stopped at (or the end of the curve it
/// points past). A reading within the dead zone of the applied angle is jitter: there is nothing
/// to settle, and the levels stay.
public struct HingeMixer: Sendable {
    public static let allRadioAngle = 70.0
    public static let allCommentaryAngle = 160.0
    /// Degrees the smoothed angle must move from the last applied one before levels change.
    public static let deadZone = 5.0
    /// The share of the way to a new reading the smoothed angle moves each time.
    public static let smoothing = 0.3

    /// Degrees from the latest reading at which settling stops stepping and lands on it.
    public static let settledWithin = 0.5

    private var smoothed: Double?
    private var applied: Double?
    /// The latest reading, which `settle()` steps towards.
    private var latest: Double?
    /// The latest move went past the dead zone from the applied angle and hasn't landed yet.
    private var moving = false

    public init() {}

    /// Nothing left for `settle()` to do: no move past the dead zone is still on its way.
    public var isSettled: Bool { !moving }

    /// Clamped and linear between the two ends.
    /// A reading that isn't a number gives an even mix; infinity is the end it points to.
    public static func levels(angle: Double) -> MixLevels {
        if angle.isNaN { return MixLevels(commentary: 0.5, radio: 0.5) }
        let f = (angle - allRadioAngle) / (allCommentaryAngle - allRadioAngle)
        let commentary = Float(min(max(f, 0), 1))
        return MixLevels(commentary: commentary, radio: 1 - commentary)
    }

    /// Takes a reading. Returns the levels to apply, or nil to leave them as they are. The first
    /// reading always applies. Afterwards: when the smoothed angle is more than `deadZone` from the
    /// last applied one, or has reached an end of the curve that the applied one hadn't.
    public mutating func update(angle: Double) -> MixLevels? {
        guard angle.isFinite else { return nil }
        latest = angle
        if let applied, abs(angle - applied) > Self.deadZone { moving = true }
        return step(towards: angle)
    }

    /// One more step towards the latest reading, as if the hinge had reported it again. Once
    /// within `settledWithin` of it (clamped to the curve's ends), lands on it: the last levels
    /// returned after a move are exactly `levels(angle:)` of where the hinge stopped. Returns the
    /// levels to apply, or nil; nil and nothing changes once `isSettled`.
    public mutating func settle() -> MixLevels? {
        guard moving, let latest, let current = smoothed else { return nil }
        let target = min(max(latest, Self.allRadioAngle), Self.allCommentaryAngle)
        if abs(target - current) >= Self.settledWithin { return step(towards: latest) }
        smoothed = target
        moving = false
        guard let last = applied, Self.levels(angle: target) != Self.levels(angle: last) else { return nil }
        applied = target
        return Self.levels(angle: target)
    }

    /// The smoothing step, the end rule and the dead zone, for a reading or a settling step.
    private mutating func step(towards angle: Double) -> MixLevels? {
        var next = smoothed.map { $0 + Self.smoothing * (angle - $0) } ?? angle
        // A reading held at or past an end reaches it exactly once smoothing has brought it within
        // the dead zone, rather than stopping just short.
        if angle <= Self.allRadioAngle, next - Self.allRadioAngle <= Self.deadZone {
            next = Self.allRadioAngle
        } else if angle >= Self.allCommentaryAngle, Self.allCommentaryAngle - next <= Self.deadZone {
            next = Self.allCommentaryAngle
        }
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

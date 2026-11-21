import Foundation

/// Tells a real unfold from the fold's posture readings, for Unfold to See.
///
/// An unfold is the last posture that wasn't `.unknown` being `.closed`, then flat, book or laptop.
/// `.unknown` readings in between (the hinge part open before the fold's region is known) are
/// passed over, so closed → unknown → book is still an unfold. `.unknown` on its own is never one:
/// unknown → book after anything but closed, or with nothing known before, moves nothing.
public struct UnfoldWatch: Sendable, Equatable {
    /// The latest posture that wasn't `.unknown`; nil until one is seen.
    public private(set) var lastKnown: Posture?
    /// The latest posture seen, `.unknown` included.
    public private(set) var current: Posture?

    public init() {}

    /// The fold may be opening: closed was the last known posture and the latest is `.unknown`.
    public var mayBeOpening: Bool { lastKnown == .closed && current == .unknown }

    /// Takes a reading. True when it completes an unfold.
    @discardableResult
    public mutating func see(_ posture: Posture) -> Bool {
        current = posture
        guard posture != .unknown else { return false }
        let unfolded = lastKnown == .closed && [.flat, .book, .laptop].contains(posture)
        lastKnown = posture
        return unfolded
    }

    /// A change from `old` to `new`: `old` is seen first when it isn't the latest reading (the
    /// watch missed it, or saw nothing yet), so the memory always starts from the truth.
    @discardableResult
    public mutating func change(from old: Posture, to new: Posture) -> Bool {
        if current != old { see(old) }
        return see(new)
    }
}

import Foundation

/// The moment of the race the picture shows, so timing can follow the video. F1 TV's streams
/// carry a program date (`EXT-X-PROGRAM-DATE-TIME`) that runs a few seconds ahead of the timing
/// archive's clock; `offsetMs` (−7 s unless the viewer nudges it) closes that gap.
public struct PictureClock: Sendable {
    /// How far timing is moved from the stream's own time; negative is earlier.
    public var offsetMs: Int64

    public static let defaultOffsetMs: Int64 = -7000

    public init(offsetMs: Int64 = PictureClock.defaultOffsetMs) {
        self.offsetMs = offsetMs
    }

    /// The picture's moment:
    /// - with a program date: that date plus the offset, not an estimate;
    /// - else the session start plus the player's position plus the offset, an estimate;
    /// - else nil.
    /// A program date or player position that is no moment (not finite, or beyond Int64's
    /// milliseconds) counts as none. Sums saturate rather than trap.
    public func time(programDate: Date?, sessionStart: UTCms?, playerSeconds: Double) -> (t: UTCms, estimated: Bool)? {
        if let programDate, let ms = Self.milliseconds(programDate.timeIntervalSince1970) {
            return (F1Values.add(ms, offsetMs), false)
        }
        guard let sessionStart, let played = Self.milliseconds(playerSeconds) else { return nil }
        return (F1Values.add(F1Values.add(sessionStart, played), offsetMs), true)
    }

    /// Seconds as whole milliseconds; nil when not finite or out of Int64's range.
    static func milliseconds(_ seconds: Double) -> Int64? {
        let ms = (seconds * 1000).rounded()
        // Inside ±9.2e18, so the conversion can't trap.
        guard ms.isFinite, ms > -9.2e18, ms < 9.2e18 else { return nil }
        return Int64(ms)
    }
}

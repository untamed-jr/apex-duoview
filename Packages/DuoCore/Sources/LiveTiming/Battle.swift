import Foundation

/// The battle highlight: your driver within 1.0 s of the car ahead or behind for two timing
/// updates in a row. Races only (elsewhere the interval is a lap-time difference, not a gap on
/// track), and off with no favourite driver; `Tower.rows` applies both.
public enum Battle {
    /// Within this many seconds, inclusive.
    public static let withinSeconds = 1.0

    /// The cars `number` is battling with: those next to it (directly ahead or behind) and within
    /// 1.0 s in each of the last two updates, oldest first in `updates`. Ahead first, then behind.
    /// Fewer than two updates, a car missing or without a position, in the pits, retired or
    /// stopped, and a gap that isn't a time ("LAP 5", "+1 LAP", "") are no battle.
    public static func rivals(of number: String, updates: [[String: DriverTimingState]]) -> [String] {
        guard updates.count >= 2 else { return [] }
        let last = updates[updates.count - 1]
        let both = close(to: number, in: updates[updates.count - 2]).intersection(close(to: number, in: last))
        return both.sorted { (last[$0]?.position ?? .max, $0) < (last[$1]?.position ?? .max, $1) }
    }

    /// The cars next to `number` within the window in one update.
    static func close(to number: String, in states: [String: DriverTimingState]) -> Set<String> {
        guard let me = states[number], racing(me), let p = me.position else { return [] }
        var out = Set<String>()
        for (other, s) in states where other != number && racing(s) {
            if s.position == p - 1, within(me.interval) { out.insert(other) }
            if s.position == p + 1, within(s.interval) { out.insert(other) }
        }
        return out
    }

    static func racing(_ s: DriverTimingState) -> Bool {
        s.position != nil && !s.inPit && !s.retired && !s.stopped
    }

    static func within(_ interval: String) -> Bool {
        gapSeconds(interval).map { $0 <= withinSeconds } ?? false
    }

    /// A gap as F1 writes it ("+0.454", "0.454") in seconds; nil for laps, blanks and anything else.
    static func gapSeconds(_ text: String) -> Double? {
        var body = Substring(text.trimmingCharacters(in: .whitespaces))
        if body.hasPrefix("+") { body = body.dropFirst() }
        guard !body.isEmpty, body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let seconds = Double(body), seconds.isFinite else { return nil }
        return seconds
    }
}

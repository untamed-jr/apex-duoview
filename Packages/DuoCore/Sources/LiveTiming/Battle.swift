import Foundation

/// The battle highlight: your driver within 1.0 s of the car ahead or behind for two timing
/// updates in a row, counting only updates that touch your driver or that rival (another car's
/// update doesn't make a second one). Races only (elsewhere the interval is a lap-time
/// difference, not a gap on track), and off with no favourite driver; `Tower.rows` applies both.
public enum Battle {
    /// Within this many seconds, inclusive.
    public static let withinSeconds = 1.0

    /// The cars `number` is battling with, from timing snapshots oldest first (each a timing
    /// update). A rival is a car next to `number` (directly ahead or behind) in the last snapshot.
    /// It counts when the pair is next to each other and within 1.0 s in each of the last two
    /// updates that touch either car: where its state differs from the update before (the first
    /// snapshot touches every car in it). Ahead first, then behind.
    ///
    /// A car missing or without a position, in the pits, retired or stopped, and a gap that isn't a
    /// time ("LAP 5", "+1 LAP", "") are no battle.
    public static func rivals(of number: String, updates: [[String: DriverTimingState]]) -> [String] {
        guard let last = updates.last else { return [] }
        let found = neighbours(of: number, in: last).filter { rival in
            var touching: [Int] = []
            var i = updates.count - 1
            while i >= 0, touching.count < 2 {
                if i == 0 || updates[i][number] != updates[i - 1][number] || updates[i][rival] != updates[i - 1][rival] {
                    touching.append(i)
                }
                i -= 1
            }
            return touching.count == 2 && touching.allSatisfy { close(number, rival, in: updates[$0]) }
        }
        return ordered(found, by: last)
    }

    /// As `rivals(of:updates:)`, from the timeline at `t`: the updates that touch a car are the
    /// moments its timing changed (`TimingTimeline` keeps a car's state only when it changes, so a
    /// line that only moves mini-sector segments isn't one). Nothing after `t` is read.
    public static func rivals(of number: String, at t: UTCms, timing: TimingTimeline) -> [String] {
        let now = timing.at(t)
        let found = neighbours(of: number, in: now).filter { rival in
            let times = lastTwoTimes(timing.cars[number], timing.cars[rival], atOrBefore: t)
            guard times.count == 2 else { return false }
            return times.allSatisfy { u in
                var pair: [String: DriverTimingState] = [:]
                pair[number] = timing.state(of: number, at: u)
                pair[rival] = timing.state(of: rival, at: u)
                return close(number, rival, in: pair)
            }
        }
        return ordered(found, by: now)
    }

    /// The cars directly ahead of and behind `number`, when it is racing.
    static func neighbours(of number: String, in states: [String: DriverTimingState]) -> [String] {
        guard let me = states[number], racing(me), let p = me.position else { return [] }
        return states.filter { $0.key != number && ($0.value.position == p - 1 || $0.value.position == p + 1) }.map(\.key)
    }

    /// Both racing, next to each other, and the one behind within the window of the one ahead.
    static func close(_ a: String, _ b: String, in states: [String: DriverTimingState]) -> Bool {
        guard let sa = states[a], let sb = states[b], racing(sa), racing(sb),
              let pa = sa.position, let pb = sb.position else { return false }
        if pb == pa - 1 { return within(sa.interval) }
        if pb == pa + 1 { return within(sb.interval) }
        return false
    }

    /// The two latest distinct change times of either car at or before `t`, oldest first.
    static func lastTwoTimes(_ a: TimingTimeline.History?, _ b: TimingTimeline.History?, atOrBefore t: UTCms) -> [UTCms] {
        var tail: [UTCms] = []
        for history in [a, b] {
            guard let history, let i = F1Values.lastIndex(in: history.times, atOrBefore: t) else { continue }
            tail.append(contentsOf: history.times[max(i - 1, 0)...i])
        }
        return Array(Set(tail).sorted().suffix(2))
    }

    static func ordered(_ cars: [String], by states: [String: DriverTimingState]) -> [String] {
        cars.sorted { (states[$0]?.position ?? .max, $0) < (states[$1]?.position ?? .max, $1) }
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

import Foundation

/// Whether the gap between two cars is closing or growing over the last 3 laps.
public enum GapTrend: Sendable, Equatable {
    case closing, growing, steady
}

/// What the Gap Thermometer shows for a pair of cars. Cars are named by racing number; `ahead`
/// is the one nearer the front of the race.
public enum GapReading: Sendable, Equatable {
    /// A gap in ms. `heat` is 0 (cool) to 1 (red), `GapPair.heat(gapMs:)`; `trend` is nil when
    /// there is none to give (too few laps).
    case gap(ms: Int, ahead: String, behind: String, trend: GapTrend?, heat: Double)
    /// F1's own words for a gap that isn't a time ("1L").
    case lapped(text: String, ahead: String, behind: String)
    case inPit(car: String)
    case out(car: String)
    /// Gaps start after the first lap.
    case beforeFirstLap
    /// Qualifying, practice and the like: intervals there are lap-time differences.
    case notRace
}

public enum GapPair {
    /// Gaps within this many ms either way count as steady.
    public static let steadyMs = 100

    /// 0 at 3000 ms or more, 0.5 at 2000, 1 at 1000 or less, linear between.
    public static func heat(gapMs: Int) -> Double {
        min(max(Double(3000 - gapMs) / 2000, 0), 1)
    }

    /// The pair's gap at `t` (picture time), from timing at or before it. Adjacent cars use F1's
    /// interval; others the difference of their gaps to the leader. F1's text stands when it isn't
    /// a time. The trend compares the gap now with the gap `RaceLines.trendLaps` laps ago (as the
    /// race lines do, at the same point of the chasing car's lap), each from the gaps to the leader.
    public static func reading(_ a: String, _ b: String, at t: UTCms, session: LoadedSession) -> GapReading {
        guard session.info.isRace else { return .notRace }
        let states = session.timing.at(t)
        guard states.values.contains(where: { $0.lineCrossedAt != nil }) else { return .beforeFirstLap }
        // A car that is out, or in the pits, is no gap; the first of the pair says.
        for car in [a, b] {
            guard let s = states[car], s.position != nil, !s.retired, !s.stopped else { return .out(car: car) }
            if s.inPit { return .inPit(car: car) }
        }
        guard let sa = states[a], let sb = states[b], let pa = sa.position, let pb = sb.position, a != b else {
            return .beforeFirstLap
        }
        let (front, back) = pa < pb ? (a, b) : (b, a)
        let (sf, sk) = pa < pb ? (sa, sb) : (sb, sa)
        let gaps = PitCircle.gapsToLeader(states, at: t, timing: session.timing)
        let byLeader = RaceLines.difference(gaps, front, back)

        let ms: Int
        if abs(pa - pb) == 1 {
            let text = sk.interval.trimmingCharacters(in: .whitespaces)
            if let m = PitCircle.gapMs(text) {
                ms = m
            } else if !text.isEmpty {
                return .lapped(text: text, ahead: front, behind: back)
            } else if let d = byLeader {
                ms = d
            } else {
                return .beforeFirstLap
            }
        } else {
            // Each car's own words where its gap to the leader isn't a time ("1L"); the leader has none.
            func words(_ s: DriverTimingState) -> String? {
                let text = s.gapToLeader.trimmingCharacters(in: .whitespaces)
                guard s.position != 1, !text.isEmpty, PitCircle.gapMs(text) == nil else { return nil }
                return text
            }
            let wf = words(sf), wk = words(sk)
            if (wf == nil) != (wk == nil) {
                return .lapped(text: wk ?? wf ?? "", ahead: front, behind: back)
            } else if let d = byLeader {
                ms = d
            } else if let text = wk {
                return .lapped(text: text, ahead: front, behind: back)
            } else {
                return .beforeFirstLap
            }
        }
        let gap = max(ms, 0)
        return .gap(ms: gap, ahead: front, behind: back,
                    trend: trend(front: front, back: back, now: byLeader, at: t, session: session), heat: heat(gapMs: gap))
    }

    private static func trend(front: String, back: String, now: Int?, at t: UTCms, session: LoadedSession) -> GapTrend? {
        guard let now, let then = RaceLines.trendTime(car: back, at: t, session: session) else { return nil }
        let before = session.timing.at(then)
        guard let earlier = RaceLines.difference(PitCircle.gapsToLeader(before, at: then, timing: session.timing), front, back)
        else { return nil }
        if abs(now - earlier) <= steadyMs { return .steady }
        return now < earlier ? .closing : .growing
    }

    /// Cars still racing with a position, in race order.
    private static func order(_ states: [String: DriverTimingState]) -> [(number: String, state: DriverTimingState)] {
        states.filter { $0.value.position != nil && !$0.value.retired && !$0.value.stopped }
            .sorted { ($0.value.position ?? 0, $0.key) < ($1.value.position ?? 0, $1.key) }
            .map { (number: $0.key, state: $0.value) }
    }

    /// Your driver and the nearer car ahead or behind (by interval; a car with no time gap is
    /// the farther one), in race order, ahead first. Without a favourite, or one who isn't racing,
    /// P1 and P2. Nil outside races or with fewer than two cars.
    public static func defaultPair(favourite: String?, at t: UTCms, session: LoadedSession) -> (String, String)? {
        guard session.info.isRace else { return nil }
        let cars = order(session.timing.at(t))
        guard cars.count >= 2 else { return nil }
        guard let favourite, let i = cars.firstIndex(where: { $0.number == favourite }) else {
            return (cars[0].number, cars[1].number)
        }
        let ahead = i > 0 ? cars[i - 1] : nil
        let behind = i + 1 < cars.count ? cars[i + 1] : nil
        let toAhead = ahead == nil ? nil : PitCircle.gapMs(cars[i].state.interval)
        let toBehind = behind.flatMap { PitCircle.gapMs($0.state.interval) }
        switch (ahead, behind) {
        case let (a?, b?):
            if let x = toAhead, let y = toBehind { return x <= y ? (a.number, favourite) : (favourite, b.number) }
            return toBehind != nil && toAhead == nil ? (favourite, b.number) : (a.number, favourite)
        case let (a?, nil): return (a.number, favourite)
        case let (nil, b?): return (favourite, b.number)
        default: return nil
        }
    }

    /// Moves a pair `step` places along the race order (+1 a place back). The pair is read from
    /// its front car's place; retired cars are stepped over. Nil past either end, and outside races.
    public static func shifted(_ pair: (String, String), by step: Int, at t: UTCms, session: LoadedSession) -> (String, String)? {
        guard session.info.isRace else { return nil }
        let states = session.timing.at(t)
        let cars = order(states)
        let places = [pair.0, pair.1].compactMap { states[$0]?.position }
        guard places.count == 2, let frontPlace = places.min() else { return nil }
        let before = cars.filter { ($0.state.position ?? 0) < frontPlace }.count
        let present = cars.contains { $0.state.position == frontPlace }
        // A front car that has gone out sits between two places: stepping back lands on the car
        // behind it.
        let target = before + step - (!present && step > 0 ? 1 : 0)
        guard target >= 0, target + 1 < cars.count else { return nil }
        return (cars[target].number, cars[target + 1].number)
    }
}

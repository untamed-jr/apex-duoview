import Foundation

/// What a marker on the Scrub Deck's event strip stands for.
public enum RaceEventKind: Sendable, Equatable {
    /// The session's first "Started": lights out in a race, the session's start otherwise.
    case lightsOut
    /// A car going into the pit lane (after the start; `RaceEvent.end` is when it came out).
    case pit(car: String)
    /// A safety car, VSC or red flag period, drawn as a band to `RaceEvent.end`.
    case safetyCar, vsc, red
    /// A lap faster than every lap before it in the session.
    case fastestLap(car: String)
    case retirement(car: String)
    /// Each time the session went to "Finished".
    case chequered
}

/// One marker on the event strip.
public struct RaceEvent: Sendable, Equatable {
    public var t: UTCms
    /// The race lap it happened on (the leader's lap in progress; the lap just finished for the
    /// chequered flag). Nil outside races, whose strip runs by time.
    public var lap: Int?
    public var kind: RaceEventKind
    /// When a band or a pit stop ended. Nil while it is still going at the cut (picture time),
    /// even if the data goes on to end it: the end isn't shown before it happens.
    public var end: UTCms?

    public init(t: UTCms, lap: Int?, kind: RaceEventKind, end: UTCms?) {
        self.t = t
        self.lap = lap
        self.kind = kind
        self.end = end
    }
}

/// The Scrub Deck's event strip.
public enum RaceEvents {
    /// The events at or before `t` (picture time), oldest first; events at the same moment in
    /// the order lights out, bands, pits, fastest laps, retirements, chequered flag. Nothing
    /// after `t` is read: an event later than `t` is left out and an end later than `t` is nil.
    /// `t` nil is the whole session, ends included (the opt-in "Show the whole race on the Scrub
    /// Deck", off by default).
    public static func list(until t: UTCms?, session: LoadedSession) -> [RaceEvent] {
        let cut = t ?? .max
        let started = session.sessionStatus.started
        let race = session.info.isRace
        func ended(_ end: UTCms?) -> UTCms? { end.flatMap { $0 <= cut ? $0 : nil } }
        func lap(_ u: UTCms, finished: Bool = false) -> Int? {
            guard race else { return nil }
            let done = session.timing.at(u).values.compactMap(\.numberOfLaps).max() ?? 0
            if finished { return max(done, 1) }
            let total = session.header.at(u).totalLaps
            return total.map { min(done + 1, $0) } ?? done + 1
        }

        var out: [RaceEvent] = []
        if let started, started <= cut { out.append(RaceEvent(t: started, lap: lap(started), kind: .lightsOut, end: nil)) }

        for span in session.flags.spans where span.start <= cut {
            let kind: RaceEventKind
            switch span.kind {
            case .safetyCar: kind = .safetyCar
            case .vsc: kind = .vsc
            case .red: kind = .red
            }
            out.append(RaceEvent(t: span.start, lap: lap(span.start), kind: kind, end: ended(span.end)))
        }

        var fastest: [(t: UTCms, car: String, ms: Int)] = []
        var baseline = Int.max
        for number in session.timing.cars.keys.sorted(by: Tower.numberOrder) {
            guard let history = session.timing.cars[number],
                  let last = F1Values.lastIndex(in: history.times, atOrBefore: cut) else { continue }
            var previous: DriverTimingState?
            var pitIn: UTCms?
            for i in 0...last {
                let s = history.states[i], u = history.times[i]
                defer { previous = s }
                guard let before = previous else {
                    // A car's first state (the archive's opening snapshot, or a live join) is no
                    // change; a fastest lap it holds is only the bar to beat.
                    if s.lastLapPace == .overallBest, let ms = s.lastLapMs { baseline = min(baseline, ms) }
                    continue
                }
                if s.inPit, !before.inPit, started.map({ u >= $0 }) ?? true { pitIn = u }
                if !s.inPit, before.inPit, let start = pitIn {
                    out.append(RaceEvent(t: start, lap: lap(start), kind: .pit(car: number), end: u))
                    pitIn = nil
                }
                if s.lastLapPace == .overallBest, let ms = s.lastLapMs,
                   before.lastLapPace != .overallBest || before.lastLapMs != ms {
                    fastest.append((u, number, ms))
                }
                if s.retired, !before.retired { out.append(RaceEvent(t: u, lap: lap(u), kind: .retirement(car: number), end: nil)) }
            }
            if let start = pitIn { out.append(RaceEvent(t: start, lap: lap(start), kind: .pit(car: number), end: nil)) }
        }
        // F1 flags each new fastest lap; one that isn't faster than the last (a flag resent, or
        // moved back to an older lap) is no new marker.
        fastest.sort { $0.t != $1.t ? $0.t < $1.t : Tower.numberOrder($0.car, $1.car) }
        for f in fastest where f.ms < baseline {
            baseline = f.ms
            out.append(RaceEvent(t: f.t, lap: lap(f.t), kind: .fastestLap(car: f.car), end: nil))
        }

        var previous: String?
        for change in session.sessionStatus.changes where change.at <= cut {
            if change.status == "Finished", previous != "Finished" {
                out.append(RaceEvent(t: change.at, lap: lap(change.at, finished: true), kind: .chequered, end: nil))
            }
            previous = change.status
        }

        return out.enumerated().sorted { a, b in
            (a.element.t, rank(a.element.kind), a.offset) < (b.element.t, rank(b.element.kind), b.offset)
        }.map(\.element)
    }

    static func rank(_ kind: RaceEventKind) -> Int {
        switch kind {
        case .lightsOut: return 0
        case .safetyCar, .vsc, .red: return 1
        case .pit: return 2
        case .fastestLap: return 3
        case .retirement: return 4
        case .chequered: return 5
        }
    }
}

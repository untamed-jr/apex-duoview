import Foundation

/// One car on the pit circle.
public struct PitCircleCar: Sendable, Equatable {
    public var number: String
    /// The three-letter code; the number for a car DriverList doesn't name.
    public var tla: String
    /// "RRGGBB", or "" when unknown.
    public var teamColour: String
    /// How far into the lap the car is, in time at the reference pace: 0 at the line, rising in
    /// the direction of travel, below 1.
    public var fraction: Double
    /// The same as an angle: degrees from the finish at the top, in the direction of travel
    /// (0 ..< 360). The view picks which way round that is.
    public var angle: Double
    /// Time behind the leader in ms (0 for the leader), counted through every car ahead.
    public var gapToLeaderMs: Int
    /// The default label: the gap to the next car ahead round the circle, "+1.2".
    public var gapToAhead: String
    /// The label with the toggle on: "Leader", or the gap to the leader, "+12.3".
    public var gapToLeader: String
    /// In the pit lane: the view puts it on the inner arc.
    public var inPit: Bool

    public init(number: String, tla: String, teamColour: String, fraction: Double, angle: Double, gapToLeaderMs: Int,
                gapToAhead: String, gapToLeader: String, inPit: Bool) {
        self.number = number
        self.tla = tla
        self.teamColour = teamColour
        self.fraction = fraction
        self.angle = angle
        self.gapToLeaderMs = gapToLeaderMs
        self.gapToAhead = gapToAhead
        self.gapToLeader = gapToLeader
        self.inPit = inPit
    }
}

/// The pit circle at one moment.
public struct PitCircleState: Sendable, Equatable {
    /// One lap round the circle, in ms.
    public var referenceLapMs: Int
    /// How many green laps `referenceLapMs` averages: 5, or 0 before the leader has 5 and it is
    /// their typical lap or last lap (the 0.98 fallback).
    public var greenLaps: Int
    /// What a stop costs (`PitCircle.pitLossMs`).
    public var pitLossMs: Int
    /// How many clean stops `pitLossMs` is the median of; 0 when it is the stored value or 22 s.
    public var measuredStops: Int
    public var leader: String
    /// The leader's lap in progress.
    public var lap: Int?
    /// In running order (by gap to the leader). Retired and stopped cars are left out, and so is
    /// a car with no gap at all (no time, no chain and no lap in common with the leader yet).
    public var cars: [PitCircleCar]

    public init(referenceLapMs: Int, greenLaps: Int, pitLossMs: Int, measuredStops: Int, leader: String, lap: Int?,
                cars: [PitCircleCar]) {
        self.referenceLapMs = referenceLapMs
        self.greenLaps = greenLaps
        self.pitLossMs = pitLossMs
        self.measuredStops = measuredStops
        self.leader = leader
        self.lap = lap
        self.cars = cars
    }
}

/// Where a stop now would put a car.
public struct Rejoin: Sendable, Equatable {
    /// Its position after the stop.
    public var position: Int
    /// The racing number of the car it would come out behind; nil when it would come out in
    /// the lead.
    public var behind: String?
    /// How far behind `behind` it would come out; with no car ahead, its lead over the car
    /// behind (0 when there is none).
    public var gapMs: Int

    public init(position: Int, behind: String?, gapMs: Int) {
        self.position = position
        self.behind = behind
        self.gapMs = gapMs
    }

    /// The pit circle's line: "If HAM stops now, out 2.1 s behind NOR" ("..., out in the lead").
    public func text(car: String, session: LoadedSession) -> String {
        let me = PitCircle.tla(car, session)
        guard let behind else { return "If \(me) stops now, out in the lead" }
        return "If \(me) stops now, out \(PitCircle.secondsText(gapMs)) behind \(PitCircle.tla(behind, session))"
    }

    /// Race Engineer's line: "Pit now → P7 behind ALO" ("Pit now → P1" in the lead).
    public func consoleText(session: LoadedSession) -> String {
        guard let behind else { return "Pit now → P\(position)" }
        return "Pit now → P\(position) behind \(PitCircle.tla(behind, session))"
    }
}

/// The pit circle, after MultiViewer's and Android's (PitCircle.kt, PitWindow.kt): the lap as a
/// circle in time at the leader's pace, the finish at the top. Each car sits as far behind the
/// leader as its gap, so a stop costs the same arc wherever it's made, and the cars a stop's
/// length behind are the ones it would come out among. Races only, as the battle rule: elsewhere
/// the gaps are lap-time differences, not time on track.
public enum PitCircle {
    /// The reference lap averages this many of the leader's latest green laps.
    public static let referenceLaps = 5
    /// What a stop costs before any has been measured here.
    public static let typicalLossMs = 22_000
    /// A lap shorter or longer than this wasn't run on track (a red flag, a count sent twice).
    static let lapRangeMs: ClosedRange<Int64> = 40_000...240_000
    /// A stop's time in the pit lane, and what it cost, outside these isn't an ordinary stop.
    static let laneRangeMs: ClosedRange<Int64> = 12_000...60_000
    static let lossRangeMs: ClosedRange<Int> = 10_000...45_000
    /// The furthest round the lap the leader is drawn before it crosses the line.
    static let leaderHold = 0.999

    // MARK: Reference lap and pit loss

    /// One lap round the circle: the average of the leader's last 5 green laps (ms, oldest
    /// first). Before the leader has 5 green laps (the spec): their typical lap, then their last
    /// timed lap, as F1 gives it (the 0.98 fix for joining live part-way, when no lap has been
    /// timed here yet). Nil when there is none of those.
    public static func referenceLapMs(leaderGreenLaps: [Int], typicalLapMs: Int?, lastLapMs: Int?) -> Int? {
        guard leaderGreenLaps.count >= referenceLaps else { return typicalLapMs ?? lastLapMs }
        let green = leaderGreenLaps.suffix(referenceLaps)
        return green.reduce(0, +) / green.count
    }

    /// What a stop costs: the median of this session's clean stops (`sessionStops`), else the
    /// value stored for this circuit (`TimingSettings.pitLossMs`), else 22 s.
    public static func pitLossMs(sessionStops: [Int], storedMs: Int?) -> Int {
        if !sessionStops.isEmpty { return sessionStops.sorted()[sessionStops.count / 2] }
        return storedMs ?? typicalLossMs
    }

    /// The car's laps finished by `t` that could have been run on track, in ms, oldest first:
    /// the times between its line crossings.
    public static func laps(of car: String, at t: UTCms, session: LoadedSession) -> [Int] {
        windows(crossings(of: car, upTo: t, timing: session.timing)).map { Int($0.end - $0.start) }
    }

    /// The car's green laps by `t`, in ms, oldest first: laps with no pit stop in them, run
    /// while the track was clear at their midpoint (a local yellow counts as clear; a safety car,
    /// VSC or red flag doesn't).
    public static func greenLaps(of car: String, at t: UTCms, session: LoadedSession) -> [Int] {
        let stops = pitStops(of: car, upTo: t, timing: session.timing)
        return windows(crossings(of: car, upTo: t, timing: session.timing)).filter { lap in
            let clear: Bool
            switch session.flags.status(at: lap.start + (lap.end - lap.start) / 2) {
            case .clear, .yellow: clear = true
            default: clear = false
            }
            return clear && !stops.contains { $0.in < lap.end && ($0.out ?? t) > lap.start }
        }.map { Int($0.end - $0.start) }
    }

    /// The car's typical lap at `t`: the median of its last 5 laps (`laps`); nil before it has
    /// finished two crossings' worth.
    public static func typicalLapMs(of car: String, at t: UTCms, session: LoadedSession) -> Int? {
        let recent = laps(of: car, at: t, session: session).suffix(referenceLaps).sorted()
        return recent.isEmpty ? nil : recent[recent.count / 2]
    }

    /// The reference lap at `t`, from the leader's laps; with how many green laps it averages.
    /// F1 sends no time for a race's first lap (São Paulo 2026), so until the leader's second
    /// crossing its last lap is the time from lights out to its first, when that could be a lap
    /// run on track (40–240 s; not across a red flag or an aborted start).
    static func reference(leader: String, at t: UTCms, session: LoadedSession) -> (ms: Int, green: Int)? {
        let green = greenLaps(of: leader, at: t, session: session).suffix(referenceLaps)
        let state = session.timing.state(of: leader, at: t)
        var last = state?.lastLapMs
        if last == nil, state?.numberOfLaps == 1, let crossed = state?.lineCrossedAt,
           let start = session.sessionStatus.started, lapRangeMs.contains(F1Values.sub(crossed, start)) {
            last = Int(F1Values.sub(crossed, start))
        }
        guard let ms = referenceLapMs(leaderGreenLaps: Array(green), typicalLapMs: typicalLapMs(of: leader, at: t, session: session),
                                      lastLapMs: last) else { return nil }
        return (ms, green.count >= referenceLaps ? referenceLaps : 0)
    }

    /// What each clean stop finished by `t` cost, in ms, in the order made: the laps it spans
    /// (from the line before it went in to the line after it came out) less as many of the car's
    /// typical laps before the stop. A stop is clean when no safety car, VSC or red flag overlaps
    /// those laps and its time in the lane (12–60 s) and its cost (10–45 s) look like one ordinary
    /// stop. Races only. Nothing after `t` is read.
    public static func sessionStops(until t: UTCms, session: LoadedSession) -> [Int] {
        guard session.info.isRace else { return [] }
        var out: [(at: UTCms, ms: Int)] = []
        for number in session.timing.cars.keys {
            let line = crossings(of: number, upTo: t, timing: session.timing)
            for stop in pitStops(of: number, upTo: t, timing: session.timing) {
                guard let exit = stop.out, laneRangeMs.contains(exit - stop.in),
                      let before = line.last(where: { $0 <= stop.in }),
                      let after = line.first(where: { $0 >= exit }) else { continue }
                let spanned = line.filter { $0 > before && $0 <= after }.count
                let earlier = windows(line.filter { $0 <= before }).suffix(referenceLaps).map { Int($0.end - $0.start) }.sorted()
                guard spanned > 0, !earlier.isEmpty else { continue }
                let typical = earlier[earlier.count / 2]
                let loss = Int(after - before) - spanned * typical
                let flagged = session.flags.spans.contains { $0.start < after && ($0.end ?? .max) > before }
                guard !flagged, lossRangeMs.contains(loss) else { continue }
                out.append((stop.in, loss))
            }
        }
        return out.sorted { $0.at < $1.at }.map(\.ms)
    }

    /// The pit loss at `t`: this session's clean stops so far, else `storedMs`, else 22 s.
    public static func pitLossMs(at t: UTCms, session: LoadedSession, storedMs: Int? = nil) -> Int {
        pitLossMs(sessionStops: sessionStops(until: t, session: session), storedMs: storedMs)
    }

    // MARK: The circle

    /// The circle at `t` (picture time), from timing at or before `t`. Nil outside races, and
    /// until the leader has finished a lap ("The circle starts once the leader has finished a
    /// lap."): the leader is placed by the time since it last crossed the line, so a live session
    /// joined part-way waits for its next crossing; from then its last lap stands in as the
    /// reference until it has timed one here. Every other car sits its gap behind the leader.
    /// `storedPitLossMs` is this circuit's stored pit loss.
    public static func layout(at t: UTCms, session: LoadedSession, storedPitLossMs: Int? = nil) -> PitCircleState? {
        guard session.info.isRace else { return nil }
        let states = session.timing.at(t)
        guard let leader = states.first(where: { $0.value.position == 1 && !$0.value.retired && !$0.value.stopped })?.key,
              let crossed = states[leader]?.lineCrossedAt,
              let reference = reference(leader: leader, at: t, session: session) else { return nil }
        let ref = Double(reference.ms)
        // A lap slower than the reference (a safety car, a stop, a red flag) holds the leader
        // just short of the line until it crosses, instead of wrapping the field round.
        let leaderAt = fraction(min(Double(F1Values.sub(t, crossed)) / ref, leaderHold))
        let gaps = gapsToLeader(states, at: t, timing: session.timing)
        let placed = ordered(gaps).map { (number: $0.key, gap: $0.value, at: fraction(leaderAt - Double($0.value) / ref)) }
        let stops = sessionStops(until: t, session: session)
        let cars = placed.map { car -> PitCircleCar in
            let ahead = placed.filter { $0.number != car.number }.map { fraction($0.at - car.at) }.min()
            let driver = session.drivers[car.number]
            return PitCircleCar(
                number: car.number,
                tla: driver?.tla ?? car.number,
                teamColour: driver?.teamColour ?? "",
                fraction: car.at,
                angle: car.at * 360,
                gapToLeaderMs: car.gap,
                gapToAhead: ahead.map { signedText(Int(($0 * ref).rounded())) } ?? "",
                gapToLeader: car.number == leader ? "Leader" : signedText(car.gap),
                inPit: states[car.number]?.inPit ?? false
            )
        }
        let total = session.header.at(t).totalLaps
        let lap = states[leader]?.numberOfLaps.map { n in total.map { min(n + 1, $0) } ?? n + 1 }
        return PitCircleState(referenceLapMs: reference.ms, greenLaps: reference.green,
                              pitLossMs: pitLossMs(sessionStops: stops, storedMs: storedPitLossMs),
                              measuredStops: stops.count, leader: leader, lap: lap, cars: cars)
    }

    /// Where `car` would come out if it stopped at `t`: its gap to the leader plus `pitLossMs`,
    /// among every other racing car's gap. Nil outside races, for a car in the pits, retired,
    /// stopped, or whose gap isn't known.
    public static func rejoin(car: String, at t: UTCms, session: LoadedSession, pitLossMs: Int) -> Rejoin? {
        guard session.info.isRace else { return nil }
        let states = session.timing.at(t)
        guard let me = states[car], !me.inPit else { return nil }
        let gaps = gapsToLeader(states, at: t, timing: session.timing)
        guard let mine = gaps[car] else { return nil }
        let out = mine + max(pitLossMs, 0)
        let others = ordered(gaps.filter { $0.key != car })
        let ahead = others.filter { $0.value <= out }
        guard let behind = ahead.last else {
            return Rejoin(position: 1, behind: nil, gapMs: others.first.map { $0.value - out } ?? 0)
        }
        return Rejoin(position: ahead.count + 1, behind: behind.key, gapMs: out - behind.value)
    }

    // MARK: Shared with RaceLines

    /// Each racing car's time behind the leader in ms (the leader 0), from `states` (timing at
    /// `t`): its GapToLeader when that is a time; else the car ahead's plus its interval; else
    /// (a lapped car whose gaps read "1L" or "+1 LAP") its crossing of the latest lap both it and
    /// the leader had finished by `t`, less the leader's. The chain goes on behind such a car.
    /// Retired and stopped cars, and cars with none of these, are left out.
    static func gapsToLeader(_ states: [String: DriverTimingState], at t: UTCms, timing: TimingTimeline) -> [String: Int] {
        var out: [String: Int] = [:]
        let racing = states.filter { !$0.value.retired && !$0.value.stopped }
        let ordered = racing.filter { $0.value.position != nil }.sorted { ($0.value.position ?? 0) < ($1.value.position ?? 0) }
        let leader = ordered.first { $0.value.position == 1 }?.key
        var leaderLaps: [Int: UTCms]?
        func byCrossings(_ number: String) -> Int? {
            guard let leader else { return nil }
            if leaderLaps == nil {
                leaderLaps = Dictionary(timing.completedLaps(of: leader, upTo: t).map { ($0.lap, $0.crossedAt) }) { _, last in last }
            }
            for lap in timing.completedLaps(of: number, upTo: t).reversed() {
                if let theirs = leaderLaps?[lap.lap] { return Int(clamping: F1Values.sub(lap.crossedAt, theirs)) }
            }
            return nil
        }
        var previous: Int?
        for (number, s) in ordered {
            let gap: Int?
            if s.position == 1 {
                gap = 0
            } else {
                gap = gapMs(s.gapToLeader) ?? previous.flatMap { p in gapMs(s.interval).map { p + $0 } } ?? byCrossings(number)
            }
            out[number] = gap
            previous = gap
        }
        // Cars without a position are placed by their gap.
        for (number, s) in racing where s.position == nil {
            if let gap = gapMs(s.gapToLeader) ?? byCrossings(number) { out[number] = gap }
        }
        return out
    }

    /// Gaps in running order: smallest first, ties by number.
    static func ordered(_ gaps: [String: Int]) -> [(key: String, value: Int)] {
        gaps.sorted { $0.value != $1.value ? $0.value < $1.value : Tower.numberOrder($0.key, $1.key) }
    }

    /// F1's gap text ("+4.401", "65.123", "1:05.123") in ms; nil for "LAP 7", "1L", "+1 LAP", "".
    static func gapMs(_ text: String) -> Int? {
        var body = Substring(text.trimmingCharacters(in: .whitespaces))
        if body.hasPrefix("+") { body = body.dropFirst() }
        return F1Values.durationMs(String(body))
    }

    /// Times the car crossed the line up to `t`, oldest first.
    static func crossings(of car: String, upTo t: UTCms, timing: TimingTimeline) -> [UTCms] {
        guard let history = timing.cars[car], let last = F1Values.lastIndex(in: history.times, atOrBefore: t) else { return [] }
        var out: [UTCms] = []
        for state in history.states[...last] {
            guard let at = state.lineCrossedAt, at != out.last, at <= t else { continue }
            out.append(at)
        }
        return out
    }

    /// Laps between consecutive crossings that could have been run on track.
    static func windows(_ crossings: [UTCms]) -> [(start: UTCms, end: UTCms)] {
        zip(crossings, crossings.dropFirst()).map { (start: $0, end: $1) }.filter { lapRangeMs.contains($0.end - $0.start) }
    }

    /// The car's trips down the pit lane up to `t`: in, and out (nil while still in at `t`).
    static func pitStops(of car: String, upTo t: UTCms, timing: TimingTimeline) -> [(in: UTCms, out: UTCms?)] {
        guard let history = timing.cars[car], let last = F1Values.lastIndex(in: history.times, atOrBefore: t) else { return [] }
        var out: [(in: UTCms, out: UTCms?)] = []
        var since: UTCms?
        for i in 0...last {
            let inPit = history.states[i].inPit
            if inPit, since == nil { since = history.times[i] }
            if !inPit, let start = since { out.append((start, history.times[i])); since = nil }
        }
        if let since { out.append((since, nil)) }
        return out
    }

    static func fraction(_ x: Double) -> Double {
        let f = x - x.rounded(.down)
        return f >= 1 ? 0 : f
    }

    static func tla(_ number: String, _ session: LoadedSession) -> String {
        session.drivers[number]?.tla ?? number
    }

    /// "2.1 s", to the nearest tenth.
    static func secondsText(_ ms: Int) -> String {
        let tenths = (max(ms, 0) + 50) / 100
        return "\(tenths / 10).\(tenths % 10) s"
    }

    /// "+1.2", to the nearest tenth.
    static func signedText(_ ms: Int) -> String {
        let tenths = (abs(ms) + 50) / 100
        return "\(ms < 0 ? "-" : "+")\(tenths / 10).\(tenths % 10)"
    }
}

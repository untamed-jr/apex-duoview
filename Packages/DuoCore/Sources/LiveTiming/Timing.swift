import Foundation
import F1TV

/// How a sector or lap compares: grey (none yet), yellow, green, purple.
public enum SectorPace: Sendable, Equatable {
    case empty, set, personalBest, overallBest

    /// From a timing cell: its Value, PersonalFastest and OverallFastest.
    static func of(_ cell: JSONValue) -> SectorPace {
        if cell["Value"].string.isEmpty { return .empty }
        if cell["OverallFastest"].bool == true { return .overallBest }
        if cell["PersonalFastest"].bool == true { return .personalBest }
        return .set
    }
}

/// One car's timing at a moment, from TimingData.
public struct DriverTimingState: Sendable, Equatable {
    public var position: Int?
    /// Laps completed, as F1 counts them.
    public var numberOfLaps: Int?
    public var lastLapMs: Int?
    public var lastLapPace: SectorPace
    public var bestLapMs: Int?
    /// To the leader in a race ("LAP 5" for the leader), to the fastest lap in qualifying.
    public var gapToLeader: String
    /// To the car ahead.
    public var interval: String
    /// S1…S3 of the lap in progress: blank from the line until each is set.
    public var sectors: [SectorPace]
    public var inPit: Bool
    public var pitOut: Bool
    public var retired: Bool
    public var stopped: Bool
    public var knockedOut: Bool
    /// When the car last crossed the line (its lap count went up, other than as it left the pits).
    public var lineCrossedAt: UTCms?
    /// When the lap in progress began: the last crossing, or leaving the pits when F1 started a
    /// lap count there (qualifying), whichever is later. The running lap clock counts from it.
    public var lapStartedAt: UTCms?

    public init(position: Int? = nil, numberOfLaps: Int? = nil, lastLapMs: Int? = nil, lastLapPace: SectorPace = .empty,
                bestLapMs: Int? = nil, gapToLeader: String = "", interval: String = "",
                sectors: [SectorPace] = [.empty, .empty, .empty], inPit: Bool = false, pitOut: Bool = false,
                retired: Bool = false, stopped: Bool = false, knockedOut: Bool = false, lineCrossedAt: UTCms? = nil,
                lapStartedAt: UTCms? = nil) {
        self.position = position
        self.numberOfLaps = numberOfLaps
        self.lastLapMs = lastLapMs
        self.lastLapPace = lastLapPace
        self.bestLapMs = bestLapMs
        self.gapToLeader = gapToLeader
        self.interval = interval
        self.sectors = sectors
        self.inPit = inPit
        self.pitOut = pitOut
        self.retired = retired
        self.stopped = stopped
        self.knockedOut = knockedOut
        self.lineCrossedAt = lineCrossedAt
        self.lapStartedAt = lapStartedAt ?? lineCrossedAt
    }
}

/// A lap a car finished at the line, as its timing showed it from some moment on.
public struct CompletedLap: Sendable, Equatable {
    /// F1's lap count after the crossing: the lap finished.
    public var lap: Int
    public var crossedAt: UTCms
    /// F1's LastLapTime for this lap, once sent; nil before then, and for a race's first lap
    /// (F1 sends none).
    public var lapMs: Int?
    public var pace: SectorPace
    /// S1…S3 of this lap: those set since the crossing before, and a final sector arriving up
    /// to 3 s after the line.
    public var sectors: [SectorPace]

    public init(lap: Int, crossedAt: UTCms, lapMs: Int?, pace: SectorPace, sectors: [SectorPace]) {
        self.lap = lap
        self.crossedAt = crossedAt
        self.lapMs = lapMs
        self.pace = pace
        self.sectors = sectors
    }
}

/// Every car's timing through a session. Each TimingData line is merged into the car's state
/// (TopicMerge); a car's derived state is kept only when it changes (most lines only move
/// mini-sector segments), so `at` is a binary search per car rather than a replay.
///
/// Rules ported from Android's DriverTiming, with two changes. Sector colours come from F1's
/// merged flags: F1 sends PersonalFastest/OverallFastest only when they change (an emptied
/// sector gets an explicit false), so resetting them at the line, as Android did, would turn a
/// personal best yellow. And a car's first NumberOfLaps counts as crossing the line when the car
/// was already known without one: 2026 sends none until lap 1 ends. A third: a count raised in
/// the same delta as PitOut is no crossing. In 2026 qualifying F1 raises NumberOfLaps as each run
/// leaves the pits (São Paulo, car 12 at offsets 815622, 6094211, 7348411, 8051554, 8871348);
/// that starts a lap (`lapStartedAt`) but isn't the line. In races the count goes up in the pit
/// lane while InPit is set, with PitOut later on its own, so races are unchanged. Kept from Android: the
/// sectors go blank at the line until each is set again, and a final sector arriving up to 3 s
/// after the line belongs to the lap just done.
public struct TimingTimeline: Sendable {
    struct History: Sendable {
        var times: [UTCms] = []
        var states: [DriverTimingState] = []
    }

    let cars: [String: History]
    /// The moments some car's state changed, oldest first ("timing updates").
    public let updateTimes: [UTCms]
    let partTimes: [UTCms]
    let parts: [Int]
    /// Each car's finished laps, kept apart from its states so a lap's details arriving after
    /// the line (the final sector, the lap time) add no timing update: each entry is one lap as
    /// it stood from that time on.
    let completed: [String: LapHistory]

    struct LapHistory: Sendable {
        var times: [UTCms] = []
        var laps: [CompletedLap] = []
    }

    static let lateSectorMs: Int64 = 3_000

    /// The laps `number` finished, as known at `t`: each as it stood at or before `t` (a final
    /// sector or lap time sent after `t` is not there yet), oldest first.
    public func completedLaps(of number: String, upTo t: UTCms) -> [CompletedLap] {
        guard let history = completed[number], let last = F1Values.lastIndex(in: history.times, atOrBefore: t) else { return [] }
        var out: [CompletedLap] = []
        for lap in history.laps[...last] {
            if out.last?.crossedAt == lap.crossedAt { out[out.count - 1] = lap } else { out.append(lap) }
        }
        return out
    }

    /// Each car's state at `t`: the latest at or before it. Cars with nothing yet are absent.
    public func at(_ t: UTCms) -> [String: DriverTimingState] {
        var out: [String: DriverTimingState] = [:]
        for (number, history) in cars {
            if let i = F1Values.lastIndex(in: history.times, atOrBefore: t) { out[number] = history.states[i] }
        }
        return out
    }

    public func state(of number: String, at t: UTCms) -> DriverTimingState? {
        guard let history = cars[number], let i = F1Values.lastIndex(in: history.times, atOrBefore: t) else { return nil }
        return history.states[i]
    }

    /// Every time a car crossed the line (its lap count went up), up to and including `t`, by
    /// car, oldest first per car. For geometry (where the line is on the map), which may read the
    /// whole session; anything shown as data must pass picture time as `t`, never later.
    public func lineCrossings(upTo t: UTCms) -> [(car: String, at: UTCms)] {
        var out: [(car: String, at: UTCms)] = []
        for number in cars.keys.sorted() {
            guard let history = cars[number] else { continue }
            var last: UTCms?
            for (i, state) in history.states.enumerated() where history.times[i] <= t {
                guard let crossed = state.lineCrossedAt, crossed != last, crossed <= t else { continue }
                out.append((car: number, at: crossed))
                last = crossed
            }
        }
        return out
    }

    /// The part of qualifying running at `t` (TimingData's SessionPart), if the session has them.
    public func sessionPart(at t: UTCms) -> Int? {
        F1Values.lastIndex(in: partTimes, atOrBefore: t).map { parts[$0] }
    }

    /// TimingData lines (the first is the full state, the rest deltas), timed at
    /// `streamStart + offset`.
    public static func build(lines: [StreamLine], streamStart: UTCms) -> TimingTimeline {
        var builder = Builder(streamStart: streamStart)
        for line in lines { builder.add(line) }
        return builder.timeline
    }

    /// `build`, a line at a time: the live feed keeps one and adds only the lines that came
    /// since it last asked. Histories are changed in place, so a line costs the same however
    /// long the session has run.
    struct Builder: LineFolder {
        let streamStart: UTCms
        private var live: [String: Live] = [:]
        private var cars: [String: History] = [:]
        private var updates: [UTCms] = []
        private var top: JSONValue = .null
        private var part: Int?
        private var partTimes: [UTCms] = [], parts: [Int] = []
        private var completed: [String: LapHistory] = [:]

        init(streamStart: UTCms) {
            self.streamStart = streamStart
        }

        /// The timeline so far.
        var timeline: TimingTimeline {
            TimingTimeline(cars: cars, updateTimes: updates, partTimes: partTimes, parts: parts, completed: completed)
        }

        mutating func add(_ line: StreamLine) {
            let t = F1Values.add(streamStart, line.offsetMs)
            guard case .object(var members) = line.json else { return }
            let lineDeltas = members.removeValue(forKey: "Lines") ?? .null
            var touched = Set<String>()
            if !members.isEmpty {
                top = TopicMerge.merge(top, .object(members))
                if let p = top["SessionPart"].int, (1...9).contains(p), p != part {
                    part = p
                    partTimes.append(t)
                    parts.append(p)
                    touched.formUnion(live.keys)  // the gaps come from another part's Stats now
                }
            }
            if case .object(let deltas) = lineDeltas {
                for (number, delta) in deltas {
                    guard case .object = delta else { continue }
                    live[number, default: Live()].apply(delta, at: t)
                    touched.insert(number)
                }
            }
            var changed = false
            for number in touched {
                guard let car = live[number] else { continue }
                if let lap = car.lap, completed[number]?.laps.last != lap {
                    if completed[number]?.times.last == t, let i = completed[number]?.laps.indices.last {
                        completed[number]?.laps[i] = lap
                    } else {
                        completed[number, default: LapHistory()].times.append(t)
                        completed[number, default: LapHistory()].laps.append(lap)
                    }
                }
                var state = car.state(part: part)
                if let last = cars[number]?.states.last {
                    if last == state { continue }
                    if last.sectors == state.sectors { state.sectors = last.sectors }  // share storage
                }
                if cars[number]?.times.last == t, let i = cars[number]?.states.indices.last {
                    cars[number]?.states[i] = state
                } else {
                    cars[number, default: History()].times.append(t)
                    cars[number, default: History()].states.append(state)
                }
                changed = true
            }
            if changed, updates.last != t { updates.append(t) }
        }
    }

    /// One car while building: its merged TimingData line plus what F1's state doesn't keep.
    struct Live {
        var line: JSONValue = .null
        /// Whether each sector has been set since the car last crossed the line.
        var fresh = [true, true, true]
        var crossedAt: UTCms?
        var lapStart: UTCms?
        var laps: Int?
        var inPit = false
        /// The lap last finished at the line, as known so far.
        var lap: CompletedLap?

        mutating func apply(_ delta: JSONValue, at t: UTCms) {
            // Sectors first, so a final sector sent with the crossing counts for the lap it ends.
            var lateFinal = false
            for (i, cell) in Self.sectorCells(delta["Sectors"]) where (0..<3).contains(i) {
                guard case .object(let members) = cell, let value = members["Value"] else { continue }
                if value.string.isEmpty { continue }
                let late = i == 2 && !fresh[0] && crossedAt.map { (1...TimingTimeline.lateSectorMs).contains(F1Values.sub(t, $0)) } == true
                if late { lateFinal = true } else { fresh[i] = true }
            }
            let known = !line.isNull
            line = TopicMerge.merge(line, delta)
            if let n = delta["NumberOfLaps"].int {
                // A count that goes up is a crossing; so is the first count for a car already
                // known without one (2026 sends none until lap 1 ends). A car's first line —
                // a live feed's opening snapshot — is never one. A count raised with PitOut
                // (qualifying) starts the out lap at the pit exit: a new lap, not the line.
                let rose = laps.map { n > $0 } ?? (known && n > 0)
                if rose {
                    if delta["PitOut"].bool != true {
                        crossedAt = t
                        // The lap just finished: the sectors set since the last crossing.
                        let sectors = line["Sectors"]
                        lap = CompletedLap(lap: n, crossedAt: t, lapMs: nil, pace: .empty,
                                           sectors: (0..<3).map { fresh[$0] ? SectorPace.of(Self.element(sectors, $0)) : .empty })
                    }
                    lapStart = t
                    fresh = [false, false, false]
                }
                laps = n
            }
            if let inPit = delta["InPit"].bool { self.inPit = inPit }
            if delta["PitOut"].bool == true { inPit = false }
            if var finished = lap, finished.crossedAt == crossedAt {
                // A final sector up to 3 s after the line, and the lap time (sent with the
                // crossing, or after it; F1 sends none for a race's first lap), belong to it.
                if lateFinal { finished.sectors[2] = SectorPace.of(Self.element(line["Sectors"], 2)) }
                let time = delta["LastLapTime"]
                if !time["Value"].isNull {
                    finished.lapMs = F1Values.durationMs(line["LastLapTime"]["Value"].string)
                    finished.pace = finished.lapMs == nil ? .empty : SectorPace.of(line["LastLapTime"])
                } else if case .object = time, finished.lapMs != nil {
                    finished.pace = SectorPace.of(line["LastLapTime"])
                }
                lap = finished
            }
        }

        func state(part: Int?) -> DriverTimingState {
            let stats = Self.element(line["Stats"], max((part ?? 1) - 1, 0))
            func text(_ candidates: JSONValue...) -> String {
                for c in candidates where !c.isNull { return c.string }
                return ""
            }
            let sectors = line["Sectors"]
            return DriverTimingState(
                position: line["Position"].int,
                numberOfLaps: line["NumberOfLaps"].int,
                lastLapMs: F1Values.durationMs(line["LastLapTime"]["Value"].string),
                lastLapPace: SectorPace.of(line["LastLapTime"]),
                bestLapMs: F1Values.durationMs(line["BestLapTime"]["Value"].string),
                gapToLeader: text(line["GapToLeader"], line["TimeDiffToFastest"], stats["TimeDiffToFastest"]),
                interval: text(line["IntervalToPositionAhead"]["Value"], line["TimeDiffToPositionAhead"],
                               stats["TimeDifftoPositionAhead"], stats["TimeDiffToPositionAhead"]),
                sectors: (0..<3).map { fresh[$0] ? SectorPace.of(Self.element(sectors, $0)) : .empty },
                inPit: inPit,
                pitOut: line["PitOut"].bool ?? false,
                retired: line["Retired"].bool ?? false,
                stopped: line["Stopped"].bool ?? false,
                knockedOut: line["KnockedOut"].bool ?? false,
                lineCrossedAt: crossedAt,
                lapStartedAt: lapStart
            )
        }

        /// Sectors come as a list in the first line and index-keyed objects after.
        static func sectorCells(_ value: JSONValue) -> [(Int, JSONValue)] {
            switch value {
            case .array(let items): return Array(items.enumerated())
            case .object(let members): return members.compactMap { key, v in Int(key).map { ($0, v) } }
            default: return []
            }
        }

        static func element(_ value: JSONValue, _ index: Int) -> JSONValue {
            if case .object = value { return value[String(index)] }
            return value[index]
        }
    }
}

/// One set of tyres in TimingAppData.
public struct Stint: Sendable, Equatable {
    /// "SOFT", "MEDIUM", "HARD", "INTERMEDIATE", "WET" (F1's words).
    public var compound: String
    public var isNew: Bool
    /// The set's age in laps when fitted.
    public var startLaps: Int
    /// Laps on the set so far, its age when fitted included.
    public var totalLaps: Int

    public init(compound: String, isNew: Bool, startLaps: Int, totalLaps: Int) {
        self.compound = compound
        self.isNew = isNew
        self.startLaps = startLaps
        self.totalLaps = totalLaps
    }
}

/// Each car's stints through a session, from TimingAppData (merged with TopicMerge; kept when
/// they change). Stints whose compound isn't known yet are left out.
public struct StintTimeline: Sendable {
    struct History: Sendable {
        var times: [UTCms] = []
        var stints: [[Stint]] = []
    }

    let cars: [String: History]

    public static func build(lines: [StreamLine], streamStart: UTCms) -> StintTimeline {
        var builder = Builder(streamStart: streamStart)
        for line in lines { builder.add(line) }
        return builder.timeline
    }

    /// `build`, a line at a time (as `TimingTimeline.Builder`).
    struct Builder: LineFolder {
        let streamStart: UTCms
        private var merged: [String: JSONValue] = [:]
        private var cars: [String: History] = [:]

        init(streamStart: UTCms) {
            self.streamStart = streamStart
        }

        var timeline: StintTimeline { StintTimeline(cars: cars) }

        mutating func add(_ line: StreamLine) {
            guard case .object(let deltas) = line.json["Lines"] else { return }
            let t = F1Values.add(streamStart, line.offsetMs)
            for (number, delta) in deltas {
                guard case .object = delta else { continue }
                let state = TopicMerge.merge(merged[number] ?? .null, delta)
                merged[number] = state
                let stints = F1Values.ordered(state["Stints"]).compactMap { s -> Stint? in
                    let compound = s["Compound"].string
                    guard !compound.isEmpty else { return nil }
                    return Stint(compound: compound, isNew: s["New"].bool ?? false,
                                 startLaps: s["StartLaps"].int ?? 0, totalLaps: s["TotalLaps"].int ?? 0)
                }
                if cars[number]?.stints.last == stints { continue }
                if cars[number]?.times.last == t, let i = cars[number]?.stints.indices.last {
                    cars[number]?.stints[i] = stints
                } else {
                    cars[number, default: History()].times.append(t)
                    cars[number, default: History()].stints.append(stints)
                }
            }
        }
    }

    /// Each car's stints at `t`, oldest first. Cars with nothing yet are absent.
    public func at(_ t: UTCms) -> [String: [Stint]] {
        var out: [String: [Stint]] = [:]
        for (number, history) in cars {
            if let i = F1Values.lastIndex(in: history.times, atOrBefore: t) { out[number] = history.stints[i] }
        }
        return out
    }
}

/// What the timing tower's header shows.
public struct SessionHeader: Sendable, Equatable {
    public var lap: Int?
    public var totalLaps: Int?
    /// The session clock, in whole seconds.
    public var clockRemaining: Int?
    public var airTemp: Double?
    public var trackTemp: Double?
    public var raining: Bool

    public init(lap: Int? = nil, totalLaps: Int? = nil, clockRemaining: Int? = nil,
                airTemp: Double? = nil, trackTemp: Double? = nil, raining: Bool = false) {
        self.lap = lap
        self.totalLaps = totalLaps
        self.clockRemaining = clockRemaining
        self.airTemp = airTemp
        self.trackTemp = trackTemp
        self.raining = raining
    }
}

/// The header through a session, from LapCount (races), ExtrapolatedClock and WeatherData; any
/// of them may be empty.
public struct HeaderTimeline: Sendable {
    struct ClockMark: Sendable, Equatable {
        var utc: UTCms
        var remainingMs: Int64
        var running: Bool
    }

    struct Weather: Sendable, Equatable {
        var air: Double?
        var track: Double?
        var raining: Bool
    }

    let lapTimes: [UTCms], laps: [Int]
    let totalTimes: [UTCms], totals: [Int]
    let markTimes: [UTCms], marks: [ClockMark]
    let weatherTimes: [UTCms], weather: [Weather]

    public static func build(lapCount: [StreamLine], clock: [StreamLine], weather: [StreamLine], streamStart: UTCms) -> HeaderTimeline {
        var lapTimes: [UTCms] = [], laps: [Int] = []
        var totalTimes: [UTCms] = [], totals: [Int] = []
        for line in lapCount {
            let t = F1Values.add(streamStart, line.offsetMs)
            if let lap = line.json["CurrentLap"].int { lapTimes.append(t); laps.append(lap) }
            if let total = line.json["TotalLaps"].int { totalTimes.append(t); totals.append(total) }
        }

        // Android's parseClock: a line can leave out any of Utc, Remaining and Extrapolating.
        var marks: [ClockMark] = []
        for line in clock {
            let utc = F1Values.utc(line.json["Utc"].string) ?? F1Values.add(streamStart, line.offsetMs)
            let last = marks.last
            let remaining: Int64
            if let ms = F1Values.durationMs(line.json["Remaining"].string) {
                remaining = Int64(ms)
            } else if let last {
                remaining = last.running ? max(F1Values.sub(last.remainingMs, F1Values.sub(utc, last.utc)), 0) : last.remainingMs
            } else {
                continue
            }
            let running = line.json["Extrapolating"].bool ?? last?.running ?? false
            marks.append(ClockMark(utc: utc, remainingMs: remaining, running: running))
        }
        marks = marks.enumerated().sorted { ($0.element.utc, $0.offset) < ($1.element.utc, $1.offset) }.map(\.element)

        var weatherTimes: [UTCms] = [], readings: [Weather] = []
        var state: JSONValue = .null
        for line in weather {
            state = TopicMerge.merge(state, line.json)
            let reading = Weather(air: Double(state["AirTemp"].string), track: Double(state["TrackTemp"].string),
                                  raining: (Double(state["Rainfall"].string) ?? 0) > 0)
            if readings.last == reading { continue }
            weatherTimes.append(F1Values.add(streamStart, line.offsetMs))
            readings.append(reading)
        }
        return HeaderTimeline(lapTimes: lapTimes, laps: laps, totalTimes: totalTimes, totals: totals,
                              markTimes: marks.map(\.utc), marks: marks, weatherTimes: weatherTimes, weather: readings)
    }

    public func at(_ t: UTCms) -> SessionHeader {
        let w = F1Values.lastIndex(in: weatherTimes, atOrBefore: t).map { weather[$0] }
        return SessionHeader(
            lap: F1Values.lastIndex(in: lapTimes, atOrBefore: t).map { laps[$0] },
            totalLaps: F1Values.lastIndex(in: totalTimes, atOrBefore: t).map { totals[$0] },
            clockRemaining: clockRemainingMs(at: t).map { Int($0 / 1000) },
            airTemp: w?.air,
            trackTemp: w?.track,
            raining: w?.raining ?? false
        )
    }

    /// What the clock read at `t`; nil before the first mark, which is from after `t`.
    func clockRemainingMs(at t: UTCms) -> Int64? {
        guard let i = F1Values.lastIndex(in: markTimes, atOrBefore: t) else { return nil }
        let mark = marks[i]
        let left = mark.running ? F1Values.sub(mark.remainingMs, F1Values.sub(t, mark.utc)) : mark.remainingMs
        return max(left, 0)
    }
}

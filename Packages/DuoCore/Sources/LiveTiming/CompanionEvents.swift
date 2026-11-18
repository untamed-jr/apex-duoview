import Foundation

/// What happened, for the closed phone's cards and the haptics.
public enum CompanionEventKind: Sendable, Equatable {
    case yellow, safetyCar, vsc, red, chequered
    case pit(car: String)
    case radio(car: String)
    case out(car: String)
    /// `car` passes `other` and takes P`position`.
    case passed(car: String, other: String, position: Int)
    case purpleSector(car: String)
}

public struct CompanionEvent: Sendable, Equatable {
    public var t: UTCms
    /// A track event carries the leader's lap, as `RaceEvents` does; a car's event carries that
    /// car's lap (laps done plus one, as the radio labels it). Nil outside races and before
    /// lights out.
    public var lap: Int?
    public var kind: CompanionEventKind

    public init(t: UTCms, lap: Int?, kind: CompanionEventKind) {
        self.t = t
        self.lap = lap
        self.kind = kind
    }
}

/// How the picture reached the time it now shows.
public enum PictureMotion: Sendable {
    /// Normal playback.
    case play
    /// A seek, a scrub or a jump.
    case seek
}

/// Finds the events the picture has just crossed. Everything is read at or before the time it is
/// given: the state at the step's two ends, the flags and the clips up to its end.
public struct EventDetector: Sendable {
    /// Picture time after a seek (or any baseline) in which nothing is reported.
    public static let seekQuietMs: Int64 = 2000
    /// A yellow flag is reported at most once in this much picture time.
    public static let yellowRepeatMs: Int64 = 60_000
    /// A step over this much picture time is a jump, not playback.
    public static let jumpMs: Int64 = 10_000

    private var previous: UTCms?
    private var quietUntil: UTCms = .min
    private var lastYellow: UTCms?

    public init() {}

    /// The events in `(previous t, t]`, oldest first. The first step, a `.seek`, a step back and
    /// a step over `jumpMs` set the baseline and start the quiet period instead: they give
    /// nothing, and neither does the quiet period that follows.
    ///
    /// `favourite` is the driver's racing number (pits, out, purple sector, a pass, radio) and
    /// `listening` holds the numbers whose radio is reported without being the favourite's; the
    /// favourite's radio always is. With neither, only the track's events come back.
    public mutating func step(to t: UTCms, motion: PictureMotion, session: LoadedSession, radio: RadioClips,
                              favourite: String?, listening: Set<String> = []) -> [CompanionEvent] {
        guard motion == .play, let from = previous, t >= from, F1Values.sub(t, from) <= Self.jumpMs else {
            previous = t
            quietUntil = F1Values.add(t, Self.seekQuietMs)
            lastYellow = nil
            return []
        }
        previous = t
        guard t > from else { return [] }

        var found = Self.trackEvents(from: from, to: t, session: session)
        if let favourite { found += Self.carEvents(car: favourite, from: from, to: t, session: session) }
        found += Self.radioEvents(from: from, to: t, session: session, radio: radio,
                                  cars: favourite.map { listening.union([$0]) } ?? listening)
        // Oldest first; at the same moment the order they were found in.
        let ordered = found.enumerated().sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }.map(\.element)

        var out: [CompanionEvent] = []
        for event in ordered {
            // Inside the quiet period after a baseline: dropped, and it counts for nothing.
            if event.t < quietUntil { continue }
            if event.kind == .yellow {
                if let last = lastYellow, F1Values.sub(event.t, last) < Self.yellowRepeatMs { continue }
                lastYellow = event.t
            }
            out.append(event)
        }
        return out
    }

    // MARK: Track

    private enum Category { case clear, yellow, safetyCar, vsc, red }

    private static func category(_ status: TrackStatusKind) -> Category {
        switch status {
        case .clear: return .clear
        case .yellow: return .yellow
        case .safetyCar, .safetyCarInThisLap: return .safetyCar
        case .vsc, .vscEnding: return .vsc
        case .red: return .red
        }
    }

    private static func trackEvents(from: UTCms, to: UTCms, session: LoadedSession) -> [CompanionEvent] {
        let flags = session.flags
        var out: [CompanionEvent] = []
        // Moments the status can change in (from, to]; each is looked at on its own so a
        // yellow that becomes a safety car inside one step gives both.
        var moments = flags.statusTimes.filter { $0 > from && $0 <= to }
        for red in flags.redFlags {
            if red.start > from && red.start <= to { moments.append(red.start) }
            if let end = red.end, end > from, end <= to { moments.append(end) }
        }
        moments = Array(Set(moments)).sorted()
        var before = category(flags.status(at: from))
        for moment in moments {
            let now = category(flags.status(at: moment))
            defer { before = now }
            guard now != before else { continue }
            let kind: CompanionEventKind
            switch now {
            case .yellow where before == .clear: kind = .yellow
            case .safetyCar: kind = .safetyCar
            case .vsc: kind = .vsc
            case .red: kind = .red
            default: continue
            }
            out.append(CompanionEvent(t: moment, lap: leaderLap(at: moment, session: session), kind: kind))
        }

        var status: String?
        for change in session.sessionStatus.changes where change.at <= to {
            defer { status = change.status }
            if change.at > from, change.status == "Finished", status != "Finished", !change.isSnapshot {
                out.append(CompanionEvent(t: change.at, lap: leaderLap(at: change.at, session: session, finished: true),
                                          kind: .chequered))
            }
        }
        return out
    }

    /// Before the first start there is no lap, nor outside a race.
    private static func isBeforeStart(_ t: UTCms, session: LoadedSession) -> Bool {
        let status = session.sessionStatus
        if let started = status.started { return t < started }
        return status.status(at: t) == "Inactive"
    }

    /// The leader's lap in progress (the lap just finished for the chequered flag), as `RaceEvents`.
    private static func leaderLap(at t: UTCms, session: LoadedSession, finished: Bool = false) -> Int? {
        guard session.info.isRace, !isBeforeStart(t, session: session) else { return nil }
        let done = session.timing.at(t).values.compactMap(\.numberOfLaps).max() ?? 0
        if finished { return max(done, 1) }
        let next = done == Int.max ? done : done + 1
        return session.header.at(t).totalLaps.map { min(next, $0) } ?? next
    }

    // MARK: Cars

    /// The car's lap as the radio labels it; nil unless a race lap.
    private static func carLap(_ car: String, at t: UTCms, session: LoadedSession) -> Int? {
        let clip = RadioClip(utc: t, racingNumber: car, path: "")
        if case .lap(let lap) = RadioClips.lapLabel(for: clip, in: session) { return lap }
        return nil
    }

    private static func carEvents(car: String, from: UTCms, to: UTCms, session: LoadedSession) -> [CompanionEvent] {
        var out: [CompanionEvent] = []
        func add(_ t: UTCms, _ kind: CompanionEventKind) {
            out.append(CompanionEvent(t: t, lap: carLap(car, at: t, session: session), kind: kind))
        }

        // Each state the car took in (from, to], against the one before it.
        if let history = session.timing.cars[car] {
            let first = F1Values.lastIndex(in: history.times, atOrBefore: from).map { $0 + 1 } ?? 0
            var before: DriverTimingState? = first > 0 ? history.states[first - 1] : nil
            if first < history.times.count {
                for i in first..<history.times.count where history.times[i] <= to {
                    let state = history.states[i], t = history.times[i]
                    defer { before = state }
                    guard let was = before else { continue }
                    if state.inPit, !was.inPit { add(t, .pit(car: car)) }
                    if (state.retired || state.stopped), !(was.retired || was.stopped) { add(t, .out(car: car)) }
                    for k in state.sectors.indices where state.sectors[k] == .overallBest {
                        if k >= was.sectors.count || was.sectors[k] != .overallBest {
                            add(t, .purpleSector(car: car))
                            break
                        }
                    }
                }
            }
        }

        if session.info.isRace, let pass = pass(car: car, from: from, to: to, session: session) { out.append(pass) }
        return out
    }

    /// A one-place change for `car` between the two ends, with neither car in the pit lane at
    /// either end. Bigger changes are pit cycles or retirements.
    private static func pass(car: String, from: UTCms, to: UTCms, session: LoadedSession) -> CompanionEvent? {
        let was = session.timing.at(from), now = session.timing.at(to)
        guard let a = was[car], let b = now[car], let p0 = a.position, let p1 = b.position,
              (p0 &- p1 == 1 || p1 &- p0 == 1) else { return nil }
        func inPitLane(_ s: DriverTimingState) -> Bool { s.inPit || s.pitOut }
        guard !inPitLane(a), !inPitLane(b) else { return nil }
        let others = was.keys.filter { $0 != car }.sorted(by: Tower.numberOrder)
        guard let other = others.first(where: { number in
            guard let x = was[number], let y = now[number], x.position == p1, y.position == p0 else { return false }
            return !inPitLane(x) && !inPitLane(y)
        }) else { return nil }
        // The moment the car's place changed: the first state at the new place.
        var at = to
        if let history = session.timing.cars[car] {
            let first = F1Values.lastIndex(in: history.times, atOrBefore: from).map { $0 + 1 } ?? 0
            if first < history.times.count,
               let i = (first..<history.times.count).first(where: { history.times[$0] <= to && history.states[$0].position == p1 }) {
                at = history.times[i]
            }
        }
        let gained = p1 < p0
        return CompanionEvent(t: at, lap: carLap(car, at: at, session: session),
                              kind: .passed(car: gained ? car : other, other: gained ? other : car, position: min(p0, p1)))
    }

    // MARK: Radio

    private static func radioEvents(from: UTCms, to: UTCms, session: LoadedSession, radio: RadioClips,
                                    cars: Set<String>) -> [CompanionEvent] {
        guard !cars.isEmpty else { return [] }
        return radio.all.filter { $0.utc > from && $0.utc <= to && cars.contains($0.racingNumber) }.map {
            CompanionEvent(t: $0.utc, lap: carLap($0.racingNumber, at: $0.utc, session: session), kind: .radio(car: $0.racingNumber))
        }
    }
}

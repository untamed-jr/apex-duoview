import Foundation

/// What a car is doing on its lap, as Android's map and tap-a-car read it.
public enum LapState: Sendable, Equatable {
    /// Nothing known yet, or (outside qualifying) running after its out lap.
    case unknown
    case pit
    case outLap
    /// A flying lap (qualifying only).
    case push
    /// The slow lap after a flying lap (qualifying only).
    case coolDown
    case knockedOut
}

public extension TimingSessionInfo {
    /// A race or a sprint (F1's Type "Race").
    var isRace: Bool { Self.isRace(type: type) }

    /// Qualifying or sprint qualifying: the sessions with flying laps and knockouts (Android's
    /// `showsPushLaps`).
    var isQualifying: Bool { type.range(of: "Qualifying", options: .caseInsensitive) != nil }
}

extension TimingSessionInfo {
    /// `isRace` for a session type, wherever one is read (the archive's topics, a live
    /// session's optional ones).
    static func isRace(type: String) -> Bool {
        type.range(of: "Race", options: .caseInsensitive) != nil
    }
}

/// Each car's lap state through a session, derived from its timing history by Android's rules
/// (LiveTiming.parseStates):
/// - going into the pits makes it `.pit`;
/// - leaving them (PitOut, or InPit going false while in the pits) makes it `.outLap`;
/// - crossing the line turns an out lap or a cool-down lap into `.push`, and a push lap into
///   `.coolDown`;
/// - being knocked out makes it `.knockedOut`.
///
/// Push and cool-down mean something only in qualifying, where Android alone shows them. In other
/// sessions the line ends an out lap and the car is `.unknown` from then on, so `.push` and
/// `.coolDown` never appear there.
///
/// A crossing is `TimingTimeline`'s (`lineCrossedAt` changing), not Android's own count: the
/// timeline doesn't count the lap count F1 raises as a qualifying run leaves the pits, which on
/// Android's rules made each out lap a push lap and every lap after it the wrong way round.
///
/// Built once (one pass over the timing history); `at` is a binary search per car, cheap enough
/// for every frame. Each state depends only on the history at or before its own time.
///
/// It is a snapshot of the timeline it was built from: a live caller, whose timeline grows,
/// rebuilds it when the timeline changes (not on every frame).
public struct LapStates: Sendable {
    struct History: Sendable {
        var times: [UTCms] = []
        var states: [LapState] = []
    }

    let cars: [String: History]

    public init(timing: TimingTimeline, qualifying: Bool) {
        var cars: [String: History] = [:]
        for (number, timeline) in timing.cars {
            var history = History()
            var current = LapState.unknown
            var previous: DriverTimingState?
            for (i, s) in timeline.states.enumerated() {
                var state = current
                if s.inPit, previous?.inPit != true { state = .pit }
                let pitOut = s.pitOut && previous?.pitOut != true
                let leftPits = !s.inPit && previous?.inPit == true && state == .pit
                if pitOut || leftPits { state = .outLap }
                if s.lineCrossedAt != nil, s.lineCrossedAt != previous?.lineCrossedAt {
                    switch state {
                    case .outLap, .coolDown: state = qualifying ? .push : .unknown
                    case .push: state = qualifying ? .coolDown : .unknown
                    default: break
                    }
                }
                if s.knockedOut, previous?.knockedOut != true { state = .knockedOut }
                if state != current || history.times.isEmpty {
                    history.times.append(timeline.times[i])
                    history.states.append(state)
                    current = state
                }
                previous = s
            }
            cars[number] = history
        }
        self.cars = cars
    }

    /// The session's lap states, push laps only when it is a qualifying session.
    public init(session: LoadedSession) {
        self.init(timing: session.timing, qualifying: session.info.isQualifying)
    }

    /// Each car's state at `t`: the latest at or before it. Cars with no timing yet are absent
    /// (read them as `.unknown`).
    public func at(_ t: UTCms) -> [String: LapState] {
        var out: [String: LapState] = [:]
        for (number, history) in cars {
            if let i = F1Values.lastIndex(in: history.times, atOrBefore: t) { out[number] = history.states[i] }
        }
        return out
    }

    /// One car's state at `t`; `.unknown` before its first timing.
    public func state(of number: String, at t: UTCms) -> LapState {
        guard let history = cars[number], let i = F1Values.lastIndex(in: history.times, atOrBefore: t) else { return .unknown }
        return history.states[i]
    }

    /// Each car's state at `t`, building the states first: for a one-off question (a tap). Keep a
    /// `LapStates` for anything asked often.
    public static func at(_ t: UTCms, timing: TimingTimeline, qualifying: Bool) -> [String: LapState] {
        LapStates(timing: timing, qualifying: qualifying).at(t)
    }
}

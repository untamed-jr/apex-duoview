import Foundation

/// Race Engineer's lines for the car on the top screen:
/// ```
/// P4  ▲ NOR +1.2s closing  ▼ RUS -0.8s ↗
/// Medium · 18 laps   Pit now → P7 behind ALO
/// L41 1:32.456 ■■■  L40 1:32.912 ■■□  L39 …
/// ```
public struct RaceLinesModel: Sendable, Equatable {
    public var position: Int?
    /// The car ahead: its code, how far ahead ("+1.2s", or F1's own words when it isn't a time,
    /// such as "1L"), and whether the gap is shrinking over the last 3 laps (nil when there is
    /// no trend: too few laps, or the gap unchanged or not a time).
    public var ahead: (tla: String, gap: String, closing: Bool?)?
    /// The car behind: its code, how far behind ("-0.8s"), and whether it is closing in.
    public var behind: (tla: String, gap: String, closing: Bool?)?
    /// The compound ("Medium", F1's word in title case) and laps on the set.
    public var tyre: (compound: String, laps: Int)?
    /// "Pit now → P7 behind ALO", from the pit circle (`Rejoin.consoleText`).
    public var pitNow: String?
    /// The last 5 laps finished, newest first: the lap's number, its time ("1:32.456", "" when
    /// F1 sent none) and its sectors.
    public var lastLaps: [(lap: Int, time: String, sectors: [SectorPace])]
    /// The racing numbers of the cars ahead and behind, for tapping to switch the onboard.
    public var aheadNumber: String?
    public var behindNumber: String?

    public init(position: Int?, ahead: (tla: String, gap: String, closing: Bool?)?,
                behind: (tla: String, gap: String, closing: Bool?)?, tyre: (compound: String, laps: Int)?,
                pitNow: String?, lastLaps: [(lap: Int, time: String, sectors: [SectorPace])],
                aheadNumber: String? = nil, behindNumber: String? = nil) {
        self.position = position
        self.ahead = ahead
        self.behind = behind
        self.tyre = tyre
        self.pitNow = pitNow
        self.lastLaps = lastLaps
        self.aheadNumber = aheadNumber
        self.behindNumber = behindNumber
    }

    public static func == (a: RaceLinesModel, b: RaceLinesModel) -> Bool {
        func same(_ x: (tla: String, gap: String, closing: Bool?)?, _ y: (tla: String, gap: String, closing: Bool?)?) -> Bool {
            x?.tla == y?.tla && x?.gap == y?.gap && x?.closing == y?.closing && (x == nil) == (y == nil)
        }
        return a.position == b.position && same(a.ahead, b.ahead) && same(a.behind, b.behind)
            && a.tyre?.compound == b.tyre?.compound && a.tyre?.laps == b.tyre?.laps && (a.tyre == nil) == (b.tyre == nil)
            && a.pitNow == b.pitNow && a.aheadNumber == b.aheadNumber && a.behindNumber == b.behindNumber
            && a.lastLaps.count == b.lastLaps.count
            && zip(a.lastLaps, b.lastLaps).allSatisfy { $0.lap == $1.lap && $0.time == $1.time && $0.sectors == $1.sectors }
    }
}

public enum RaceLines {
    /// How many laps back the gap trend looks.
    public static let trendLaps = 3
    /// How many finished laps the console lists.
    public static let lapsShown = 5

    /// `car`'s lines at `t` (picture time), from timing at or before `t`; nil before the car has
    /// any timing. Outside races (where the gaps are lap-time differences) there are no cars
    /// ahead or behind and no pit line. `storedPitLossMs` is this circuit's stored pit loss.
    ///
    /// The trend compares the gap now with the gap 3 laps ago: at the same point of the lap
    /// three of `car`'s laps earlier (`t` less the time its last 3 laps took), each gap from the
    /// two cars' gaps to the leader then.
    public static func at(_ t: UTCms, car: String, session: LoadedSession, storedPitLossMs: Int? = nil) -> RaceLinesModel? {
        let states = session.timing.at(t)
        guard let me = states[car] else { return nil }
        let race = session.info.isRace

        var ahead: (tla: String, gap: String, closing: Bool?)?
        var behind: (tla: String, gap: String, closing: Bool?)?
        var aheadNumber: String?, behindNumber: String?
        if race, let p = me.position {
            let gaps = PitCircle.gapsToLeader(states, at: t, timing: session.timing)
            let then = trendTime(car: car, at: t, session: session).map { PitCircle.gapsToLeader(session.timing.at($0), at: $0, timing: session.timing) }
            func trend(front: String, back: String) -> Bool? {
                guard let now = difference(gaps, front, back), let before = then.flatMap({ difference($0, front, back) }),
                      now != before else { return nil }
                return now < before
            }
            if let (number, _) = states.first(where: { $0.value.position == p - 1 }) {
                aheadNumber = number
                ahead = (PitCircle.tla(number, session), gapText(me.interval, sign: "+"), trend(front: number, back: car))
            }
            if let (number, s) = states.first(where: { $0.value.position == p + 1 && !$0.value.retired && !$0.value.stopped }) {
                behindNumber = number
                behind = (PitCircle.tla(number, session), gapText(s.interval, sign: "-"), trend(front: car, back: number))
            }
        }

        let pitNow = race ? PitCircle.rejoin(car: car, at: t, session: session,
                                             pitLossMs: PitCircle.pitLossMs(at: t, session: session, storedMs: storedPitLossMs))?
            .consoleText(session: session) : nil
        let laps = session.timing.completedLaps(of: car, upTo: t).suffix(lapsShown).reversed().map {
            (lap: $0.lap, time: $0.lapMs.map(Tower.lapText) ?? "", sectors: $0.sectors)
        }
        return RaceLinesModel(position: me.position, ahead: ahead, behind: behind,
                              tyre: session.stints.at(t)[car]?.last.flatMap(tyre), pitNow: pitNow, lastLaps: laps,
                              aheadNumber: aheadNumber, behindNumber: behindNumber)
    }

    /// The same point of the lap `trendLaps` laps earlier: `t` less the time `car`'s last 3 laps
    /// took. Nil before it has finished that many laps since its first crossing.
    static func trendTime(car: String, at t: UTCms, session: LoadedSession) -> UTCms? {
        let crossings = PitCircle.crossings(of: car, upTo: t, timing: session.timing)
        guard crossings.count > trendLaps, let last = crossings.last else { return nil }
        return F1Values.sub(t, F1Values.sub(last, crossings[crossings.count - 1 - trendLaps]))
    }

    /// How far `back` is behind `front`, in ms.
    static func difference(_ gaps: [String: Int], _ front: String, _ back: String) -> Int? {
        guard let f = gaps[front], let b = gaps[back] else { return nil }
        return b - f
    }

    /// An interval as the console writes it: "+1.2s" ahead, "-0.8s" behind (to the nearest
    /// tenth); F1's own text when it isn't a time ("1L"), "" when there is none.
    static func gapText(_ interval: String, sign: String) -> String {
        guard let ms = PitCircle.gapMs(interval) else { return interval.trimmingCharacters(in: .whitespaces) }
        let tenths = (ms + 50) / 100
        return "\(sign)\(tenths / 10).\(tenths % 10)s"
    }

    /// "MEDIUM" as "Medium", and its laps; nil for a compound F1 doesn't know yet.
    static func tyre(_ stint: Stint) -> (compound: String, laps: Int)? {
        let word = stint.compound.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !word.uppercased().contains("UNKNOWN") else { return nil }
        return (word.prefix(1).uppercased() + word.dropFirst().lowercased(), stint.totalLaps)
    }
}

import Foundation

/// One car in the timing tower.
public struct TowerRow: Sendable, Equatable {
    public var number: String
    /// The three-letter code; the number for a car DriverList doesn't name.
    public var tla: String
    /// "RRGGBB", or "" when unknown.
    public var teamColour: String
    public var position: Int?
    /// "1:32.456", "PIT" in the pit lane, or "" before a lap.
    public var lastLap: String
    /// The last lap's colour; `.empty` for "PIT" and "".
    public var lastLapPace: SectorPace
    /// To the leader in a race, to the fastest lap otherwise (see `Tower.gapHeader`).
    public var gap: String
    /// To the car ahead.
    public var interval: String
    /// The compound's letter (S, M, H, I, W) and laps on the set.
    public var tyre: (compound: Character, laps: Int)?
    /// Knocked out, retired or stopped.
    public var dimmed: Bool
    /// In qualifying's Q1 or Q2, among the cars that would go out now.
    public var inKnockoutZone: Bool
    /// The favourite driver or a rival within 1.0 s of them (`Battle`).
    public var battle: Bool

    public init(number: String, tla: String, teamColour: String, position: Int?, lastLap: String, lastLapPace: SectorPace,
                gap: String, interval: String, tyre: (compound: Character, laps: Int)?, dimmed: Bool,
                inKnockoutZone: Bool, battle: Bool) {
        self.number = number
        self.tla = tla
        self.teamColour = teamColour
        self.position = position
        self.lastLap = lastLap
        self.lastLapPace = lastLapPace
        self.gap = gap
        self.interval = interval
        self.tyre = tyre
        self.dimmed = dimmed
        self.inKnockoutZone = inKnockoutZone
        self.battle = battle
    }

    public static func == (a: TowerRow, b: TowerRow) -> Bool {
        a.number == b.number && a.tla == b.tla && a.teamColour == b.teamColour && a.position == b.position
            && a.lastLap == b.lastLap && a.lastLapPace == b.lastLapPace && a.gap == b.gap && a.interval == b.interval
            && a.tyre?.compound == b.tyre?.compound && a.tyre?.laps == b.tyre?.laps && a.dimmed == b.dimmed
            && a.inKnockoutZone == b.inKnockoutZone && a.battle == b.battle
    }
}

/// The timing tower: every car with timing, in running order, as Android's laptop tower shows it.
public enum Tower {
    /// The rows at `t` (picture time), from timing, tyres and the qualifying part at or before
    /// `t` only. Sorted by position, cars without one last, by number. `favourite` is the
    /// favourite driver's racing number (`carNumber(forDriver:in:)` finds it from "My driver");
    /// without one there is no battle highlight.
    public static func rows(at t: UTCms, session: LoadedSession, favourite: String?) -> [TowerRow] {
        let timing = session.timing.at(t)
        let stints = session.stints.at(t)
        let zone = knockoutZone(timing, part: session.info.isQualifying ? session.timing.sessionPart(at: t) : nil)
        var battling = Set<String>()
        if let favourite, session.info.isRace {
            let rivals = Battle.rivals(of: favourite, at: t, timing: session.timing)
            if !rivals.isEmpty { battling = Set(rivals + [favourite]) }
        }
        let rows = timing.map { number, s -> TowerRow in
            let driver = session.drivers[number]
            let lap = s.lastLapMs.map(lapText)
            let tyre = stints[number]?.last.flatMap { stint in stint.compound.first.map { (compound: $0, laps: stint.totalLaps) } }
            return TowerRow(
                number: number,
                tla: driver?.tla ?? number,
                teamColour: driver?.teamColour ?? "",
                position: s.position,
                lastLap: s.inPit ? "PIT" : lap ?? "",
                lastLapPace: s.inPit || lap == nil ? .empty : s.lastLapPace,
                gap: s.gapToLeader,
                interval: s.interval,
                tyre: tyre,
                dimmed: s.knockedOut || s.retired || s.stopped,
                inKnockoutZone: zone.contains(number),
                battle: battling.contains(number)
            )
        }
        return rows.sorted { a, b in
            switch (a.position, b.position) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return numberOrder(a.number, b.number)
            }
        }
    }

    /// The gap column's title: "Leader" in a race, "Fastest" otherwise (Android).
    public static func gapHeader(session: LoadedSession) -> String {
        session.info.isRace ? "Leader" : "Fastest"
    }

    /// The racing number of a driver named by last name ("My driver"), ignoring case and accents.
    public static func carNumber(forDriver lastName: String, in session: LoadedSession) -> String? {
        let matches = session.drivers.values.filter {
            !$0.lastName.isEmpty
                && $0.lastName.compare(lastName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return matches.map(\.number).sorted(by: numberOrder).first
    }

    /// How many of the cars still in go out at the end of qualifying part `part`. Q3 always has
    /// ten cars and Q1 and Q2 drop the same number: five each from 20 cars, six each from 22 (as
    /// F1's 2026 NoEntries [22, 16, 10]). Zero in Q3, or outside parts 1 and 2.
    public static func knockoutZoneSize(carsStillIn: Int, part: Int) -> Int {
        switch part {
        case 1: return max((carsStillIn - 10) / 2, 0)
        case 2: return max(carsStillIn - 10, 0)
        default: return 0
        }
    }

    /// The cars still in (not knocked out, with a position) in the bottom places that go out.
    static func knockoutZone(_ timing: [String: DriverTimingState], part: Int?) -> Set<String> {
        guard let part else { return [] }
        let still = timing.filter { !$0.value.knockedOut && $0.value.position != nil }
            .sorted { ($0.value.position ?? 0, $0.key) < ($1.value.position ?? 0, $1.key) }
        let size = knockoutZoneSize(carsStillIn: still.count, part: part)
        return Set(still.suffix(size).map(\.key))
    }

    /// A lap time as F1 writes it: "1:29.518".
    public static func lapText(_ ms: Int) -> String {
        let ms = max(ms, 0)
        let seconds = ms / 1000 % 60
        let millis = ms % 1000
        return "\(ms / 60_000):\(seconds < 10 ? "0" : "")\(seconds).\(String(repeating: "0", count: millis < 10 ? 2 : millis < 100 ? 1 : 0))\(millis)"
    }

    /// Numbers in numeric order ("3" before "10"), anything else after, by text.
    static func numberOrder(_ a: String, _ b: String) -> Bool {
        (Int(a) ?? .max, a) < (Int(b) ?? .max, b)
    }
}

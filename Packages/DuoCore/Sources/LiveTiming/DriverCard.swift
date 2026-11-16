import Foundation

/// The broadcast-style card over an onboard (Android's DriverCard): position, number and surname
/// in the team colour, then one of "PIT" (`inPit`), the lap just done (`flash`, for 6 s after the
/// line) or the running lap clock (`lapClock`); below, the sector bars and the gap.
public struct DriverCardModel: Sendable, Equatable {
    /// How long a finished lap's time shows after the line.
    public static let flashMs: Int64 = 6_000

    public var position: Int?
    public var number: String
    /// The last name in capitals; the three-letter code, then the number, when DriverList has none.
    public var surname: String
    /// "RRGGBB", or "" when unknown.
    public var teamColour: String
    /// Time into the lap, "m:ss.t". Nil in the pits, while `flash` shows, before the car's first
    /// crossing, and once it is retired or stopped.
    public var lapClock: String?
    public var inPit: Bool
    /// The lap just finished ("1:29.518") and its colour, for 6 s after the line; nil in the pits.
    public var flash: (text: String, pace: SectorPace)?
    /// S1…S3 of the lap in progress: grey (`.empty`) until each is set.
    public var sectors: [SectorPace]
    /// The interval to the car ahead in a race; the gap to the fastest lap otherwise.
    public var gap: String

    public init(position: Int?, number: String, surname: String, teamColour: String, lapClock: String?, inPit: Bool,
                flash: (text: String, pace: SectorPace)?, sectors: [SectorPace], gap: String) {
        self.position = position
        self.number = number
        self.surname = surname
        self.teamColour = teamColour
        self.lapClock = lapClock
        self.inPit = inPit
        self.flash = flash
        self.sectors = sectors
        self.gap = gap
    }

    public static func == (a: DriverCardModel, b: DriverCardModel) -> Bool {
        a.position == b.position && a.number == b.number && a.surname == b.surname && a.teamColour == b.teamColour
            && a.lapClock == b.lapClock && a.inPit == b.inPit && a.flash?.text == b.flash?.text
            && a.flash?.pace == b.flash?.pace && a.sectors == b.sectors && a.gap == b.gap
    }

    /// Car `number`'s card at `t` (picture time), from its timing at or before `t`; nil before
    /// the car has any timing.
    public static func at(_ t: UTCms, number: String, session: LoadedSession) -> DriverCardModel? {
        guard let s = session.timing.state(of: number, at: t) else { return nil }
        let driver = session.drivers[number]
        let name = driver?.lastName.trimmingCharacters(in: .whitespaces) ?? ""
        let elapsed = s.lineCrossedAt.map { F1Values.sub(t, $0) }
        let out = s.inPit || s.retired || s.stopped
        var flash: (text: String, pace: SectorPace)?
        if !s.inPit, let elapsed, (0..<flashMs).contains(elapsed), let lap = s.lastLapMs {
            flash = (Tower.lapText(lap), s.lastLapPace)
        }
        return DriverCardModel(
            position: s.position,
            number: number,
            surname: (name.isEmpty ? driver?.tla ?? number : name).uppercased(),
            teamColour: driver?.teamColour ?? "",
            lapClock: out || flash != nil ? nil : elapsed.map(clockText),
            inPit: s.inPit,
            flash: flash,
            sectors: s.sectors,
            gap: session.info.isRace ? s.interval : s.gapToLeader
        )
    }

    /// A running lap clock, "m:ss.t" (tenths truncated).
    static func clockText(_ ms: Int64) -> String {
        let tenths = max(ms, 0) / 100
        let seconds = tenths / 10 % 60
        return "\(tenths / 600):\(seconds < 10 ? "0" : "")\(seconds).\(tenths % 10)"
    }
}

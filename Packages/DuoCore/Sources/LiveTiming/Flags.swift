import Foundation
import F1TV

/// What the whole track is under, from TrackStatus (1 clear, 2 yellow, 4 safety car, 5 red,
/// 6 VSC, 7 VSC ending) and race control.
public enum TrackStatusKind: Sendable, Equatable {
    case clear, yellow, safetyCar, safetyCarInThisLap, vsc, vscEnding, red

    /// The words the map shows; none for clear or a local yellow (the sectors show that).
    public var label: String? {
        switch self {
        case .clear, .yellow: return nil
        case .safetyCar: return "Safety car"
        case .safetyCarInThisLap: return "Safety car in this lap"
        case .vsc: return "Virtual safety car"
        case .vscEnding: return "VSC ending"
        case .red: return "Red flag"
        }
    }
}

/// The flags at one moment.
public struct FlagState: Sendable, Equatable {
    public var status: TrackStatusKind
    /// Marshal sector → 1 (yellow) or 2 (double yellow).
    public var yellowSectors: [Int: Int]
    /// "Red flag · Q3 resumes in 4:12", "Safety car", or nil.
    public var caption: String?
    /// The next announced restart, while one is coming.
    public var resumesAt: UTCms?

    public init(status: TrackStatusKind, yellowSectors: [Int: Int] = [:], caption: String? = nil, resumesAt: UTCms? = nil) {
        self.status = status
        self.yellowSectors = yellowSectors
        self.caption = caption
        self.resumesAt = resumesAt
    }
}

/// A safety car, VSC or red flag period, for the timeline and the Scrub Deck.
public struct FlagSpan: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case safetyCar, vsc, red }

    public var kind: Kind
    public var start: UTCms
    /// Nil while it's still out at the end of the data.
    public var end: UTCms?

    public init(kind: Kind, start: UTCms, end: UTCms?) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

/// Race control's flags through a session, ported from Android's TrackFlags: sector yellows
/// from race control's messages, the track's condition from TrackStatus, "SAFETY CAR IN THIS
/// LAP", red flags from race control until the green light (TrackStatus doesn't always mark
/// them), and announced restart times.
public struct TrackFlags: Sendable {
    struct SectorFlag: Sendable { var utc: UTCms; var sector: Int; var level: Int }
    struct Resumption: Sendable { var announced: UTCms; var at: UTCms; var what: String }
    struct RedFlag: Sendable { var start: UTCms; var end: UTCms? }

    let sectorFlags: [SectorFlag]
    let statusTimes: [UTCms]
    let statusCodes: [Int]
    let safetyCarIn: [UTCms]
    let resumptions: [Resumption]
    let redFlags: [RedFlag]
    public private(set) var spans: [FlagSpan] = []

    /// An announcement is shown for an hour at most, so a stale one never lingers.
    static let announcementLifeMs: Int64 = 3_600_000

    init(sectorFlags: [SectorFlag], status: [(UTCms, Int)], safetyCarIn: [UTCms], resumptions: [Resumption], redFlags: [RedFlag]) {
        self.sectorFlags = sectorFlags
        statusTimes = status.map(\.0)
        statusCodes = status.map(\.1)
        self.safetyCarIn = safetyCarIn
        self.resumptions = resumptions
        self.redFlags = redFlags
        spans = makeSpans()
    }

    /// TrackStatus lines are timed at `streamStart + offset`; race control's by their own Utc.
    /// Announced restart times are the track's local time, `gmtOffsetSeconds` east of GMT.
    public static func build(trackStatus: [StreamLine], raceControl: [StreamLine], streamStart: UTCms,
                             gmtOffsetSeconds: Int) -> TrackFlags {
        let status = trackStatus.compactMap { line -> (UTCms, Int)? in
            guard let code = line.json["Status"].int else { return nil }
            return (F1Values.add(streamStart, line.offsetMs), code)
        }
        let messages = controlMessages(raceControl, streamStart: streamStart)
        return TrackFlags(
            sectorFlags: sectorFlags(messages),
            status: status,
            safetyCarIn: messages.filter {
                $0.message["Category"].string == "SafetyCar" && $0.message["Message"].string.contains("IN THIS LAP")
            }.map(\.utc),
            resumptions: messages.compactMap { resumption($0.message["Message"].string, said: $0.utc, offset: gmtOffsetSeconds) },
            redFlags: redFlags(messages)
        )
    }

    public func at(_ t: UTCms) -> FlagState {
        let status = status(at: t)
        var yellow: [Int: Int] = [:]
        for f in sectorFlags {
            if f.utc > t { break }
            if f.sector == 0 { yellow.removeAll() } else if f.level == 0 { yellow[f.sector] = nil } else { yellow[f.sector] = f.level }
        }
        let resumption = resumptions.last {
            $0.announced <= t && t < $0.at && F1Values.sub(t, $0.announced) < Self.announcementLifeMs
        }
        let parts = [status.label, resumption.map { "\($0.what) in \(Self.countdown(F1Values.sub($0.at, t)))" }].compactMap { $0 }
        return FlagState(status: status, yellowSectors: yellow,
                         caption: parts.isEmpty ? nil : parts.joined(separator: " · "), resumesAt: resumption?.at)
    }

    func status(at t: UTCms) -> TrackStatusKind {
        if redFlags.contains(where: { $0.start <= t && $0.end.map { t < $0 } ?? true }) { return .red }
        var code = 1
        var since = UTCms.min
        for (i, time) in statusTimes.enumerated() {
            if time > t { break }
            if statusCodes[i] != code { since = time }
            code = statusCodes[i]
        }
        switch code {
        case 2: return .yellow
        case 4: return safetyCarIn.contains { since <= $0 && $0 <= t } ? .safetyCarInThisLap : .safetyCar
        case 5: return .red
        case 6: return .vsc
        case 7: return .vscEnding
        default: return .clear
        }
    }

    private func makeSpans() -> [FlagSpan] {
        func kind(_ s: TrackStatusKind) -> FlagSpan.Kind? {
            switch s {
            case .safetyCar, .safetyCarInThisLap: return .safetyCar
            case .vsc, .vscEnding: return .vsc
            case .red: return .red
            case .clear, .yellow: return nil
            }
        }
        let breaks = Set(statusTimes + redFlags.map(\.start) + redFlags.compactMap(\.end)).sorted()
        var out: [FlagSpan] = []
        var current: FlagSpan.Kind?
        for t in breaks {
            let k = kind(status(at: t))
            guard k != current else { continue }
            if current != nil { out[out.count - 1].end = t }
            if let k { out.append(FlagSpan(kind: k, start: t, end: nil)) }
            current = k
        }
        return out
    }

    /// "4:12", or "1:04:12" from an hour; rounded up, so it reaches 0:00 as the time arrives.
    static func countdown(_ ms: Int64) -> String {
        let s = F1Values.add(ms, 999) / 1000
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Race control

    struct Message { var message: JSONValue; var utc: UTCms }

    /// Each line adds Messages, as a list or as index-keyed entries. A message without a
    /// readable Utc (given with or without its "Z") takes its line's time.
    static func controlMessages(_ lines: [StreamLine], streamStart: UTCms) -> [Message] {
        lines.flatMap { line in
            F1Values.ordered(line.json["Messages"]).map { m in
                Message(message: m, utc: F1Values.utc(m["Utc"].string) ?? F1Values.add(streamStart, line.offsetMs))
            }
        }
    }

    /// Yellows and clears in single marshal sectors, and "TRACK CLEAR" (sector 0), which
    /// clears them all. Oldest first; equal times keep the order sent.
    static func sectorFlags(_ messages: [Message]) -> [SectorFlag] {
        let flags = messages.compactMap { m -> SectorFlag? in
            let scope = m.message["Scope"].string
            let sector = m.message["Sector"].int ?? 0
            switch m.message["Flag"].string {
            case "YELLOW": return scope == "Sector" && sector > 0 ? SectorFlag(utc: m.utc, sector: sector, level: 1) : nil
            case "DOUBLE YELLOW": return scope == "Sector" && sector > 0 ? SectorFlag(utc: m.utc, sector: sector, level: 2) : nil
            case "CLEAR", "GREEN":
                if scope == "Sector" { return sector > 0 ? SectorFlag(utc: m.utc, sector: sector, level: 0) : nil }
                return scope == "Track" ? SectorFlag(utc: m.utc, sector: 0, level: 0) : nil
            default: return nil
            }
        }
        return flags.enumerated().sorted { ($0.element.utc, $0.offset) < ($1.element.utc, $1.offset) }.map(\.element)
    }

    /// Each red flag until the next green light, chequered flag or session (re)start; not
    /// "TRACK CLEAR", which race control sends while the session is still stopped (Spa 2026, Q3).
    static func redFlags(_ messages: [Message]) -> [RedFlag] {
        var out: [RedFlag] = []
        var since: UTCms?
        for m in messages {
            let flag = m.message["Flag"].string
            let green = flag == "GREEN" || flag == "CHEQUERED"
                || (m.message["Category"].string == "SessionStatus" && m.message["Message"].string.contains("STARTED"))
            if flag == "RED" {
                if since == nil { since = m.utc }
            } else if green, let start = since {
                out.append(RedFlag(start: start, end: m.utc))
                since = nil
            }
        }
        if let since { out.append(RedFlag(start: since, end: nil)) }
        return out
    }

    /// "Q3 WILL RESUME AT 17:04", "RACE WILL RESUME AT 15:42", "SQ2 WILL START AT 17:08",
    /// "ESTIMATED TIME OF SQ1 RESUMPTION - 16:59": the next time it's that clock time at the
    /// track after it was said (or up to an hour before).
    static func resumption(_ text: String, said: UTCms, offset: Int) -> Resumption? {
        let upper = text.uppercased()
        let groups: [String]
        if let g = match(#"^(?:THE )?([A-Z0-9 ]+?) WILL (RESUME|RESTART|START) AT (\d{1,2}):(\d{2})"#, upper) {
            groups = g
        } else if let g = match(#"ESTIMATED TIME OF (?:THE )?([A-Z0-9 ]+?) (RESUMPTION|RESTART|START) ?-? ?(\d{1,2}):(\d{2})"#, upper) {
            groups = [g[0], g[1] == "RESUMPTION" ? "RESUME" : g[1], g[2], g[3]]
        } else {
            return nil
        }
        guard let h = Int(groups[2]), let m = Int(groups[3]), h < 24, m < 60 else { return nil }
        let day: Int64 = 86_400_000
        guard (-F1Values.maxOffsetSeconds...F1Values.maxOffsetSeconds).contains(offset) else { return nil }
        let zone = Int64(offset) * 1000
        let localSaid = F1Values.add(said, zone)
        let dayStart = F1Values.sub(localSaid, ((localSaid % day) + day) % day)
        var at = F1Values.add(dayStart, Int64(h) * 3_600_000 + Int64(m) * 60_000)
        if at < F1Values.sub(localSaid, 3_600_000) { at = F1Values.add(at, day) }
        var who = groups[0]
        if who.hasPrefix("THE ") { who.removeFirst(4) }
        who = who.trimmingCharacters(in: .whitespaces)
        let isPart = who.range(of: #"^S?Q\d$"#, options: .regularExpression) != nil
        let name = isPart ? who : who.prefix(1).uppercased() + who.dropFirst().lowercased()
        let action = groups[1] == "RESUME" ? "resumes" : groups[1] == "RESTART" ? "restarts" : "starts"
        return Resumption(announced: said, at: F1Values.sub(at, zone), what: "\(name) \(action)")
    }

    /// The capture groups of the first match of `pattern` in `text`.
    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

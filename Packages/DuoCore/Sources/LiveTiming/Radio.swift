import Foundation
import F1TV

/// The wall-clock time in a radio clip's file name ("ANT_12_20261108_141229.mp3" is 2026-11-08
/// 14:12:29). It is the track's local time, not UTC: São Paulo 2026's names are three hours
/// behind their `Utc` (GMT−3), so turning it into a moment needs the session's GMT offset.
public struct RadioFileTime: Sendable, Hashable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// The moment, for a track `gmtOffsetSeconds` east of GMT (`TimingSessionInfo.gmtOffsetSeconds`).
    public func utc(gmtOffsetSeconds: Int) -> UTCms? {
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        let text = "\(year)-\(two(month))-\(two(day))T\(two(hour)):\(two(minute)):\(two(second))Z"
        guard (1000...9999).contains(year), let local = SignalR.utc(text) else { return nil }
        let (ms, overflow) = Int64(gmtOffsetSeconds).multipliedReportingOverflow(by: 1000)
        return F1Values.sub(local, overflow ? (gmtOffsetSeconds > 0 ? .max : .min) : ms)
    }

    /// "…_YYYYMMDD_HHMMSS.ext" at the end of a path; nil for anything else.
    static func parse(path: String) -> RadioFileTime? {
        let name = path.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        let stem = name.split(separator: ".", omittingEmptySubsequences: false).first ?? ""
        let parts = stem.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let date = parts[parts.count - 2], time = parts[parts.count - 1]
        guard date.utf8.count == 8, time.utf8.count == 6,
              let y = F1Values.smallInt(date.prefix(4), maxDigits: 4),
              let mo = F1Values.smallInt(date.dropFirst(4).prefix(2), maxDigits: 2),
              let d = F1Values.smallInt(date.suffix(2), maxDigits: 2),
              let h = F1Values.smallInt(time.prefix(2), maxDigits: 2),
              let mi = F1Values.smallInt(time.dropFirst(2).prefix(2), maxDigits: 2),
              let s = F1Values.smallInt(time.suffix(2), maxDigits: 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 60
        else { return nil }
        return RadioFileTime(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
    }
}

/// One team radio recording from F1's TeamRadio topic.
public struct RadioClip: Sendable, Hashable {
    /// When F1 published the clip (its `Utc`): the clip exists from this moment of picture time.
    /// Later than when the words were said (São Paulo 2026: 6 to 50 s after the file name's time).
    public let utc: UTCms
    /// The car's number, as DriverList keys it ("1", "12").
    public let racingNumber: String
    /// Under the session's folder: "TeamRadio/ANT_12_20261108_141229.mp3".
    public let path: String
    /// The time in the file name, when it has one; the track's local time (`RadioFileTime`).
    public let fileTime: RadioFileTime?

    public init(utc: UTCms, racingNumber: String, path: String) {
        self.utc = utc
        self.racingNumber = racingNumber
        self.path = path
        self.fileTime = RadioFileTime.parse(path: path)
    }

    /// The file name's time as a moment, for a track `gmtOffsetSeconds` east of GMT.
    public func fileUtc(gmtOffsetSeconds: Int) -> UTCms? {
        fileTime?.utc(gmtOffsetSeconds: gmtOffsetSeconds)
    }
}

/// A session's team radio, from TeamRadio lines, as Android's `parseRadio`/`addRadio`: each line
/// adds `Captures`, a list in the opening state and objects keyed "1", "2"… after it. A capture
/// needs a readable `Utc` and a `Path`; anything else is skipped. A path already seen is dropped
/// (the first one stays). Oldest `Utc` first; clips with the same `Utc` keep the order they came.
///
/// Whole session: what is shown must be cut at picture time (`visible(at:)`).
public struct RadioClips: Sendable, Equatable {
    public private(set) var all: [RadioClip] = []
    private var paths: Set<String> = []

    public init() {}

    public init(lines: [StreamLine]) {
        for line in lines { add(line) }
    }

    /// Adds a line's captures (the live feed adds lines as they come).
    public mutating func add(_ line: StreamLine) {
        for capture in Self.captures(line.json["Captures"]) {
            let path = capture["Path"].string
            let stamp = capture["Utc"].string
            guard !path.isEmpty, !paths.contains(path), !stamp.isEmpty, let utc = F1Values.utc(stamp) else { continue }
            paths.insert(path)
            let clip = RadioClip(utc: utc, racingNumber: capture["RacingNumber"].string, path: path)
            // After every clip at or before its time: sorted, and arrival order on ties.
            var lo = all.startIndex, hi = all.endIndex
            while lo < hi {
                let mid = (lo + hi) / 2
                if all[mid].utc <= utc { lo = mid + 1 } else { hi = mid }
            }
            all.insert(clip, at: lo)
        }
    }

    /// The clips that exist at picture time `t`: published at or before it (`utc ≤ t`), as
    /// Android's `clip.utc <= now`. `t` nil is "Show the whole race": every clip. With `driver`
    /// (a racing number), only that car's.
    public func visible(at t: UTCms?, driver: String? = nil) -> [RadioClip] {
        let shown = t.map { t in all.prefix { $0.utc <= t } } ?? all[...]
        guard let driver else { return Array(shown) }
        return shown.filter { $0.racingNumber == driver }
    }

    /// Where clip audio lives: F1's live timing archive.
    public static let audioBase = "https://livetiming.formula1.com/static/"

    /// A clip's MP3: `audioBase` + the session's `Path` (SessionInfo; a missing closing slash is
    /// added) + the clip's `Path`, percent-encoded ("São" is "S%C3%A3o"), as Android's
    /// `radioBase + clip.path`. Nil when either is empty or has an empty, "." or ".." segment or
    /// a leading "/": the address always stays under the archive, so a request that carries the
    /// F1 TV sign-in (the fallback, if F1 refuses one without) can only go there.
    public static func audioURL(sessionPath: String, clipPath: String) -> URL? {
        let session = sessionPath.hasSuffix("/") ? String(sessionPath.dropLast()) : sessionPath
        let path = session + "/" + clipPath
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !session.isEmpty, !clipPath.isEmpty,
              !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let base = URL(string: audioBase),
              let url = URL(string: audioBase + encoded),
              url.scheme == base.scheme, url.host == base.host, url.port == base.port, url.path.hasPrefix(base.path)
        else { return nil }
        return url
    }

    /// Path characters left as they are: letters, digits, "/" and the unreserved marks (as
    /// `TimingArchive`'s requests).
    private static let pathAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-._~")

    /// A list in order, or keyed entries in number order (any other keys after, by name).
    static func captures(_ value: JSONValue) -> [JSONValue] {
        let items: [JSONValue]
        switch value {
        case .array(let list):
            items = list
        case .object(let members):
            items = members.sorted { a, b in
                switch (Int(a.key), Int(b.key)) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.key < b.key
                }
            }.map(\.value)
        default:
            items = []
        }
        return items.filter { if case .object = $0 { return true } else { return false } }
    }
}

/// What a radio clip's row is headed with: where the session was when F1 published the clip.
/// The app writes the words ("Lap 23", "Before the start", "Q2 · 8:12 left", "12:24").
public enum RadioLapLabel: Sendable, Equatable {
    /// Before the session's first start (in a race, lights out).
    case beforeStart
    /// A race: the driver's lap, F1's count of laps done plus one, as Android's `lapAt`.
    case lap(Int)
    /// A race, once it was finished (the leader's chequered flag), for every car.
    case afterFlag
    /// Qualifying: the part running (TimingData's SessionPart) and the session clock
    /// (ExtrapolatedClock); either can be missing.
    case qualifying(part: Int?, remainingMs: Int64?)
    /// Practice: the time since the session started (red flags included).
    case practice(elapsedMs: Int64)
    /// Nothing to say: a race joined under way and a car with no lap count yet, or a practice
    /// session whose start isn't known.
    case unknown
}

extension RadioClips {
    /// The label for `clip`, from the session's data at the clip's `Utc` only (nothing after it):
    /// - before the first "Started": `.beforeStart` (also when the feed joined while "Inactive");
    /// - a race once "Finished" (or "Finalised", "Ends"): `.afterFlag`;
    /// - a race: the car's lap count at `Utc` plus one. A car timing shows with no count yet,
    ///   after a start the feed saw, is on lap 1 (2026 sends no NumberOfLaps until lap 1 ends;
    ///   Android shows nothing there), but only while no car has a count of 2 or more at `Utc`:
    ///   once any car does, a car with no count is `.unknown`. A car timing hasn't shown, or no
    ///   count with no known start (joined under way), is `.unknown`;
    /// - qualifying (and sprint qualifying): the part and the clock;
    /// - anything else: the time since the start.
    public static func lapLabel(for clip: RadioClip, in session: LoadedSession) -> RadioLapLabel {
        let t = clip.utc
        let status = session.sessionStatus
        let started = status.started
        let now = status.status(at: t)
        if let started, t < started { return .beforeStart }
        if started == nil, now == "Inactive" { return .beforeStart }
        if session.info.isRace {
            if let now, finished.contains(now) { return .afterFlag }
            guard let car = session.timing.state(of: clip.racingNumber, at: t) else { return .unknown }
            if let laps = car.numberOfLaps { return .lap(laps + 1) }
            guard started != nil else { return .unknown }
            // Lap 1 only while the field is on it: no car has finished lap 2's count yet (at or before `t`).
            let anyOnLapTwo = session.timing.at(t).values.contains { ($0.numberOfLaps ?? 0) >= 2 }
            return anyOnLapTwo ? .unknown : .lap(1)
        }
        if session.info.isQualifying {
            return .qualifying(part: session.timing.sessionPart(at: t), remainingMs: session.header.clockRemainingMs(at: t))
        }
        guard let started else { return .unknown }
        return .practice(elapsedMs: F1Values.sub(t, started))
    }

    /// The statuses F1 gives a race once its chequered flag is out.
    static let finished: Set<String> = ["Finished", "Finalised", "Ends"]
}

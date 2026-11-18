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
        return F1Values.sub(local, Int64(gmtOffsetSeconds) * 1000)
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
    public var utc: UTCms
    /// The car's number, as DriverList keys it ("1", "12").
    public var racingNumber: String
    /// Under the session's folder: "TeamRadio/ANT_12_20261108_141229.mp3".
    public var path: String
    /// The time in the file name, when it has one; the track's local time (`RadioFileTime`).
    public var fileTime: RadioFileTime?

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

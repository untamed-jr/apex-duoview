import Foundation
import F1TV

/// A session in F1's timing archive: its key, names, folder and scheduled start.
public struct ArchiveSession: Sendable, Equatable {
    public var key: Int
    public var name: String
    public var type: String
    /// The session's folder under the archive's base, ending in "/".
    public var path: String
    /// The scheduled start.
    public var start: UTCms
    /// The track's offset east of GMT.
    public var gmtOffsetSeconds: Int

    public init(key: Int, name: String, type: String, path: String, start: UTCms, gmtOffsetSeconds: Int) {
        self.key = key
        self.name = name
        self.type = type
        self.path = path
        self.start = start
        self.gmtOffsetSeconds = gmtOffsetSeconds
    }

    /// From an index entry or a SessionInfo.json; nil without a key, a folder or a start.
    init?(_ info: TimingSessionInfo) {
        guard let key = info.key, !info.path.isEmpty, let start = info.start else { return nil }
        self.init(key: key, name: info.name, type: info.type, path: info.path.hasSuffix("/") ? info.path : info.path + "/",
                  start: start, gmtOffsetSeconds: info.gmtOffsetSeconds)
    }
}

/// Finds the archive session an F1 TV video shows, the way Android does.
public enum SessionLookup {
    /// A video this long after a session's start still belongs to it: the session, its
    /// build-up and its aftermath.
    static let spanMs: Int64 = 4 * 3_600_000
    /// Android's slack: the live channel's build-up starts before the session does.
    static let slackMs: Int64 = 30 * 60_000
    /// How F1 names session folders, for finding a session the index doesn't list yet.
    static let folders = ["Race", "Sprint", "Qualifying", "Sprint_Qualifying", "Sprint_Shootout",
                          "Practice_1", "Practice_2", "Practice_3"]

    /// The session in the season's `Index.json`, in order:
    /// 1. the session key;
    /// 2. the meeting (by key or name) plus the longest session name the title contains
    ///    ("Sprint Qualifying" beats "Qualifying");
    /// 3. for a watched live moment, the weekend's latest session that started within the 4 h
    ///    before it (or up to 30 min after it, for the build-up).
    public static func match(index: JSONValue, ref: TimingRef, watched: UTCms?) -> ArchiveSession? {
        pick(candidates(index: index, ref: ref), ref: ref, watched: watched)
    }

    /// Where to look for SessionInfo.json when the index lags: the meeting's folder, the
    /// folder for the session the title names (every folder F1 uses when it names none), on the
    /// track's day of `watched`, else of the video's start. Without the track's offset the start
    /// may fall either side of midnight there, so each day it could be is tried; with neither
    /// time, the three days the meeting's folder name ends on.
    public static func probePaths(ref: TimingRef, meetingFolder: String, gmtOffsetSeconds: Int? = nil,
                                  watched: UTCms? = nil) -> [String] {
        let folder = meetingFolder.hasSuffix("/") ? meetingFolder : meetingFolder + "/"
        let moment = watched ?? ref.start.map { UTCms(($0.timeIntervalSince1970 * 1000).rounded()) }
        var days: [String] = []
        if let moment {
            let offsets: [Int] = gmtOffsetSeconds.map { [$0] } ?? [-12 * 3600, 0, 14 * 3600]
            for offset in offsets {
                let day = dayString(F1Values.add(moment, Int64(offset) * 1000))
                if !days.contains(day) { days.append(day) }
            }
        } else if let last = folder.split(separator: "/").last, let raceDay = date(String(last.prefix(10))) {
            days = (0...2).map { dayString(raceDay - Int64($0) * 86_400_000) }
        }
        let named = folders.filter { ref.title.range(of: $0.replacingOccurrences(of: "_", with: " "), options: .caseInsensitive) != nil }
        let longest = named.map(\.count).max()
        let names = longest.map { n in named.filter { $0.count == n } } ?? folders
        return days.flatMap { day in names.map { "\(folder)\(day)_\($0)/" } }
    }

    // MARK: Internals

    struct Candidate {
        var sameMeeting: Bool
        var session: ArchiveSession
    }

    /// Every session in the index, marked by whether it belongs to the reference's meeting.
    static func candidates(index: JSONValue, ref: TimingRef) -> [Candidate] {
        index["Meetings"].array.flatMap { meeting in
            let sameMeeting = isSameMeeting(meeting, ref)
            return meeting["Sessions"].array.compactMap { entry -> Candidate? in
                guard let info = TimingSessionInfo.parse(entry), let session = ArchiveSession(info) else { return nil }
                return Candidate(sameMeeting: sameMeeting, session: session)
            }
        }
    }

    static func pick(_ candidates: [Candidate], ref: TimingRef, watched: UTCms?) -> ArchiveSession? {
        if let key = ref.sessionKey.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
           let byKey = candidates.first(where: { $0.session.key == key }) {
            return byKey.session
        }
        let weekend = candidates.filter(\.sameMeeting).map(\.session)
        let named = weekend.filter { !$0.name.isEmpty && ref.title.range(of: $0.name, options: .caseInsensitive) != nil }
        // The first of the longest, as Android keeps the first it finds.
        if let byName = named.reduce(nil, { (best: ArchiveSession?, s) in
            best.map { $0.name.count >= s.name.count ? $0 : s } ?? s
        }) {
            return byName
        }
        guard let watched else { return nil }
        return weekend
            .filter { $0.start <= F1Values.add(watched, slackMs) && F1Values.sub(watched, $0.start) < spanMs }
            .max { $0.start < $1.start }
    }

    /// The reference's meeting in the index: its folder (e.g. "2026/2026-11-08_São_Paulo_Grand_Prix/")
    /// and the track's offset from GMT, for probing a session the index doesn't list yet.
    static func meeting(index: JSONValue, ref: TimingRef) -> (folder: String, gmtOffsetSeconds: Int)? {
        let sessions = candidates(index: index, ref: ref).filter(\.sameMeeting).map(\.session)
        guard let first = sessions.first else { return nil }
        let parts = first.path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return ("\(parts[0])/\(parts[1])/", first.gmtOffsetSeconds)
    }

    static func isSameMeeting(_ meeting: JSONValue, _ ref: TimingRef) -> Bool {
        let key = ref.meetingKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty, meeting["Key"].string == key { return true }
        let name = ref.meetingName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && meeting["Name"].string.caseInsensitiveCompare(name) == .orderedSame
    }

    /// "2026-11-08" for a UTC moment.
    static func dayString(_ t: UTCms) -> String {
        let c = utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(t) / 1000))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Midnight UTC of a "yyyy-MM-dd" day.
    static func date(_ day: String) -> UTCms? {
        F1Values.utc(day + "T00:00:00Z")
    }

    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
}

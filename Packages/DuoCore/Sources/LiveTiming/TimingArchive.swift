import Foundation
import F1TV

/// One file from the archive.
public enum ArchiveFile: Sendable, Equatable {
    case data(Data)
    /// F1 refused it (401/403: not published, or not for this sign-in) or has no such file
    /// (404, or a byte range past its end, 416). Never a reason to sign out.
    case unavailable(status: Int)
    /// The network failed or F1 answered with some other error; trying again may work.
    case failed
}

/// A replay's timing, everything the timing views read, built from F1's archive.
public struct LoadedSession: Sendable {
    public var info: TimingSessionInfo
    public var drivers: [String: DriverInfo]
    public var streamStart: UTCms
    public var positions: PositionSeries
    public var timing: TimingTimeline
    public var stints: StintTimeline
    public var header: HeaderTimeline
    public var flags: TrackFlags
    /// Empty when the archive has no SessionStatus.
    public var sessionStatus: SessionStatusTimeline
    /// Optional topics the archive didn't give ("WeatherData", ...), in a fixed order.
    public var missing: [String]

    public init(info: TimingSessionInfo, drivers: [String: DriverInfo], streamStart: UTCms, positions: PositionSeries,
                timing: TimingTimeline, stints: StintTimeline, header: HeaderTimeline, flags: TrackFlags,
                sessionStatus: SessionStatusTimeline = SessionStatusTimeline(), missing: [String]) {
        self.info = info
        self.drivers = drivers
        self.streamStart = streamStart
        self.positions = positions
        self.timing = timing
        self.stints = stints
        self.header = header
        self.flags = flags
        self.sessionStatus = sessionStatus
        self.missing = missing
    }
}

/// F1's live timing archive (livetiming.formula1.com/static), which takes the F1 TV
/// subscription token as `Authorization: Bearer`. Nothing here throws: a refusal is
/// `.unavailable` (and never reaches sign-in), a network error `.failed`. The token goes only
/// in that header, to the archive's own host, and never into a returned value.
public actor TimingArchive {
    private let http: any HTTPClient
    private let token: @Sendable () async -> String?
    private let base: URL

    public init(http: any HTTPClient, token: @escaping @Sendable () async -> String?,
                base: URL = URL(string: "https://livetiming.formula1.com/static/")!) {
        self.http = http
        self.token = token
        self.base = base
    }

    /// The season's Index.json; nil when it can't be had or read.
    public func index(year: Int) async -> JSONValue? {
        guard case .data(let body) = await get("\(year)/Index.json", range: nil) else { return nil }
        return try? JSONValue.parse(Self.withoutBOM(body))
    }

    public func file(sessionPath: String, name: String) async -> ArchiveFile {
        await get(sessionPath + name, range: nil)
    }

    /// Those bytes of a file (fewer at its end). A host that ignores the range sends the whole
    /// file; only the asked-for bytes come back.
    public func range(sessionPath: String, name: String, bytes: ClosedRange<Int>) async -> ArchiveFile {
        await get(sessionPath + name, range: bytes)
    }

    /// The archive session an F1 TV video shows: from the season's index by `SessionLookup`'s
    /// rules; when the index doesn't list it yet, from the SessionInfo.json of the folders
    /// `SessionLookup.probePaths` names in the meeting's folder. Folders are probed only when a
    /// watched moment, a session named in the title or the video's start (to one day) narrows
    /// them; otherwise the index is the only request.
    public func session(for ref: TimingRef, watched: UTCms?) async -> ArchiveSession? {
        guard let index = await index(year: ref.year) else { return nil }
        if let found = SessionLookup.match(index: index, ref: ref, watched: watched) { return found }
        guard let meeting = SessionLookup.meeting(index: index, ref: ref) else { return nil }
        let named = SessionLookup.namedFolders(ref.title) != nil
        // A probed session matches by key, by a name in the title or by the moment: with none of
        // them, don't ask.
        guard watched != nil || ref.sessionKey != nil || named else { return nil }
        // A key alone would mean every folder on each of three days: ask only once the start
        // pins the day.
        guard watched != nil || named
            || SessionLookup.probeDays(ref: ref, meetingFolder: meeting.folder, gmtOffsetSeconds: meeting.gmtOffsetSeconds,
                                       watched: nil).count == 1
        else { return nil }
        let listed = Set(SessionLookup.candidates(index: index, ref: ref).map(\.session.path))
        let paths = SessionLookup.probePaths(ref: ref, meetingFolder: meeting.folder,
                                             gmtOffsetSeconds: meeting.gmtOffsetSeconds, watched: watched)
            .filter { !listed.contains($0) }
        let probed = await withTaskGroup(of: ArchiveSession?.self) { group in
            for path in paths {
                group.addTask {
                    guard case .data(let body) = await self.file(sessionPath: path, name: "SessionInfo.json"),
                          let json = try? JSONValue.parse(Self.withoutBOM(body)),
                          var info = TimingSessionInfo.parse(json) else { return nil }
                    if info.path.isEmpty { info.path = path }
                    return ArchiveSession(info)
                }
            }
            var found: [ArchiveSession] = []
            for await session in group { if let session { found.append(session) } }
            return found
        }
        // In the order the paths were asked for, so a tie goes the same way every time.
        let ordered = paths.compactMap { path in probed.first { $0.path == path } }
            + probed.filter { found in !paths.contains(found.path) }
        return SessionLookup.pick(ordered.map { .init(sameMeeting: true, session: $0) }, ref: ref, watched: watched)
    }

    // MARK: Loading

    /// The topics a replay reads. DriverList, SessionInfo and Position are required; the rest
    /// are optional and listed in `LoadedSession.missing` when the archive doesn't give them.
    /// LapCount is published for races (and sprints) only.
    static func topics(for session: ArchiveSession) -> [String] {
        ["Heartbeat", "TimingData", "TimingAppData", "RaceControlMessages", "TrackStatus", "SessionStatus"]
            + (session.type == "Race" ? ["LapCount"] : [])
            + ["ExtrapolatedClock", "WeatherData"]
    }

    private enum Fetched: Sendable {
        case json(JSONValue)
        case lines([StreamLine])
        case missing
    }

    /// Fetches the session's files concurrently and parses them off the caller's actor
    /// (`@concurrent`, whatever the caller's isolation). Nil only when DriverList, SessionInfo or
    /// Position (or every car position in it) is missing.
    @concurrent
    public static func load(_ session: ArchiveSession, using archive: TimingArchive) async -> LoadedSession? {
        let topics = topics(for: session)
        let files: [String: Fetched] = await withTaskGroup(of: (String, Fetched).self) { group in
            for name in ["DriverList", "SessionInfo"] {
                group.addTask {
                    guard case .data(let body) = await archive.file(sessionPath: session.path, name: name + ".json"),
                          let json = try? JSONValue.parse(withoutBOM(body)) else { return (name, .missing) }
                    return (name, .json(json))
                }
            }
            for name in ["Position.z"] + topics {
                group.addTask {
                    guard case .data(let body) = await archive.file(sessionPath: session.path, name: name + ".jsonStream")
                    else { return (name, .missing) }
                    return (name, .lines(StreamLine.parseFile(body)))
                }
            }
            var out: [String: Fetched] = [:]
            for await (name, fetched) in group { out[name] = fetched }
            return out
        }
        func lines(_ name: String) -> [StreamLine]? {
            if case .lines(let l)? = files[name] { return l }
            return nil
        }
        guard case .json(let driverJSON)? = files["DriverList"], case .object = driverJSON,
              case .json(let infoJSON)? = files["SessionInfo"], let info = TimingSessionInfo.parse(infoJSON),
              let positionLines = lines("Position.z")
        else { return nil }

        guard let streamStart = ArchiveClock.streamStart(heartbeat: lines("Heartbeat") ?? [], positions: positionLines)
        else { return nil }
        async let positions = PositionSeries.parse(lines: positionLines)
        async let timing = TimingTimeline.build(lines: lines("TimingData") ?? [], streamStart: streamStart)
        async let stints = StintTimeline.build(lines: lines("TimingAppData") ?? [], streamStart: streamStart)
        async let header = HeaderTimeline.build(lapCount: lines("LapCount") ?? [], clock: lines("ExtrapolatedClock") ?? [],
                                                weather: lines("WeatherData") ?? [], streamStart: streamStart)
        async let flags = TrackFlags.build(trackStatus: lines("TrackStatus") ?? [], raceControl: lines("RaceControlMessages") ?? [],
                                           streamStart: streamStart, gmtOffsetSeconds: info.gmtOffsetSeconds)
        let cars = await positions
        guard !cars.cars.isEmpty else { return nil }
        return LoadedSession(
            info: info,
            drivers: Drivers.parse(driverJSON),
            streamStart: streamStart,
            positions: cars,
            timing: await timing,
            stints: await stints,
            header: await header,
            flags: await flags,
            sessionStatus: SessionStatusTimeline.build(lines: lines("SessionStatus") ?? [], streamStart: streamStart),
            missing: topics.filter { lines($0) == nil }
        )
    }

    // MARK: Requests

    private func get(_ path: String, range: ClosedRange<Int>?) async -> ArchiveFile {
        // A negative start would go out as a suffix range ("the last n bytes").
        if let range, range.lowerBound < 0 { return .unavailable(status: 416) }
        guard let url = url(path) else { return .failed }
        var headers = ["User-Agent": Endpoints.userAgent]
        if let token = await token(), !token.isEmpty { headers["Authorization"] = "Bearer " + token }
        if let range { headers["Range"] = "bytes=\(range.lowerBound)-\(range.upperBound)" }
        let response: HTTPResponse
        do {
            response = try await http.send(HTTPRequest(method: "GET", url: url, headers: headers))
        } catch {
            // The error's text is never passed on: a transport could have put the header in it.
            return .failed
        }
        switch response.status {
        case 206:
            return .data(response.body)
        case 200..<300:
            guard let range else { return .data(response.body) }
            // The whole file came back: keep to the asked-for bytes.
            let count = response.body.count
            guard range.lowerBound < count else { return .unavailable(status: 416) }
            // The upper bound may be Int.max ("to the end"): clamp before adding one.
            let start = response.body.startIndex + range.lowerBound
            let end = response.body.startIndex + min(range.upperBound, count - 1) + 1
            return .data(response.body.subdata(in: start..<end))
        case 401, 403, 404, 416:
            return .unavailable(status: response.status)
        default:
            return .failed
        }
    }

    /// The base plus the path, percent-encoded; nil for a path that could leave the archive
    /// ("..", or a leading "/"), so the token is only ever sent under the base.
    private func url(_ path: String) -> URL? {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !segments.contains(where: { $0 == ".." || $0 == "." }),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed),
              let url = URL(string: base.absoluteString + encoded),
              url.scheme == base.scheme, url.host == base.host, url.port == base.port,
              url.path.hasPrefix(base.path)
        else { return nil }
        return url
    }

    /// Path characters left as they are: letters, digits, "/" and the unreserved marks.
    private static let pathAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-._~")

    static func withoutBOM(_ data: Data) -> Data {
        data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
    }
}

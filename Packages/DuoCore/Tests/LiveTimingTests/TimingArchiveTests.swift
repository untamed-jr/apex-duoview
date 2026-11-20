import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// Stands in for F1's archive host: answers by the path under /static/, records every request,
/// and can hold every answer until a number of requests are in flight at once, to prove fetches
/// overlap.
actor FakeArchiveHTTP: HTTPClient {
    private var answers: [String: Result<HTTPResponse, Error>] = [:]
    private(set) var requests: [HTTPRequest] = []
    private var inFlight = 0
    private(set) var maxInFlight = 0
    private var holdUntil = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holdTimer: Task<Void, Never>?
    /// The hold ran out before enough requests were in flight: they were not all concurrent.
    private(set) var holdTimedOut = false

    func serve(_ path: String, status: Int = 200, body: Data = Data()) {
        answers[path] = .success(HTTPResponse(status: status, body: body))
    }

    func fail(_ path: String, with error: Error) { answers[path] = .failure(error) }

    /// Holds each request until `count` are in flight together. After `timeout` every held
    /// request is let go and `holdTimedOut` is set, so a test fails instead of hanging.
    func hold(until count: Int, timeout: Duration) {
        holdUntil = count
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.release(timedOut: true)
        }
    }

    /// Lets every held request go (once each) and stops holding.
    private func release(timedOut: Bool) {
        guard holdUntil > 0 else { return }
        if timedOut { holdTimedOut = true }
        holdUntil = 0
        holdTimer?.cancel()
        holdTimer = nil
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }

    /// Every committed fixture file of a session, under its archive folder.
    func serveSession(fixture dir: String, at sessionPath: String) throws {
        let folder = try Fixture.url(dir)
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            serve(sessionPath + name, body: try Data(contentsOf: folder.appendingPathComponent(name)))
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        if holdUntil > 0 {
            if inFlight >= holdUntil {
                release(timedOut: false)
            } else {
                await withCheckedContinuation { held.append($0) }
            }
        }
        let path = request.url.path.hasPrefix("/static/") ? String(request.url.path.dropFirst(8)) : request.url.path
        guard let answer = answers[path] else { return HTTPResponse(status: 404, body: Data()) }
        return try answer.get()
    }
}

/// An error that carries the token in its text, as a careless transport might.
struct LeakyError: Error, CustomStringConvertible {
    let token: String
    var description: String { "connection to livetiming failed with Authorization: Bearer \(token)" }
}

@Suite struct TimingArchiveTests {
    static let token = "SENTINEL-TOKEN-7f3a9c"
    static let racePath = "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/"
    static let qualiPath = "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-07_Qualifying/"
    static let race = ArchiveSession(key: 11412, name: "Race", type: "Race", path: racePath,
                                     start: SignalR.utc("2026-11-08T17:00:00Z")!, gmtOffsetSeconds: -10_800)
    static let quali = ArchiveSession(key: 11408, name: "Qualifying", type: "Qualifying", path: qualiPath,
                                      start: SignalR.utc("2026-11-07T18:00:00Z")!, gmtOffsetSeconds: -10_800)

    static func archive(_ http: FakeArchiveHTTP, token: String? = TimingArchiveTests.token) -> TimingArchive {
        TimingArchive(http: http, token: { token })
    }

    static func raceHTTP() async throws -> FakeArchiveHTTP {
        let http = FakeArchiveHTTP()
        try await http.serveSession(fixture: "sp26-race", at: racePath)
        return http
    }

    // MARK: Files

    @Test func bearerHeaderSent() async throws {
        let http = try await Self.raceHTTP()
        let file = await Self.archive(http).file(sessionPath: Self.racePath, name: "SessionInfo.json")
        #expect(file == .data(try Fixture.data("sp26-race/SessionInfo.json")))
        let request = try #require(await http.requests.first)
        #expect(request.method == "GET")
        #expect(request.headers["Authorization"] == "Bearer \(Self.token)")
        #expect(request.headers["User-Agent"] == Endpoints.userAgent)
        // The folder's "ã" is percent-encoded, on F1's host under /static/.
        #expect(request.url.absoluteString == "https://livetiming.formula1.com/static/2026/2026-11-08_S%C3%A3o_Paulo_Grand_Prix/2026-11-08_Race/SessionInfo.json")
    }

    @Test func noTokenSendsNoAuthorization() async throws {
        let http = try await Self.raceHTTP()
        _ = await Self.archive(http, token: nil).file(sessionPath: Self.racePath, name: "SessionInfo.json")
        #expect(await http.requests.first?.headers["Authorization"] == nil)
    }

    @Test func refusalsAreUnavailableAndOtherFailuresFailed() async throws {
        let http = FakeArchiveHTTP()
        let archive = Self.archive(http)
        for status in [401, 403, 404, 416] {
            await http.serve("x/\(status).json", status: status)
            #expect(await archive.file(sessionPath: "x/", name: "\(status).json") == .unavailable(status: status))
        }
        for status in [500, 502, 429, 302] {
            await http.serve("x/\(status).json", status: status)
            #expect(await archive.file(sessionPath: "x/", name: "\(status).json") == .failed)
        }
        await http.fail("x/net.json", with: URLError(.notConnectedToInternet))
        #expect(await archive.file(sessionPath: "x/", name: "net.json") == .failed)
        await http.fail("x/cancel.json", with: CancellationError())
        #expect(await archive.file(sessionPath: "x/", name: "cancel.json") == .failed)
    }

    @Test func pathsThatLeaveTheArchiveAreRefusedUnsent() async throws {
        let http = FakeArchiveHTTP()
        let archive = Self.archive(http)
        for path in ["../../", "2026/../../x/", "//evil.example/"] {
            #expect(await archive.file(sessionPath: path, name: "SessionInfo.json") == .failed)
        }
        // "?" and "#" stay part of the path.
        _ = await archive.file(sessionPath: "2026/a?b#c/", name: "SessionInfo.json")
        let sent = await http.requests
        #expect(sent.count == 1)
        #expect(sent.allSatisfy { $0.url.host == "livetiming.formula1.com" && $0.url.query == nil && $0.url.fragment == nil })
    }

    @Test func rangeSendsTheRangeAndKeepsToIt() async throws {
        let http = FakeArchiveHTTP()
        let archive = Self.archive(http)
        let body = Data((0..<200).map { UInt8($0) })
        await http.serve("x/partial.z", status: 206, body: body.subdata(in: 10..<20))
        #expect(await archive.range(sessionPath: "x/", name: "partial.z", bytes: 10...19) == .data(body.subdata(in: 10..<20)))
        #expect(await http.requests.last?.headers["Range"] == "bytes=10-19")
        #expect(await http.requests.last?.headers["Authorization"] == "Bearer \(Self.token)")
        // A host that ignores the range sends the whole file: only the asked-for bytes come back.
        await http.serve("x/whole.z", body: body)
        #expect(await archive.range(sessionPath: "x/", name: "whole.z", bytes: 10...19) == .data(body.subdata(in: 10..<20)))
        #expect(await archive.range(sessionPath: "x/", name: "whole.z", bytes: 190...299) == .data(body.subdata(in: 190..<200)))
        #expect(await archive.range(sessionPath: "x/", name: "whole.z", bytes: 300...399) == .unavailable(status: 416))
        // "To the end" as an open upper bound, without overflowing.
        #expect(await archive.range(sessionPath: "x/", name: "whole.z", bytes: 150...Int.max) == .data(body.subdata(in: 150..<200)))
        #expect(await http.requests.last?.headers["Range"] == "bytes=150-\(Int.max)")
        // A negative start would be a suffix range: refused unsent.
        let sent = await http.requests.count
        #expect(await archive.range(sessionPath: "x/", name: "whole.z", bytes: -10...5) == .unavailable(status: 416))
        #expect(await http.requests.count == sent)
    }

    @Test func byteRangeTellsAHonouredRangeFromAnIgnoredOne() async throws {
        let http = FakeArchiveHTTP()
        let archive = Self.archive(http)
        let body = Data((0..<200).map { UInt8($0) })
        await http.serve("x/partial.z", status: 206, body: body.subdata(in: 0..<100))
        #expect(await archive.byteRange(sessionPath: "x/", name: "partial.z", bytes: 0...99) == .partial(body.subdata(in: 0..<100)))
        #expect(await http.requests.last?.headers["Range"] == "bytes=0-99")
        #expect(await http.requests.last?.headers["Authorization"] == "Bearer \(Self.token)")
        // A 200 is the whole file, kept whole: the caller stops asking for ranges.
        await http.serve("x/whole.z", body: body)
        #expect(await archive.byteRange(sessionPath: "x/", name: "whole.z", bytes: 100...199) == .whole(body))
        // Past the end, refused, missing: unavailable with the status; other errors failed.
        for status in [416, 401, 403, 404] {
            await http.serve("x/s.z", status: status)
            #expect(await archive.byteRange(sessionPath: "x/", name: "s.z", bytes: 0...9) == .unavailable(status: status))
        }
        await http.serve("x/s.z", status: 503)
        #expect(await archive.byteRange(sessionPath: "x/", name: "s.z", bytes: 0...9) == .failed)
        await http.fail("x/s.z", with: URLError(.timedOut))
        #expect(await archive.byteRange(sessionPath: "x/", name: "s.z", bytes: 0...9) == .failed)
        // A negative start is refused unsent; a path that leaves the archive fails unsent.
        let sent = await http.requests.count
        #expect(await archive.byteRange(sessionPath: "x/", name: "s.z", bytes: -10...5) == .unavailable(status: 416))
        #expect(await archive.byteRange(sessionPath: "../", name: "s.z", bytes: 0...9) == .failed)
        #expect(await http.requests.count == sent)
    }

    @Test func indexStripsTheBOM() async throws {
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: Data([0xEF, 0xBB, 0xBF]) + (try Fixture.data("Index-2026.json")))
        let index = await Self.archive(http).index(year: 2026)
        #expect(index?["Meetings"].array.count == 2)
        #expect(await Self.archive(http).index(year: 2025) == nil)
        await http.serve("2024/Index.json", body: Data("<html>".utf8))
        #expect(await Self.archive(http).index(year: 2024) == nil)
    }

    // MARK: Loading a session

    @Test func loadsTheRace() async throws {
        let http = try await Self.raceHTTP()
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.missing == [])
        #expect(loaded.info.key == 11412)
        #expect(loaded.drivers.count == 22)
        #expect(loaded.drivers["1"]?.tla != nil)
        #expect(loaded.streamStart == Fixture.raceStart)
        #expect(loaded.positions.cars.count >= 20)
        #expect(loaded.header.at(Fixture.raceLightsOut + 300_000).totalLaps == 71)
        #expect(!loaded.timing.at(Fixture.raceLightsOut + 300_000).isEmpty)
        #expect(!loaded.stints.at(Fixture.raceLightsOut + 300_000).isEmpty)
        // check:raceLightsOutUtc: SessionStatus "Started" at 00:53:44.576.
        #expect(loaded.sessionStatus.started == Fixture.raceLightsOut)
        #expect(loaded.sessionStatus.status(at: Fixture.raceLightsOut + 1) == "Started")
        // Not fetched: topics nothing reads yet, and CarData (fetched in the background later).
        let asked = Set(await http.requests.map { $0.url.lastPathComponent })
        #expect(asked == ["DriverList.json", "SessionInfo.json", "Position.z.jsonStream", "Heartbeat.jsonStream",
                          "TimingData.jsonStream", "TimingAppData.jsonStream", "RaceControlMessages.jsonStream",
                          "TrackStatus.jsonStream", "SessionStatus.jsonStream", "LapCount.jsonStream",
                          "ExtrapolatedClock.jsonStream", "WeatherData.jsonStream", "TeamRadio.jsonStream"])
    }

    @Test func archiveLoadsRadio() async throws {
        let http = try await Self.raceHTTP()
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        let clips = try RadioClips(lines: Fixture.lines("sp26-race/TeamRadio.jsonStream"))
        #expect(!clips.all.isEmpty)
        #expect(loaded.radio == clips)
        let entries = try RaceControlLog.parse(lines: Fixture.lines("sp26-race/RaceControlMessages.jsonStream"),
                                               streamStart: Fixture.raceStart)
        #expect(!entries.isEmpty)
        #expect(loaded.raceControl == entries)
        #expect(loaded.missing == [])
    }

    @Test func missingTeamRadioIsOptional() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "TeamRadio.jsonStream", status: 403)
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.missing == ["TeamRadio"])
        #expect(loaded.failed == [])
        #expect(loaded.radio.all.isEmpty)
        // Everything else still loads.
        #expect(!loaded.raceControl.isEmpty)
        #expect(loaded.positions.cars.count >= 20)
    }

    /// The archive loader's session is the one built by hand from the same long slice
    /// (`RadioRaceTests.longRace()`), radio and race control included. The slice has no
    /// Position, so the loader is given the short race's.
    @Test func archiveLoadMatchesLongRace() async throws {
        let http = FakeArchiveHTTP()
        try await http.serveSession(fixture: "sp26-race-long", at: Self.racePath)
        await http.serve(Self.racePath + "Position.z.jsonStream",
                         body: try Data(contentsOf: Fixture.url("sp26-race/Position.z.jsonStream")))
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        let hand = try RadioRaceTests.longRace()
        #expect(loaded.info == hand.info)
        #expect(loaded.drivers == hand.drivers)
        #expect(loaded.streamStart == hand.streamStart)
        #expect(loaded.radio == hand.radio)
        #expect(loaded.radio.all.count == 30)
        #expect(loaded.raceControl == hand.raceControl)
        #expect(!loaded.raceControl.isEmpty)
        #expect(loaded.flags.spans == hand.flags.spans)
        #expect(loaded.sessionStatus == hand.sessionStatus)
        #expect(loaded.timing.updateTimes == hand.timing.updateTimes)
        #expect(loaded.header.laps == hand.header.laps)
    }

    @Test func qualifyingAsksForNoLapCount() async throws {
        let http = FakeArchiveHTTP()
        try await http.serveSession(fixture: "sp26-quali", at: Self.qualiPath)
        let loaded = try #require(await TimingArchive.load(Self.quali, using: Self.archive(http)))
        #expect(loaded.missing == [])
        #expect(loaded.streamStart == Fixture.qualiStart)
        #expect(await !http.requests.contains { $0.url.lastPathComponent == "LapCount.jsonStream" })
    }

    @Test func forbiddenFileIsUnavailableNotError() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "WeatherData.jsonStream", status: 403)
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.missing == ["WeatherData"])
        #expect(loaded.header.at(Fixture.raceLightsOut).airTemp == nil)
        #expect(loaded.positions.cars.count >= 20)
    }

    @Test func missingSessionStatusIsOptional() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "SessionStatus.jsonStream", status: 404)
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.missing == ["SessionStatus"])
        #expect(loaded.sessionStatus.started == nil)
        #expect(loaded.sessionStatus.changes.isEmpty)
        #expect(loaded.positions.cars.count >= 20)
    }

    /// Refused or not there is `missing`; failed to download is `failed`: separate lists, each in
    /// topic order. Core topics refused are only missing; the load goes on.
    @Test func lapCountIsReadForWhatIsRaceCallsARace() {
        // The archive's topics and a live session's optional ones use `isRace`'s own test.
        for type in ["Race", "race", "Sprint Race", "Qualifying", "Practice 1"] {
            var session = Self.race
            session.type = type
            let info = TimingSessionInfo(key: 1, name: type, type: type, path: "x/", start: nil, gmtOffsetSeconds: 0,
                                         circuitKey: nil, meetingName: "", year: nil)
            #expect(TimingArchive.topics(for: session).contains("LapCount") == info.isRace, "\(type)")
            #expect(LiveFeed.optionalTopics(type: type).contains("LapCount") == info.isRace, "\(type)")
        }
    }

    @Test func optionalTopicsGoMissingOrFailedInTopicOrder() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "SessionStatus.jsonStream", status: 403)
        await http.serve(Self.racePath + "WeatherData.jsonStream", status: 404)
        await http.serve(Self.racePath + "TimingData.jsonStream", status: 404)
        await http.serve(Self.racePath + "Heartbeat.jsonStream", status: 500)
        await http.fail(Self.racePath + "ExtrapolatedClock.jsonStream", with: URLError(.timedOut))
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.missing == ["TimingData", "SessionStatus", "WeatherData"])
        #expect(loaded.failed == ["Heartbeat", "ExtrapolatedClock"])
        // Without the heartbeat the cars' own clocks give the start: 2.1 s early on this race
        // (check:raceStartsDifferMs).
        #expect(loaded.streamStart == Fixture.raceStart - 2_102)
        #expect(loaded.timing.at(Fixture.raceLightsOut).isEmpty)
    }

    /// TimingData, TrackStatus or SessionStatus failing to download fails the whole load (it is
    /// tried again), rather than a session with silent gaps.
    @Test(arguments: TimingArchive.core)
    func coreTopicFailingFailsTheLoad(topic: String) async throws {
        for failure in [HTTPFailure.network, .status(503)] {
            let http = try await Self.raceHTTP()
            switch failure {
            case .network: await http.fail(Self.racePath + topic + ".jsonStream", with: URLError(.networkConnectionLost))
            case .status(let code): await http.serve(Self.racePath + topic + ".jsonStream", status: code)
            }
            if case .failed = await TimingArchive.loadOutcome(Self.race, using: Self.archive(http)) {} else {
                Issue.record("\(topic) \(failure): failed")
            }
        }
    }

    enum HTTPFailure { case network, status(Int) }

    /// Any other optional topic that fails is listed in `failed`, not `missing`, and the rest loads.
    @Test func optionalTopicFailingIsListedAsFailed() async throws {
        let http = try await Self.raceHTTP()
        await http.fail(Self.racePath + "WeatherData.jsonStream", with: URLError(.timedOut))
        await http.serve(Self.racePath + "TimingAppData.jsonStream", status: 502)
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.failed == ["TimingAppData", "WeatherData"])
        #expect(loaded.missing == [])
        #expect(!loaded.timing.at(Fixture.raceLightsOut + 300_000).isEmpty)
    }

    @Test(arguments: ["DriverList.json", "SessionInfo.json", "Position.z.jsonStream"])
    func missingRequiredFileGivesNil(name: String) async throws {
        for status in [403, 404] {
            let http = try await Self.raceHTTP()
            await http.serve(Self.racePath + name, status: status)
            #expect(await TimingArchive.load(Self.race, using: Self.archive(http)) == nil)
        }
        let http = try await Self.raceHTTP()
        await http.fail(Self.racePath + name, with: URLError(.networkConnectionLost))
        #expect(await TimingArchive.load(Self.race, using: Self.archive(http)) == nil)
    }

    /// Why there is no session: refused (no timing; a retry can't help) or failed (try again).
    /// A refusal wins over a failure: a retry would fetch everything again for nothing.
    @Test func loadOutcomeTellsRefusedFromFailed() async throws {
        func outcome(_ setup: (FakeArchiveHTTP) async -> Void) async throws -> ArchiveOutcome<LoadedSession> {
            let http = try await Self.raceHTTP()
            await setup(http)
            return await TimingArchive.loadOutcome(Self.race, using: Self.archive(http))
        }
        #expect(try await outcome { _ in }.value?.missing == [])
        if case .unavailable = try await outcome({ await $0.serve(Self.racePath + "DriverList.json", status: 403) }) {} else {
            Issue.record("a refused DriverList is unavailable")
        }
        if case .failed = try await outcome({ await $0.fail(Self.racePath + "Position.z.jsonStream", with: URLError(.timedOut)) }) {} else {
            Issue.record("a Position that failed to download is failed")
        }
        if case .failed = try await outcome({ await $0.serve(Self.racePath + "SessionInfo.json", status: 503) }) {} else {
            Issue.record("a 503 SessionInfo is failed")
        }
        let mixed = try await outcome {
            await $0.serve(Self.racePath + "Position.z.jsonStream", status: 404)
            await $0.fail(Self.racePath + "DriverList.json", with: URLError(.networkConnectionLost))
        }
        if case .unavailable = mixed {} else { Issue.record("a refusal wins over a failure") }
        // An optional topic that fails still loads, listed as failed (not missing).
        let optional = try await outcome { await $0.fail(Self.racePath + "WeatherData.jsonStream", with: URLError(.timedOut)) }
        #expect(optional.value?.failed == ["WeatherData"])
        #expect(optional.value?.missing == [])
        // A core topic that fails fails the load; refused, it is only missing.
        if case .failed = try await outcome({ await $0.fail(Self.racePath + "TrackStatus.jsonStream", with: URLError(.timedOut)) }) {} else {
            Issue.record("a failed TrackStatus is failed")
        }
        let refusedCore = try await outcome { await $0.serve(Self.racePath + "TrackStatus.jsonStream", status: 403) }
        #expect(refusedCore.value?.missing == ["TrackStatus"])
        // Files that came but hold nothing usable: unavailable.
        let empty = try await outcome { await $0.serve(Self.racePath + "DriverList.json", body: Data("[]".utf8)) }
        if case .unavailable = empty {} else { Issue.record("a DriverList that isn't an object is unavailable") }
    }

    @Test func missingPositionGivesNil() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "Position.z.jsonStream", status: 403)
        #expect(await TimingArchive.load(Self.race, using: Self.archive(http)) == nil)
        // A Position file with no readable car positions is as good as missing.
        await http.serve(Self.racePath + "Position.z.jsonStream", body: Data("00:00:01.000\"bm90IGRlZmxhdGU=\"\n".utf8))
        #expect(await TimingArchive.load(Self.race, using: Self.archive(http)) == nil)
    }

    /// Every file is asked for before any answer comes back: the fake holds each request until
    /// all of them are in flight together (failing, not hanging, if they never are).
    @Test func loadFetchesConcurrently() async throws {
        let http = try await Self.raceHTTP()
        let files = 3 + TimingArchive.topics(for: Self.race).count  // DriverList, SessionInfo, Position.z
        await http.hold(until: files, timeout: .seconds(30))
        let loaded = await TimingArchive.load(Self.race, using: Self.archive(http))
        #expect(await !http.holdTimedOut)
        #expect(await http.maxInFlight == files)
        #expect(await http.requests.count == files)
        #expect(loaded?.missing == [])
    }

    @Test func tokenNeverInResult() async throws {
        let http = try await Self.raceHTTP()
        await http.fail(Self.racePath + "LapCount.jsonStream", with: LeakyError(token: Self.token))
        await http.serve(Self.racePath + "WeatherData.jsonStream", status: 403)
        let archive = Self.archive(http)
        let loaded = try #require(await TimingArchive.load(Self.race, using: archive))
        #expect(loaded.missing == ["WeatherData"])
        #expect(loaded.failed == ["LapCount"])
        var text = ""
        dump(loaded, to: &text, maxDepth: 3, maxItems: 10_000)
        text += String(describing: loaded.missing) + String(describing: loaded.failed) + String(describing: loaded.info)
            + String(describing: loaded.drivers)
        #expect(!text.contains(Self.token))
        for file in [await archive.file(sessionPath: Self.racePath, name: "LapCount.jsonStream"),
                     await archive.file(sessionPath: Self.racePath, name: "WeatherData.jsonStream"),
                     await archive.range(sessionPath: Self.racePath, name: "LapCount.jsonStream", bytes: 0...9)] {
            #expect(!String(describing: file).contains(Self.token))
            #expect(!String(reflecting: file).contains(Self.token))
        }
    }

    // MARK: Finding a session (index, then a probe when the index lags)

    @Test func sessionForRefUsesTheIndex() async throws {
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try Fixture.data("Index-2026.json"))
        let ref = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "11412", circuitKey: 14,
                            meetingName: "São Paulo Grand Prix", title: "2026 São Paulo Grand Prix")
        #expect(await Self.archive(http).session(for: ref, watched: nil) == Self.race)
        #expect(await http.requests.count == 1)
    }

    /// The index without the race, as it is in the hours after one.
    static func indexWithoutRace() throws -> JSONValue {
        var index = try Fixture.json("Index-2026.json")
        if case .object(var top) = index, case .array(var meetings) = top["Meetings"],
           case .object(var sp) = meetings[1], case .array(let sessions) = sp["Sessions"] {
            sp["Sessions"] = .array(sessions.filter { $0["Name"].string != "Race" })
            meetings[1] = .object(sp)
            top["Meetings"] = .array(meetings)
            index = .object(top)
        }
        return index
    }

    @Test func sessionForRefProbesWhenTheIndexLags() async throws {
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try JSONSerialization.data(withJSONObject: Self.plain(try Self.indexWithoutRace())))
        await http.serve(Self.racePath + "SessionInfo.json", body: try Fixture.data("sp26-race/SessionInfo.json"))
        let live = TimingRef(year: 2026, meetingKey: "1299", circuitKey: 14, meetingName: "São Paulo Grand Prix",
                             title: "São Paulo Grand Prix")
        let found = await Self.archive(http).session(for: live, watched: Self.race.start + 1_800_000)
        #expect(found == Self.race)
        // Only that day's folders were tried, never a session the index already lists.
        let probed = await http.requests.map(\.url.path).filter { $0.hasSuffix("SessionInfo.json") }
        #expect(probed.count == 8)
        #expect(probed.allSatisfy { $0.contains("/2026-11-08_") })
        // Nothing could match a probe (no key, no moment, no session in the title): none sent.
        let before = await http.requests.count
        #expect(await Self.archive(http).session(for: live, watched: nil) == nil)
        #expect(await http.requests.count == before + 1)  // the index only
        // Not this weekend, or no index: nothing.
        let elsewhere = TimingRef(year: 2026, meetingKey: "9999", meetingName: "Nowhere", title: "Race")
        #expect(await Self.archive(http).session(for: elsewhere, watched: Self.race.start) == nil)
        #expect(await Self.archive(FakeArchiveHTTP()).session(for: live, watched: Self.race.start) == nil)
    }

    /// A replay of a session the index doesn't list yet (key and start, no watched moment):
    /// the start pins the day, so that day's folders are probed and the session is found.
    @Test func sessionKeyWithAStartFindsTheUnlistedSession() async throws {
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try JSONSerialization.data(withJSONObject: Self.plain(try Self.indexWithoutRace())))
        await http.serve(Self.racePath + "SessionInfo.json", body: try Fixture.data("sp26-race/SessionInfo.json"))
        let ref = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "11412", circuitKey: 14,
                            meetingName: "São Paulo Grand Prix", title: "2026 São Paulo Grand Prix",
                            start: Date(timeIntervalSince1970: Double(Self.race.start) / 1000))
        #expect(await Self.archive(http).session(for: ref, watched: nil) == Self.race)
        let probed = await http.requests.map(\.url.path).filter { $0.hasSuffix("SessionInfo.json") }
        #expect(!probed.isEmpty && probed.allSatisfy { $0.contains("/2026-11-08_") })
    }

    @Test func sessionKeyAloneProbesNothing() async throws {
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try Fixture.data("Index-2026.json"))
        // This weekend, a key the index doesn't list, no session in the title, no start, no
        // moment: nothing narrows the folders, so after the index nothing is asked.
        let ref = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "99999", circuitKey: 14,
                            meetingName: "São Paulo Grand Prix", title: "2026 São Paulo Grand Prix")
        #expect(await Self.archive(http).session(for: ref, watched: nil) == nil)
        #expect(await http.requests.map(\.url.lastPathComponent) == ["Index.json"])
        // A start that is no moment narrows nothing either.
        var odd = ref
        odd.start = Date(timeIntervalSince1970: 1e15)
        #expect(await Self.archive(http).session(for: odd, watched: nil) == nil)
        #expect(await http.requests.count == 2)
    }

    /// Index.json refused or missing (a season the archive doesn't have) is no timing; one that
    /// failed to download or came back unreadable is worth trying again.
    @Test func lookupTellsNoMatchFromFailed() async throws {
        let ref = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "11412", circuitKey: 14,
                            meetingName: "São Paulo Grand Prix", title: "2026 São Paulo Grand Prix")
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try Fixture.data("Index-2026.json"))
        #expect(await Self.archive(http).lookup(for: ref, watched: nil).value == Self.race)
        let elsewhere = TimingRef(year: 2026, meetingKey: "9999", meetingName: "Nowhere", title: "2026 Nowhere Grand Prix")
        if case .unavailable = await Self.archive(http).lookup(for: elsewhere, watched: nil) {} else {
            Issue.record("no match is unavailable")
        }
        for status in [403, 404] {
            let refused = FakeArchiveHTTP()
            await refused.serve("2026/Index.json", status: status)
            if case .unavailable = await Self.archive(refused).lookup(for: ref, watched: nil) {} else {
                Issue.record("a \(status) index is unavailable")
            }
        }
        let failed = FakeArchiveHTTP()
        await failed.fail("2026/Index.json", with: URLError(.notConnectedToInternet))
        if case .failed = await Self.archive(failed).lookup(for: ref, watched: nil) {} else { Issue.record("network: failed") }
        await failed.serve("2026/Index.json", status: 502)
        if case .failed = await Self.archive(failed).lookup(for: ref, watched: nil) {} else { Issue.record("502: failed") }
        await failed.serve("2026/Index.json", body: Data("<html>".utf8))
        if case .failed = await Self.archive(failed).lookup(for: ref, watched: nil) {} else { Issue.record("garbled: failed") }
        // `session(for:)` is the same answer without the reason.
        #expect(await Self.archive(failed).session(for: ref, watched: nil) == nil)
    }

    /// The index lags and a probe fails to download: no match may only mean that probe, so the
    /// lookup is `.failed` (tried again), not "no timing". A probe that is refused stays a miss.
    @Test func failedProbeWithNoMatchIsFailed() async throws {
        let ref = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "11412", circuitKey: 14,
                            meetingName: "São Paulo Grand Prix", title: "2026 São Paulo Grand Prix",
                            start: Date(timeIntervalSince1970: Double(Self.race.start) / 1000))
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try JSONSerialization.data(withJSONObject: Self.plain(try Self.indexWithoutRace())))
        await http.fail(Self.racePath + "SessionInfo.json", with: URLError(.timedOut))
        if case .failed = await Self.archive(http).lookup(for: ref, watched: nil) {} else {
            Issue.record("a failed probe with no match is failed")
        }
        // The probe answers next time: found.
        await http.serve(Self.racePath + "SessionInfo.json", body: try Fixture.data("sp26-race/SessionInfo.json"))
        #expect(await Self.archive(http).lookup(for: ref, watched: nil).value == Self.race)
        // Every probe refused or not there: no timing.
        await http.serve(Self.racePath + "SessionInfo.json", status: 404)
        if case .unavailable = await Self.archive(http).lookup(for: ref, watched: nil) {} else {
            Issue.record("refused probes are unavailable")
        }
    }

    @Test func sessionKeyWithAStartProbesThatDay() async throws {
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try Fixture.data("Index-2026.json"))
        var ref = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "99999", circuitKey: 14,
                            meetingName: "São Paulo Grand Prix", title: "2026 São Paulo Grand Prix")
        ref.start = Date(timeIntervalSince1970: Double(Self.race.start) / 1000)
        #expect(await Self.archive(http).session(for: ref, watched: nil) == nil)
        let probed = await http.requests.map(\.url.path).filter { $0.hasSuffix("SessionInfo.json") }
        // The one day's folders the index doesn't list (its race and quali are listed).
        #expect(!probed.isEmpty && probed.count <= SessionLookup.folders.count)
        #expect(probed.allSatisfy { $0.contains("/2026-11-08_") })
        // A title naming the session narrows it without a start: that folder on each day it could be.
        let named = TimingRef(year: 2026, meetingKey: "1299", sessionKey: "99999", meetingName: "São Paulo Grand Prix",
                              title: "2026 São Paulo GP - Sprint")
        let before = await http.requests.count
        _ = await Self.archive(http).session(for: named, watched: nil)
        let more = await http.requests.dropFirst(before).map(\.url.path).filter { $0.hasSuffix("SessionInfo.json") }
        #expect(!more.isEmpty && more.allSatisfy { $0.hasSuffix("_Sprint/SessionInfo.json") })
    }

    static func plain(_ v: JSONValue) -> Any {
        switch v {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(plain)
        case .object(let o): return o.mapValues(plain)
        }
    }
}

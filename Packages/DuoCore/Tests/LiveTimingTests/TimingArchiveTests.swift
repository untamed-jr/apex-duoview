import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// Stands in for F1's archive host: answers by the path under /static/, records every request,
/// and can hold each answer briefly to show fetches overlap.
actor FakeArchiveHTTP: HTTPClient {
    private var answers: [String: Result<HTTPResponse, Error>] = [:]
    private(set) var requests: [HTTPRequest] = []
    private var inFlight = 0
    private(set) var maxInFlight = 0
    var delay: Duration = .zero

    func serve(_ path: String, status: Int = 200, body: Data = Data()) {
        answers[path] = .success(HTTPResponse(status: status, body: body))
    }

    func fail(_ path: String, with error: Error) { answers[path] = .failure(error) }

    func setDelay(_ d: Duration) { delay = d }

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
        if delay > .zero { try? await Task.sleep(for: delay) }
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
                          "ExtrapolatedClock.jsonStream", "WeatherData.jsonStream"])
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

    @Test func optionalTopicsGoMissingInTopicOrder() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "SessionStatus.jsonStream", status: 403)
        await http.serve(Self.racePath + "WeatherData.jsonStream", status: 404)
        await http.fail(Self.racePath + "TimingData.jsonStream", with: URLError(.timedOut))
        await http.serve(Self.racePath + "Heartbeat.jsonStream", status: 500)
        let loaded = try #require(await TimingArchive.load(Self.race, using: Self.archive(http)))
        #expect(loaded.missing == ["Heartbeat", "TimingData", "SessionStatus", "WeatherData"])
        // Without the heartbeat the cars' own clocks give the start: 2.1 s early on this race
        // (check:raceStartsDifferMs).
        #expect(loaded.streamStart == Fixture.raceStart - 2_102)
        #expect(loaded.timing.at(Fixture.raceLightsOut).isEmpty)
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

    @Test func missingPositionGivesNil() async throws {
        let http = try await Self.raceHTTP()
        await http.serve(Self.racePath + "Position.z.jsonStream", status: 403)
        #expect(await TimingArchive.load(Self.race, using: Self.archive(http)) == nil)
        // A Position file with no readable car positions is as good as missing.
        await http.serve(Self.racePath + "Position.z.jsonStream", body: Data("00:00:01.000\"bm90IGRlZmxhdGU=\"\n".utf8))
        #expect(await TimingArchive.load(Self.race, using: Self.archive(http)) == nil)
    }

    @Test func loadFetchesConcurrently() async throws {
        let http = try await Self.raceHTTP()
        await http.setDelay(.milliseconds(50))
        _ = await TimingArchive.load(Self.race, using: Self.archive(http))
        #expect(await http.maxInFlight >= 5)
    }

    @Test func tokenNeverInResult() async throws {
        let http = try await Self.raceHTTP()
        await http.fail(Self.racePath + "TrackStatus.jsonStream", with: LeakyError(token: Self.token))
        await http.serve(Self.racePath + "WeatherData.jsonStream", status: 403)
        let archive = Self.archive(http)
        let loaded = try #require(await TimingArchive.load(Self.race, using: archive))
        #expect(loaded.missing == ["TrackStatus", "WeatherData"])
        var text = ""
        dump(loaded, to: &text, maxDepth: 3, maxItems: 10_000)
        text += String(describing: loaded.missing) + String(describing: loaded.info) + String(describing: loaded.drivers)
        #expect(!text.contains(Self.token))
        for file in [await archive.file(sessionPath: Self.racePath, name: "TrackStatus.jsonStream"),
                     await archive.file(sessionPath: Self.racePath, name: "WeatherData.jsonStream"),
                     await archive.range(sessionPath: Self.racePath, name: "TrackStatus.jsonStream", bytes: 0...9)] {
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

    @Test func sessionForRefProbesWhenTheIndexLags() async throws {
        // The index without the race, as it is in the hours after one.
        var index = try Fixture.json("Index-2026.json")
        if case .object(var top) = index, case .array(var meetings) = top["Meetings"],
           case .object(var sp) = meetings[1], case .array(let sessions) = sp["Sessions"] {
            sp["Sessions"] = .array(sessions.filter { $0["Name"].string != "Race" })
            meetings[1] = .object(sp)
            top["Meetings"] = .array(meetings)
            index = .object(top)
        }
        let http = FakeArchiveHTTP()
        await http.serve("2026/Index.json", body: try JSONSerialization.data(withJSONObject: Self.plain(index)))
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

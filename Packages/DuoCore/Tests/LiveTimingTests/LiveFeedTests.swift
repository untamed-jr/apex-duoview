import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// The São Paulo race's archive, replayed as live timing would send it.
struct ArchiveReplay {
    static let topics = ["Position.z", "TimingData", "TimingAppData", "SessionStatus", "RaceControlMessages", "TrackStatus",
                         "LapCount", "ExtrapolatedClock", "WeatherData", "TeamRadio", "Heartbeat"]
    let streams: [String: [StreamLine]]
    let driverList: JSONValue
    let sessionInfo: JSONValue
    let start = Fixture.raceStart

    init() throws {
        var streams: [String: [StreamLine]] = [:]
        for topic in Self.topics { streams[topic] = try Fixture.lines("sp26-race/\(topic).jsonStream") }
        self.streams = streams
        driverList = try Fixture.json("sp26-race/DriverList.json")
        sessionInfo = try Fixture.json("sp26-race/SessionInfo.json")
    }

    func utc(_ line: StreamLine) -> UTCms { start + line.offsetMs }

    /// The subscribe result as the archive's first lines: DriverList and SessionInfo whole,
    /// and each topic's first line (its full state), at that line's time.
    var opening: [RecordedMessage] {
        let first = streams[Self.topics[0]]![0]
        return [RecordedMessage(topic: "DriverList", utc: utc(first), opening: true, json: driverList),
                RecordedMessage(topic: "SessionInfo", utc: utc(first), opening: true, json: sessionInfo)]
            + Self.topics.compactMap { topic in
                streams[topic]?.first.map { RecordedMessage(topic: topic, utc: utc($0), opening: true, json: $0.json) }
            }
    }

    /// Every later line as a change, in time order; ties keep the topics' order, then the lines'.
    var changes: [RecordedMessage] {
        var all: [(utc: UTCms, topic: Int, index: Int, message: RecordedMessage)] = []
        for (t, topic) in Self.topics.enumerated() {
            for (i, line) in (streams[topic] ?? []).enumerated().dropFirst() {
                all.append((utc(line), t, i, RecordedMessage(topic: topic, utc: utc(line), opening: false, json: line.json)))
            }
        }
        return all.sorted { ($0.utc, $0.topic, $0.index) < ($1.utc, $1.topic, $1.index) }.map(\.message)
    }

    /// The subscribe result at `utc`: every topic's lines up to `through` merged, F1 style.
    func snapshot(at utc: UTCms, through: UTCms) -> [RecordedMessage] {
        [RecordedMessage(topic: "DriverList", utc: utc, opening: true, json: driverList),
         RecordedMessage(topic: "SessionInfo", utc: utc, opening: true, json: sessionInfo)]
            + Self.topics.map { topic in
                let state = (streams[topic] ?? []).filter { self.utc($0) <= through }
                    .reduce(JSONValue.null) { TopicMerge.merge($0, $1.json) }
                return RecordedMessage(topic: topic, utc: utc, opening: true, json: state)
            }
    }

    static func archiveSession() async throws -> LoadedSession {
        let http = try await TimingArchiveTests.raceHTTP()
        return try #require(await TimingArchive.load(TimingArchiveTests.race, using: TimingArchiveTests.archive(http)))
    }
}

struct LiveFeedTests {
    static let lightsOut = Fixture.raceLightsOut
    /// The fixture's window, 00:51:44.576 to 01:05:44.576, every 20 s.
    static let times: [UTCms] = stride(from: Fixture.raceStart + 3_104_576, through: Fixture.raceStart + 3_944_576, by: 20_000)
        .map { $0 } + [lightsOut, lightsOut + 1, lightsOut + 61_234]
    static let windowEnd = Fixture.raceStart + 3_944_576

    func crossings(_ timing: TimingTimeline) -> [String] {
        timing.lineCrossings(upTo: .max).map { "\($0.car)@\($0.at)" }
    }

    /// The archive's timelines and the feed's agree at every tested time.
    func expectSame(_ live: LoadedSession, _ archive: LoadedSession, at times: [UTCms] = LiveFeedTests.times,
                    sourceLocation: SourceLocation = #_sourceLocation) {
        for t in times {
            #expect(live.timing.at(t) == archive.timing.at(t), "timing at \(t)", sourceLocation: sourceLocation)
            #expect(live.stints.at(t) == archive.stints.at(t), "stints at \(t)", sourceLocation: sourceLocation)
            #expect(live.header.at(t) == archive.header.at(t), "header at \(t)", sourceLocation: sourceLocation)
            #expect(live.flags.at(t) == archive.flags.at(t), "flags at \(t)", sourceLocation: sourceLocation)
            #expect(live.sessionStatus.status(at: t) == archive.sessionStatus.status(at: t), sourceLocation: sourceLocation)
            for (number, car) in archive.positions.cars {
                #expect(live.positions.cars[number]?.at(t) == car.at(t), "car \(number) at \(t)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test func liveFeedMatchesArchiveParsers() async throws {
        let replay = try ArchiveReplay()
        let archive = try await ArchiveReplay.archiveSession()
        var feed = LiveFeed()
        for m in replay.opening + replay.changes { feed.apply(m) }
        let live = try #require(feed.session())

        #expect(feed.joinedAt == replay.opening[0].utc)
        #expect(live.streamStart == replay.opening[0].utc - LiveFeed.headStartMs)
        #expect(live.info == archive.info)
        #expect(live.drivers == archive.drivers)
        #expect(live.missing == archive.missing)
        #expect(live.positions.cars.count == archive.positions.cars.count)
        for (number, car) in archive.positions.cars { #expect(live.positions.cars[number]?.times == car.times) }
        expectSame(live, archive)
        #expect(crossings(live.timing) == crossings(archive.timing))
        #expect(!crossings(archive.timing).isEmpty)
        #expect(live.flags.sectorFlags.count == archive.flags.sectorFlags.count)
        #expect(live.flags.spans == archive.flags.spans)
        // The feed counts the opening snapshot from the stream's start (Android's head start).
        #expect(live.timing.at(live.streamStart) == archive.timing.at(Fixture.raceStart + 10_000))
        #expect(archive.timing.at(live.streamStart).isEmpty)
    }

    @Test func reconnectSnapshotNoDuplicates() async throws {
        let replay = try ArchiveReplay()
        let archive = try await ArchiveReplay.archiveSession()
        let changes = replay.changes
        let reconnect = Self.lightsOut + 180_000
        let k = try #require(changes.firstIndex { $0.utc > reconnect })

        var feed = LiveFeed()
        for m in replay.opening + changes[..<k] { feed.apply(m) }
        let atReconnect = feed.lines("TimingData").count
        for m in replay.snapshot(at: reconnect, through: reconnect) + changes[k...] { feed.apply(m) }
        let live = try #require(feed.session())

        // Nothing the lines already held came again.
        #expect(feed.lines("TimingData").count == atReconnect + changes[k...].filter { $0.topic == "TimingData" }.count)
        expectSame(live, archive)
        #expect(crossings(live.timing) == crossings(archive.timing))
        #expect(live.flags.sectorFlags.count == archive.flags.sectorFlags.count)
        #expect(live.flags.spans == archive.flags.spans)
        #expect(live.timing.at(Self.windowEnd).mapValues(\.numberOfLaps) == archive.timing.at(Self.windowEnd).mapValues(\.numberOfLaps))

        // The same snapshot taken as changes (Android after a drop) doubles race control.
        var android = LiveFeed()
        for m in replay.opening + changes[..<k] { android.apply(m) }
        for var m in replay.snapshot(at: reconnect, through: reconnect) {
            m.opening = false
            android.apply(m)
        }
        for m in changes[k...] { android.apply(m) }
        let doubled = try #require(android.session())
        #expect(doubled.flags.sectorFlags.count > archive.flags.sectorFlags.count)
    }

    @Test func reconnectAfterMissedChangesCountsEachOnce() async throws {
        let replay = try ArchiveReplay()
        let archive = try await ArchiveReplay.archiveSession()
        let dropped = Self.lightsOut + 120_000
        let back = Self.lightsOut + 300_000
        var feed = LiveFeed()
        for m in replay.opening + replay.changes.filter({ $0.utc <= dropped }) { feed.apply(m) }
        for m in replay.snapshot(at: back, through: back) + replay.changes.filter({ $0.utc > back }) { feed.apply(m) }
        let live = try #require(feed.session())

        // Laps crossed while disconnected show once, at the reconnect; none twice.
        let lost = crossings(archive.timing).filter { entry in
            let at = UTCms(entry.split(separator: "@")[1])!
            return dropped < at && at <= back
        }
        #expect(!lost.isEmpty)
        let live1 = crossings(live.timing).filter { !$0.hasSuffix("@\(back)") }
        #expect(live1 == crossings(archive.timing).filter { !lost.contains($0) })
        let atReconnect = crossings(live.timing).filter { $0.hasSuffix("@\(back)") }.map { $0.split(separator: "@")[0] }
        #expect(Set(atReconnect).count == atReconnect.count)
        #expect(Set(atReconnect) == Set(lost.map { $0.split(separator: "@")[0] }))
        // Race control's messages carry their own times: none lost, none doubled.
        #expect(live.flags.sectorFlags.count == archive.flags.sectorFlags.count)
        for t in Self.times where t > back {
            let a = archive.timing.at(t), l = live.timing.at(t)
            #expect(l.mapValues(\.numberOfLaps) == a.mapValues(\.numberOfLaps), "laps at \(t)")
            #expect(l.mapValues(\.position) == a.mapValues(\.position), "positions at \(t)")
            #expect(l.mapValues(\.bestLapMs) == a.mapValues(\.bestLapMs), "best laps at \(t)")
            #expect(live.stints.at(t) == archive.stints.at(t), "stints at \(t)")
            #expect(live.header.at(t) == archive.header.at(t), "header at \(t)")
        }
    }

    @Test func backToBackSnapshotsAndStaleTopics() throws {
        func m(_ topic: String, _ utc: UTCms, _ json: String, opening: Bool = true) throws -> RecordedMessage {
            RecordedMessage(topic: topic, utc: utc, opening: opening, json: try JSONValue.parse(Data(json.utf8)))
        }
        let info = #"{"Key":11412,"Type":"Race","Name":"Race","Path":"2026/x/","GmtOffset":"-03:00:00"}"#
        let t0: UTCms = 1_794_157_000_000  // 16:56:40 UTC
        var feed = LiveFeed()
        for msg in try [
            m("DriverList", t0, #"{"1":{"RacingNumber":"1","Tla":"VER"},"4":{"RacingNumber":"4","Tla":"NOR"}}"#),
            m("SessionInfo", t0, info),
            m("WeatherData", t0, #"{"AirTemp":"20.0","TrackTemp":"35.0","Rainfall":"0"}"#),
            m("RaceControlMessages", t0, #"{"Messages":[{"Utc":"2026-11-08T16:56:40","Flag":"YELLOW","Scope":"Sector","Sector":3}]}"#),
            // Straight into the next snapshot, with no change between: a topic named again.
            m("DriverList", t0 + 1_000, #"{"1":{"RacingNumber":"1","Tla":"VER"},"4":{"RacingNumber":"4","Tla":"NOR"},"81":{"RacingNumber":"81","Tla":"PIA"}}"#),
            m("SessionInfo", t0 + 1_000, info),
            m("WeatherData", t0 + 1_000, #"{"AirTemp":"20.0","TrackTemp":"35.0","Rainfall":"0"}"#),
            m("RaceControlMessages", t0 + 1_000, #"{"Messages":[{"Utc":"2026-11-08T16:56:40","Flag":"YELLOW","Scope":"Sector","Sector":3}]}"#),
            m("WeatherData", t0 + 30_000, #"{"AirTemp":"21.0"}"#, opening: false),
        ] { feed.apply(msg) }
        #expect(Set(try #require(feed.session()).drivers.keys) == ["1", "4", "81"])
        #expect(feed.lines("RaceControlMessages").count == 1)
        #expect(feed.lines("WeatherData").count == 2)

        // A reconnect: DriverList without car 1, no WeatherData or race control.
        for msg in try [m("DriverList", t0 + 60_000, #"{"4":{"RacingNumber":"4","Tla":"NOR"},"81":{"RacingNumber":"81","Tla":"PIA"}}"#),
                        m("SessionInfo", t0 + 60_000, info)] { feed.apply(msg) }
        #expect(feed.state.topics["WeatherData"] == nil)
        #expect(feed.state.topics["RaceControlMessages"] == nil)
        #expect(Set(feed.state.topics.keys) == ["DriverList", "SessionInfo"])
        let live = try #require(feed.session())
        #expect(Set(live.drivers.keys) == ["4", "81"])
        // What happened before stays history.
        #expect(live.header.at(t0 + 40_000).airTemp == 21.0)
        #expect(live.flags.at(t0 + 40_000).yellowSectors == [3: 1])
        #expect(live.missing == ["TimingData", "TimingAppData", "TrackStatus", "SessionStatus", "LapCount", "ExtrapolatedClock"])
        // The DriverList's lines (unused by the parsers) hold the change, once.
        #expect(feed.lines("DriverList").count == 3)
        #expect(feed.lines("DriverList").last?.json == .object(["_deleted": .array([.string("1")])]))
    }

    @Test func changesBeforeTheFirstSnapshotAreDropped() throws {
        var feed = LiveFeed()
        feed.apply(RecordedMessage(topic: "LapCount", utc: 1_000, opening: false, json: .object(["CurrentLap": .number(3)])))
        #expect(feed.streamStart == nil)
        #expect(feed.session() == nil)
        #expect(feed.lines("LapCount").isEmpty)
        feed.apply(RecordedMessage(topic: "LapCount", utc: 2_000, opening: true, json: .object(["CurrentLap": .number(3), "TotalLaps": .number(71)])))
        feed.apply(RecordedMessage(topic: "LapCount", utc: 3_000, opening: false, json: .object(["CurrentLap": .number(4)])))
        #expect(feed.streamStart == 2_000 - LiveFeed.headStartMs)
        #expect(feed.lines("LapCount").map(\.offsetMs) == [0, LiveFeed.headStartMs + 1_000])
        // No SessionInfo yet: no session, unless the caller gives it.
        #expect(feed.session() == nil)
        let info = TimingSessionInfo(key: 1, name: "Race", type: "Race", path: "x/", start: nil, gmtOffsetSeconds: 0,
                                     circuitKey: nil, meetingName: "", year: nil)
        let session = try #require(feed.session(drivers: ["4": DriverInfo(number: "4", tla: "NOR", firstName: "", lastName: "", teamName: "", teamColour: "")], info: info))
        #expect(session.header.at(2_500).lap == 3)
        #expect(session.header.at(3_000).lap == 4)
        #expect(session.drivers.keys.sorted() == ["4"])
        #expect(session.positions.cars.isEmpty)
    }

    @Test func offsetsNeverGoBack() throws {
        var feed = LiveFeed()
        let lap = { (n: Int, utc: UTCms, opening: Bool) in
            RecordedMessage(topic: "LapCount", utc: utc, opening: opening, json: .object(["CurrentLap": .number(Double(n))]))
        }
        feed.apply(lap(1, 10_000, true))
        feed.apply(lap(2, 20_000, false))
        // The phone's clock, stamping the next snapshot, runs behind F1's.
        feed.apply(lap(3, 15_000, true))
        feed.apply(lap(4, 21_000, false))
        let offsets = feed.lines("LapCount").map(\.offsetMs)
        #expect(offsets == [0, LiveFeed.headStartMs + 10_000, LiveFeed.headStartMs + 10_000, LiveFeed.headStartMs + 11_000])
    }

    @Test func excludedTopicsIgnoredAndRecordingRebuildsTheFeed() throws {
        let replay = try ArchiveReplay()
        let messages = replay.opening + replay.changes.prefix(4_000)
        var live = LiveFeed()
        for m in messages { live.apply(m) }
        live.apply(RecordedMessage(topic: "CarData.z", utc: replay.start + 3_200_000, opening: false, json: .string("x")))
        #expect(live.lines("Heartbeat").isEmpty)
        #expect(live.lines("CarData.z").isEmpty)
        #expect(live.state.topics["Heartbeat"] == nil)

        let file = Data((LiveRecording.header(sessionPath: "2026/x/") + LiveRecording.lines(messages)).utf8)
        let rebuilt = LiveFeed(LiveRecording.read(file).messages)
        for topic in ArchiveReplay.topics + ["DriverList", "SessionInfo"] {
            #expect(rebuilt.lines(topic) == live.lines(topic), "\(topic)")
        }
        #expect(rebuilt.state.topics == live.state.topics)
        #expect(rebuilt.joinedAt == live.joinedAt)
    }

    @Test func topUpPutsTheArchiveBeforeTheJoin() async throws {
        let replay = try ArchiveReplay()
        let archive = try await ArchiveReplay.archiveSession()
        let joined = Self.lightsOut + 240_000
        var feed = LiveFeed()
        for m in replay.snapshot(at: joined, through: joined) + replay.changes.filter({ $0.utc > joined }) { feed.apply(m) }
        #expect(feed.joinedAt == joined)
        let before = try #require(feed.session())
        // Before the join, the opening state stands in for everything.
        #expect(before.timing.at(Self.lightsOut + 60_000).mapValues(\.numberOfLaps) == archive.timing.at(joined).mapValues(\.numberOfLaps))
        #expect(before.timing.at(Self.lightsOut + 60_000).mapValues(\.numberOfLaps) != archive.timing.at(Self.lightsOut + 60_000).mapValues(\.numberOfLaps))

        // An archive that lags: up to 5 minutes before the join.
        let lagging = replay.streams.mapValues { $0.filter { replay.utc($0) <= joined - 300_000 } }
        var partial = feed
        partial.topUp(archive: lagging, archiveStart: replay.start)
        let early = try #require(partial.session())
        // Up to the archive's end, less the last seconds, where a car's next sample is missing.
        expectSame(early, archive, at: Self.times.filter { $0 < joined - 310_000 })
        for t in Self.times where t >= joined {
            #expect(early.timing.at(t).mapValues(\.numberOfLaps) == archive.timing.at(t).mapValues(\.numberOfLaps), "laps at \(t)")
            #expect(early.timing.at(t).mapValues(\.position) == archive.timing.at(t).mapValues(\.position), "positions at \(t)")
            #expect(early.stints.at(t) == archive.stints.at(t), "stints at \(t)")
        }
        #expect(early.flags.sectorFlags.count == archive.flags.sectorFlags.count)
        let laggingLast = try #require(Backfill.archiveLast(PositionSeries.parse(lines: lagging["Position.z"] ?? [])))
        #expect(!Backfill.isComplete(archiveLast: laggingLast, joinedAt: joined))

        // The whole archive: the same session as the replay's, before the join and after.
        feed.topUp(archive: replay.streams, archiveStart: replay.start)
        let full = try #require(feed.session())
        expectSame(full, archive)
        #expect(crossings(full.timing) == crossings(archive.timing))
        #expect(full.flags.sectorFlags.count == archive.flags.sectorFlags.count)
        #expect(full.flags.spans == archive.flags.spans)
        #expect(Backfill.isComplete(archiveLast: try #require(Backfill.archiveLast(full.positions)), joinedAt: joined))
    }

    @Test func topUpWhenTheSnapshotIsOlderThanItsStamp() async throws {
        let replay = try ArchiveReplay()
        let archive = try await ArchiveReplay.archiveSession()
        // A car crosses the line a second before the snapshot arrives, but the snapshot's state
        // is from 3 s before that: the crossing comes as a change after it.
        let crossing = try #require(archive.timing.lineCrossings(upTo: .max).map(\.at).filter { $0 > Self.lightsOut + 240_000 }.min())
        let joined = crossing + 1_000
        let state = joined - 3_000
        var feed = LiveFeed()
        for m in replay.snapshot(at: joined, through: state) + replay.changes.filter({ $0.utc > state }) { feed.apply(m) }
        feed.topUp(archive: replay.streams, archiveStart: replay.start)
        let live = try #require(feed.session())
        #expect(crossings(live.timing) == crossings(archive.timing))
        #expect(live.flags.sectorFlags.count == archive.flags.sectorFlags.count)
        expectSame(live, archive)
    }

    @Test func topUpWhenTheSnapshotIsNewerThanItsStamp() async throws {
        let replay = try ArchiveReplay()
        let archive = try await ArchiveReplay.archiveSession()
        // The phone's clock runs 2 s behind the archive's: the snapshot is stamped 2 s before
        // the state it holds, and a lap and a race control CLEAR fall between the two.
        let crossing = try #require(archive.timing.lineCrossings(upTo: .max).map(\.at).filter { $0 > Self.lightsOut + 240_000 }.min())
        // The fixture's only CLEARs are at 00:28:19, clearing the sectors' yellows.
        let control = try #require(replay.streams["RaceControlMessages"])
        let clear = try #require(control.first { F1Values.ordered($0.json["Messages"]).contains { $0["Flag"].string == "CLEAR" } }.map(replay.utc))
        for joined in [crossing - 1_000, clear - 1_000] {
            let state = joined + 2_000
            var feed = LiveFeed()
            for m in replay.snapshot(at: joined, through: state) + replay.changes.filter({ $0.utc > state }) { feed.apply(m) }
            feed.topUp(archive: replay.streams, archiveStart: replay.start)
            let live = try #require(feed.session())
            #expect(crossings(live.timing) == crossings(archive.timing), "joined \(joined)")
            #expect(live.flags.sectorFlags.count == archive.flags.sectorFlags.count, "joined \(joined)")
            #expect(TrackFlags.controlMessages(feed.lines("RaceControlMessages"), streamStart: live.streamStart).count
                    == TrackFlags.controlMessages(control, streamStart: replay.start).count, "joined \(joined)")
            expectSame(live, archive)
        }
    }

    @Test func topUpListsEachRaceControlMessageOnce() throws {
        func j(_ s: String) throws -> JSONValue { try JSONValue.parse(Data(s.utf8)) }
        let t0: UTCms = 1_794_157_000_000  // 16:56:40 UTC
        let yellow = #"{"Utc":"2026-11-08T16:55:40","Category":"Flag","Flag":"YELLOW","Scope":"Sector","Sector":3,"Message":"YELLOW IN TRACK SECTOR 3"}"#
        let clear = #"{"Utc":"2026-11-08T16:56:37","Category":"Flag","Flag":"CLEAR","Scope":"Sector","Sector":3,"Message":"CLEAR IN TRACK SECTOR 3"}"#
        var feed = LiveFeed()
        feed.apply(RecordedMessage(topic: "SessionInfo", utc: t0, opening: true,
                                   json: try j(#"{"Key":11412,"Type":"Race","Name":"Race","Path":"2026/x/"}"#)))
        feed.apply(RecordedMessage(topic: "RaceControlMessages", utc: t0, opening: true, json: try j(#"{"Messages":[\#(yellow)]}"#)))
        // The CLEAR comes live by F1's clock, before the snapshot's stamp, under another index.
        feed.apply(RecordedMessage(topic: "RaceControlMessages", utc: t0 - 2_000, opening: false, json: try j(#"{"Messages":{"5":\#(clear)}}"#)))
        let start = try #require(feed.streamStart)
        // The archive has both, and by its clock the CLEAR is earlier still.
        let archive = [StreamLine(offsetMs: 0, json: try j(#"{"Messages":[\#(yellow)]}"#)),
                       StreamLine(offsetMs: 57_500, json: try j(#"{"Messages":{"1":\#(clear)}}"#))]
        let archiveStart = t0 - 60_000
        feed.topUp(archive: ["RaceControlMessages": archive], archiveStart: archiveStart)
        let messages = TrackFlags.controlMessages(feed.lines("RaceControlMessages"), streamStart: start)
        #expect(messages.map { $0.message["Flag"].string }.sorted() == ["CLEAR", "YELLOW"])
        let session = try #require(feed.session())
        #expect(session.flags.at(t0 - 30_000).yellowSectors == [3: 1])
        #expect(session.flags.at(t0).yellowSectors.isEmpty)
    }

    /// Car 3 at a join at `seamJoin`, for the seam's edge cases: a live feed (snapshot, then
    /// changes) topped up from an archive starting `archiveStart`, lines as (time, JSON).
    static let seamJoin: UTCms = 1_794_157_000_000

    func seamFeed(snapshot: String, changes: [(UTCms, String)], archive: [(UTCms, String)]) throws -> LiveFeed {
        func j(_ s: String) throws -> JSONValue { try JSONValue.parse(Data(s.utf8)) }
        let join = Self.seamJoin
        var feed = LiveFeed()
        feed.apply(RecordedMessage(topic: "SessionInfo", utc: join, opening: true,
                                   json: try j(#"{"Key":11412,"Type":"Race","Name":"Race","Path":"2026/x/"}"#)))
        feed.apply(RecordedMessage(topic: "TimingData", utc: join, opening: true, json: try j(snapshot)))
        for (t, json) in changes { feed.apply(RecordedMessage(topic: "TimingData", utc: t, opening: false, json: try j(json))) }
        let archiveStart = join - 100_000
        feed.topUp(archive: ["TimingData": try archive.map { StreamLine(offsetMs: $0.0 - archiveStart, json: try j($0.1)) }],
                   archiveStart: archiveStart)
        return feed
    }

    func carCrossings(_ feed: LiveFeed) throws -> [UTCms] {
        try #require(feed.session()).timing.lineCrossings(upTo: .max).filter { $0.car == "3" }.map(\.at)
    }

    func laps(_ feed: LiveFeed, at t: UTCms) throws -> Int? {
        try #require(feed.session()).timing.state(of: "3", at: t)?.numberOfLaps
    }

    @Test func topUpFromAnArchiveEndingJustBeforeTheJoin() throws {
        let join = Self.seamJoin
        let first = #"{"Lines":{"3":{"NumberOfLaps":10,"Position":"3","Status":80}}}"#
        let status64 = #"{"Lines":{"3":{"Status":64}}}"#
        let crossed = #"{"Lines":{"3":{"NumberOfLaps":11}}}"#
        let status80 = #"{"Lines":{"3":{"Status":80}}}"#
        // The archive ends 10 s before the join (complete, by Backfill's 30 s), and the first
        // live change repeats a line it has from 25 s earlier: the archive doesn't reach the
        // change, so that line isn't it.
        let complete = try seamFeed(
            snapshot: #"{"Lines":{"3":{"NumberOfLaps":11,"Position":"3","Status":80}}}"#,
            changes: [(join + 5_000, status64)],
            archive: [(join - 100_000, first), (join - 20_000, status64), (join - 15_000, crossed), (join - 10_000, status80)])
        #expect(try carCrossings(complete) == [join - 15_000])
        #expect(try laps(complete, at: join - 16_000) == 10)
        #expect(try laps(complete, at: join + 6_000) == 11)
        #expect(complete.lines("TimingData").count == 5)

        // The archive ends 10 s short, and a lap was crossed after it: the snapshot's state
        // brings it, once, at the join.
        let short = try seamFeed(
            snapshot: #"{"Lines":{"3":{"NumberOfLaps":12,"Position":"3","Status":80}}}"#,
            changes: [(join + 5_000, status64)],
            archive: [(join - 100_000, first), (join - 20_000, status64), (join - 15_000, crossed), (join - 10_000, status80)])
        #expect(try carCrossings(short) == [join - 15_000, join])
        #expect(try laps(short, at: join + 6_000) == 12)

        // The archive lacks the change's copy and holds an earlier one, 20 s before. Whether it
        // reaches past the change, ends 1 s short of it, or ends 0.3 s short (inside the
        // tolerance), the match doesn't check out: every archive line keeps its own time, the
        // lap is crossed once, when it was, and never shows before.
        let snapshot = #"{"Lines":{"3":{"NumberOfLaps":11,"Position":"3","Status":80}}}"#
        let cases: [(change: UTCms, archive: [(UTCms, String)])] = [
            (join + 5_000, [(join - 100_000, first), (join - 20_000, status64), (join - 15_000, crossed), (join - 10_000, status80),
                            (join + 10_000, #"{"Lines":{"3":{"Position":"3"}}}"#)]),
            (join + 500, [(join - 100_000, first), (join - 20_000, status64), (join - 15_000, crossed), (join - 500, status80)]),
            (join + 200, [(join - 100_000, first), (join - 20_000, status64), (join - 15_000, crossed), (join - 100, status80)]),
        ]
        for (change, archive) in cases {
            let wrong = try seamFeed(snapshot: snapshot, changes: [(change, status64)], archive: archive)
            #expect(try carCrossings(wrong) == [join - 15_000], "change at \(change - join)")
            #expect(try laps(wrong, at: join - 18_000) == 10, "change at \(change - join)")
            #expect(try laps(wrong, at: join - 15_000) == 11, "change at \(change - join)")
            #expect(try laps(wrong, at: change + 1_000) == 11, "change at \(change - join)")
            // Every archive line before the join is there (Status 64 at −20 s and 80 at the
            // end, which cancel out, included), and nothing else is.
            let start = try #require(wrong.streamStart)
            #expect(wrong.lines("TimingData").filter { $0.offsetMs < LiveFeed.headStartMs }
                .map { $0.offsetMs + start } == archive.map(\.0).filter { $0 < join }, "change at \(change - join)")
        }
    }

    @Test func topUpMatchingAnEarlierCopyAtTheArchivesFirstLine() throws {
        let join = Self.seamJoin
        let status64 = #"{"Lines":{"3":{"Status":64}}}"#
        // The archive starts with an earlier copy of the first live change, then goes on
        // before the change: not the change itself, so its lines are kept at their times.
        let feed = try seamFeed(
            snapshot: #"{"Lines":{"3":{"NumberOfLaps":11,"Position":"3","Status":80}}}"#,
            changes: [(join + 5_000, status64)],
            archive: [(join - 20_000, status64),
                      (join - 15_000, #"{"Lines":{"3":{"NumberOfLaps":11}}}"#),
                      (join - 10_000, #"{"Lines":{"3":{"Status":80}}}"#),
                      (join + 10_000, #"{"Lines":{"3":{"Position":"3"}}}"#)])
        #expect(try carCrossings(feed) == [join - 15_000])
        #expect(try laps(feed, at: join - 18_000) == nil)
        #expect(try laps(feed, at: join - 15_000) == 11)
        #expect(try laps(feed, at: join + 6_000) == 11)
        let start = try #require(feed.streamStart)
        #expect(feed.lines("TimingData").prefix(3).map { $0.offsetMs + start } == [join - 20_000, join - 15_000, join - 10_000])
    }

    @Test func topUpMatchingTheArchivesFirstLine() throws {
        let join = Self.seamJoin
        // The snapshot is older than its stamp: a lap comes live 2 s before it, and the archive,
        // its clock half a second earlier, starts with that very line.
        let crossed = #"{"Lines":{"3":{"NumberOfLaps":11}}}"#
        let feed = try seamFeed(
            snapshot: #"{"Lines":{"3":{"NumberOfLaps":10,"Position":"3"}}}"#,
            changes: [(join - 2_000, crossed), (join + 10_000, #"{"Lines":{"3":{"Position":"2"}}}"#)],
            archive: [(join - 2_500, crossed), (join + 10_000, #"{"Lines":{"3":{"Position":"2"}}}"#)])
        // Nothing before it in the archive: the live lines stand, nothing twice, nothing back.
        #expect(feed.lines("TimingData").count == 3)
        #expect(try laps(feed, at: join - 2_400) == 10)
        #expect(try laps(feed, at: join) == 11)
        #expect(try carCrossings(feed) == [join - 2_000])
    }

    @Test func topicFirstNamedLaterIsNotBackdated() throws {
        func m(_ topic: String, _ utc: UTCms, _ json: String, opening: Bool = true) throws -> RecordedMessage {
            RecordedMessage(topic: topic, utc: utc, opening: opening, json: try JSONValue.parse(Data(json.utf8)))
        }
        let t0: UTCms = 1_794_157_000_000
        let reconnect = t0 + 2_400_000
        let info = #"{"Key":11412,"Type":"Race","Name":"Race","Path":"2026/x/"}"#
        func feed() throws -> LiveFeed {
            var feed = LiveFeed()
            for msg in try [
                m("SessionInfo", t0, info),
                m("LapCount", t0, #"{"CurrentLap":1,"TotalLaps":71}"#),
                m("LapCount", t0 + 10_000, #"{"CurrentLap":2}"#, opening: false),
                // WeatherData named for the first time 40 minutes in.
                m("SessionInfo", reconnect, info),
                m("LapCount", reconnect, #"{"CurrentLap":30,"TotalLaps":71}"#),
                m("WeatherData", reconnect, #"{"AirTemp":"20.0","TrackTemp":"35.0","Rainfall":"0"}"#),
                m("WeatherData", reconnect + 60_000, #"{"AirTemp":"21.0"}"#, opening: false),
            ] { feed.apply(msg) }
            return feed
        }
        var live = try feed()
        let start = try #require(live.streamStart)
        #expect(live.lines("WeatherData").first?.offsetMs == reconnect - start)
        let session = try #require(live.session())
        #expect(session.header.at(t0 + 100_000).airTemp == nil)
        #expect(session.header.at(reconnect).airTemp == 20.0)
        #expect(session.header.at(reconnect + 60_000).airTemp == 21.0)
        #expect(session.header.at(t0 + 100_000).lap == 2)

        // Topped up from an archive that lags behind the reconnect: its readings, then the
        // difference to the snapshot's at its own time.
        func w(_ t: UTCms, _ json: String) throws -> StreamLine {
            StreamLine(offsetMs: t - t0, json: try JSONValue.parse(Data(json.utf8)))
        }
        live.topUp(archive: ["WeatherData": [try w(t0 - 30_000, #"{"AirTemp":"18.0","TrackTemp":"30.0","Rainfall":"0"}"#),
                                             try w(t0 + 1_200_000, #"{"AirTemp":"19.0"}"#)]], archiveStart: t0)
        let lagging = try #require(live.session())
        #expect(lagging.header.at(t0 + 100_000).airTemp == 18.0)
        #expect(lagging.header.at(t0 + 1_300_000).airTemp == 19.0)
        #expect(lagging.header.at(reconnect).airTemp == 20.0)
        #expect(lagging.header.at(reconnect).trackTemp == 35.0)
        #expect(lagging.header.at(reconnect + 60_000).airTemp == 21.0)

        // A fuller archive, holding the live change: one stream, the snapshot's line left out.
        var full = try feed()
        full.topUp(archive: ["WeatherData": [try w(t0 - 30_000, #"{"AirTemp":"18.0","TrackTemp":"30.0","Rainfall":"0"}"#),
                                             try w(reconnect - 30_000, #"{"AirTemp":"20.0","TrackTemp":"35.0"}"#),
                                             try w(reconnect + 60_000, #"{"AirTemp":"21.0"}"#)]], archiveStart: t0)
        #expect(full.lines("WeatherData").map(\.offsetMs) == [t0 - 30_000 - start, reconnect - 30_000 - start, reconnect + 60_000 - start])
        #expect(try #require(full.session()).header.at(reconnect - 10_000).airTemp == 20.0)
    }

    @Test func newSessionPathStartsAfresh() throws {
        func m(_ topic: String, _ utc: UTCms, _ json: String, opening: Bool = true) throws -> RecordedMessage {
            RecordedMessage(topic: topic, utc: utc, opening: opening, json: try JSONValue.parse(Data(json.utf8)))
        }
        let sprint = #"{"Key":11410,"Type":"Race","Name":"Sprint","Path":"2026/sprint/"}"#
        let race = #"{"Key":11412,"Type":"Race","Name":"Race","Path":"2026/race/"}"#
        let t0: UTCms = 1_794_157_000_000
        var feed = LiveFeed()
        for msg in try [
            m("DriverList", t0, #"{"1":{"RacingNumber":"1","Tla":"VER"}}"#),
            m("LapCount", t0, #"{"CurrentLap":20,"TotalLaps":24}"#),
            m("SessionInfo", t0, sprint),
            m("LapCount", t0 + 60_000, #"{"CurrentLap":21}"#, opening: false),
            // Same session, again: carried on.
            m("SessionInfo", t0 + 70_000, sprint, opening: false),
        ] { feed.apply(msg) }
        #expect(feed.sessionPath == "2026/sprint/")
        #expect(feed.lines("LapCount").count == 2)

        // The app reconnects the next day to the race: its snapshot names the new path after
        // two of its topics.
        let t1 = t0 + 86_400_000
        for msg in try [
            m("DriverList", t1, #"{"4":{"RacingNumber":"4","Tla":"NOR"}}"#),
            m("LapCount", t1, #"{"CurrentLap":1,"TotalLaps":71}"#),
            m("SessionInfo", t1, race),
            m("LapCount", t1 + 90_000, #"{"CurrentLap":2}"#, opening: false),
        ] { feed.apply(msg) }
        #expect(feed.sessionPath == "2026/race/")
        #expect(feed.joinedAt == t1)
        #expect(feed.lines("LapCount").map(\.offsetMs) == [0, LiveFeed.headStartMs + 90_000])
        let session = try #require(feed.session())
        #expect(session.info.path == "2026/race/")
        #expect(Set(session.drivers.keys) == ["4"])
        #expect(session.header.at(t1).totalLaps == 71)

        // A new path as a change: nothing kept, and nothing until the next snapshot.
        feed.apply(try m("SessionInfo", t1 + 100_000, #"{"Path":"2026/post/"}"#, opening: false))
        #expect(feed.sessionPath == "2026/post/")
        #expect(feed.streamStart == nil)
        #expect(feed.session() == nil)
        feed.apply(try m("LapCount", t1 + 110_000, #"{"CurrentLap":3}"#, opening: false))
        #expect(feed.lines("LapCount").isEmpty)
        feed.apply(try m("SessionInfo", t1 + 120_000, #"{"Key":1,"Type":"Practice","Name":"Post","Path":"2026/post/"}"#))
        #expect(feed.joinedAt == t1 + 120_000)
        #expect(feed.session()?.info.path == "2026/post/")
    }

    @Test func topicPatchRebuildsTheNewState() throws {
        func j(_ s: String) throws -> JSONValue { try JSONValue.parse(Data(s.utf8)) }
        let cases: [(String, String)] = [
            (#"{"a":1,"b":{"c":[1,2,3]}}"#, #"{"a":1,"b":{"c":[1,5,3,4]}}"#),
            (#"{"a":1,"b":2}"#, #"{"a":1}"#),
            (#"{"a":[1,2,3]}"#, #"{"a":[1]}"#),
            (#"{"a":[1,2]}"#, #"{"a":{"x":1}}"#),
            (#"{"a":[1,2]}"#, #"{"a":{"0":1}}"#),
            (#"{"a":[[1],[2]]}"#, #"{"a":[[1],{"0":2}]}"#),
            (#"{"a":{"x":1}}"#, #"{"a":[1,2]}"#),
            (#"{"a":1}"#, #"{"a":null}"#),
            (#"{"a":null}"#, #"{}"#),
            (#"{"a":{"b":{"c":1,"d":2}}}"#, #"{"a":{"b":{"d":3}}}"#),
            (#"{"Messages":[{"m":1}]}"#, #"{"Messages":[{"m":1},{"m":2}]}"#),
            (#""abc""#, #""abd""#),
            (#"[1,2]"#, #"[3]"#),
            (#"{"x":1}"#, #"[1,2]"#),
        ]
        for (old, new) in cases {
            let o = try j(old), n = try j(new)
            let patch = try #require(TopicPatch.delta(from: o, to: n), "\(old) -> \(new)")
            #expect(TopicMerge.merge(o, patch) == n, "\(old) -> \(new)")
        }
        // A list whose first entries came as changes, then whole in a snapshot: only the new
        // entry is sent, and the list stays index-keyed.
        let indexed = try j(#"{"Messages":{"0":{"m":1}}}"#)
        let whole = try j(#"{"Messages":[{"m":1},{"m":2}]}"#)
        #expect(try TopicPatch.delta(from: indexed, to: whole) == j(#"{"Messages":{"1":{"m":2}}}"#))
        #expect(try TopicMerge.merge(indexed, #require(TopicPatch.delta(from: indexed, to: whole))) == j(#"{"Messages":{"0":{"m":1},"1":{"m":2}}}"#))
        #expect(TopicPatch.delta(from: indexed, to: try j(#"{"Messages":[{"m":1}]}"#)) == nil)
        let shrunk = try #require(TopicPatch.delta(from: try j(#"{"L":{"0":1,"1":2,"2":3}}"#), to: try j(#"{"L":[1]}"#)))
        #expect(try TopicMerge.merge(j(#"{"L":{"0":1,"1":2,"2":3}}"#), shrunk) == j(#"{"L":{"0":1}}"#))
        // At the top, an array becoming an object has no parent to replace it in: the whole new
        // state is the best there is (F1's topics are objects, or Position's string).
        #expect(try TopicPatch.delta(from: j("[1,2]"), to: j(#"{"x":1}"#)) == j(#"{"x":1}"#))
        #expect(TopicPatch.delta(from: try j(#"{"a":[1,{"b":2}]}"#), to: try j(#"{"a":[1,{"b":2}]}"#)) == nil)
        #expect(try TopicPatch.delta(from: j(#"{"Messages":[{"m":1}]}"#), to: j(#"{"Messages":[{"m":1},{"m":2}]}"#))
                == j(#"{"Messages":{"1":{"m":2}}}"#))

        // The race's TimingData and TimingAppData states, minutes apart.
        for topic in ["TimingData", "TimingAppData", "RaceControlMessages"] {
            let lines = try Fixture.lines("sp26-race/\(topic).jsonStream")
            var states: [JSONValue] = [.null]
            var state = JSONValue.null
            for (i, line) in lines.enumerated() {
                state = TopicMerge.merge(state, line.json)
                if i % max(lines.count / 6, 1) == 0 || i == lines.count - 1 { states.append(state) }
            }
            for (a, b) in zip(states, states.dropFirst()) {
                let patch = TopicPatch.delta(from: a, to: b)
                #expect(patch.map { TopicMerge.merge(a, $0) } ?? a == b, "\(topic)")
                #expect(TopicPatch.delta(from: b, to: a).map { TopicMerge.merge(b, $0) } ?? b == a, "\(topic) backwards")
            }
        }
    }
}

import Testing
import Foundation
import F1TV
@testable import LiveTiming

/// The São Paulo 2026 fixtures with every stream the race calculations read: TimingData,
/// TimingAppData, LapCount, TrackStatus, RaceControlMessages and SessionStatus (`FixtureSession`
/// leaves flags, header and status empty). With `cutAt`, every stream stops there, so a result
/// from a cut session is what the app could know at that moment: the no-spoiler tests compare it
/// with the full session's at the same time. None of these calculations reads positions.
enum RaceFixture {
    static let loadedRace: LoadedSession? = try? load("sp26-race", streamStart: Fixture.raceStart)
    static let loadedQuali: LoadedSession? = try? load("sp26-quali", streamStart: Fixture.qualiStart)

    static func race() throws -> LoadedSession { try #require(loadedRace) }
    static func quali() throws -> LoadedSession { try #require(loadedQuali) }

    static func load(_ folder: String, streamStart: UTCms, cutAt: UTCms? = nil) throws -> LoadedSession {
        func stream(_ name: String, optional: Bool = false) throws -> [StreamLine] {
            let all: [StreamLine]
            do { all = try Fixture.lines("\(folder)/\(name).jsonStream") } catch is FixtureMissing where optional { return [] }
            guard let cutAt else { return all }
            return all.filter { F1Values.add(streamStart, $0.offsetMs) <= cutAt }
        }
        let info = try #require(TimingSessionInfo.parse(try Fixture.json("\(folder)/SessionInfo.json")))
        return LoadedSession(
            info: info,
            drivers: Drivers.parse(try Fixture.json("\(folder)/DriverList.json")),
            streamStart: streamStart,
            positions: PositionSeries(cars: [:]),
            timing: TimingTimeline.build(lines: try stream("TimingData"), streamStart: streamStart),
            stints: StintTimeline.build(lines: try stream("TimingAppData"), streamStart: streamStart),
            header: HeaderTimeline.build(lapCount: try stream("LapCount", optional: true), clock: [], weather: [],
                                         streamStart: streamStart),
            flags: TrackFlags.build(trackStatus: try stream("TrackStatus"), raceControl: try stream("RaceControlMessages"),
                                    streamStart: streamStart, gmtOffsetSeconds: info.gmtOffsetSeconds),
            sessionStatus: SessionStatusTimeline.build(lines: try stream("SessionStatus"), streamStart: streamStart),
            missing: []
        )
    }

    /// A session from hand-written lines (timed from `start`), with no positions.
    static func synthetic(type: String = "Race", timing: [StreamLine], trackStatus: [StreamLine] = [],
                          sessionStatus: [StreamLine] = [], lapCount: [StreamLine] = [],
                          drivers: [String: DriverInfo] = [:], stints: [StreamLine] = [],
                          start: UTCms = 1_000_000) -> LoadedSession {
        LoadedSession(
            info: TimingSessionInfo(key: 1, name: type, type: type, path: "x/", start: start, gmtOffsetSeconds: 0,
                                    circuitKey: 14, meetingName: "Test", year: 2026),
            drivers: drivers,
            streamStart: start,
            positions: PositionSeries(cars: [:]),
            timing: TimingTimeline.build(lines: timing, streamStart: start),
            stints: StintTimeline.build(lines: stints, streamStart: start),
            header: HeaderTimeline.build(lapCount: lapCount, clock: [], weather: [], streamStart: start),
            flags: TrackFlags.build(trackStatus: trackStatus, raceControl: [], streamStart: start, gmtOffsetSeconds: 0),
            sessionStatus: SessionStatusTimeline.build(lines: sessionStatus, streamStart: start),
            missing: []
        )
    }

    /// Ten minutes after lights out in the race (offset 01:03:44.576).
    static let raceT = Fixture.raceLightsOut + 600_000
}

@Suite struct LapChartTests {
    @Test func lapChartCutAtPictureTime() throws {
        let race = try RaceFixture.race()
        let t = RaceFixture.raceT
        let rows = LapChart.rows(until: t, session: race)
        // Running order at t, as the tower's (check:raceTowerOrderAtLightsOutPlus10min).
        #expect(rows.map(\.number).joined(separator: ",") == "12,1,6,30,63,27,3,81,23,44,87,41,16,14,55,10,43,51,18,5,11,77")
        // spike/race_checks.py: check:raceLapChartColumnsAtLightsOutPlus10min = 6 (LapCount's
        // CurrentLap is 7 then: the leader has finished 6), and no lap beyond it in any row.
        #expect(rows.allSatisfy { $0.positions.count == 6 })
        // check:raceLapChartCar12AtLightsOutPlus10min, ...Car1..., ...Car44..., ...Car77...
        func row(_ n: String) -> [Int?]? { rows.first { $0.number == n }?.positions }
        #expect(row("12") == [1, 1, 1, 1, 1, 1])
        #expect(row("1") == [3, 3, 3, 3, 3, 2])
        #expect(row("44") == [9, 9, 10, 10, 10, 10])
        #expect(row("77") == [nil, nil, nil, nil, nil, nil])
        // check:raceLapChartPositionsDistinctPerLap
        for lap in 0..<6 {
            let positions = rows.compactMap { $0.positions[lap] }
            #expect(Set(positions).count == positions.count)
        }

        // The leader's sixth crossing (check:raceCar12CrossingOffsets: 3748850) adds the sixth lap.
        let sixth = Fixture.raceStart + 3_748_850
        #expect(LapChart.rows(until: sixth - 1, session: race).allSatisfy { $0.positions.count == 5 })
        #expect(LapChart.rows(until: sixth, session: race).allSatisfy { $0.positions.count == 6 })
        // Before the first crossing (3316923): a row per car with timing
        // (check:raceCarsWithTimingBeforeFirstCrossing = 22), no laps.
        let early = LapChart.rows(until: Fixture.raceStart + 3_316_922, session: race)
        #expect(early.count == 22 && early.allSatisfy { $0.positions.isEmpty })

        // Nothing later than t is read: the session cut at t gives the same chart.
        for u in [Fixture.raceLightsOut, sixth - 1, sixth, t] {
            let cut = try RaceFixture.load("sp26-race", streamStart: Fixture.raceStart, cutAt: u)
            #expect(LapChart.rows(until: u, session: cut) == LapChart.rows(until: u, session: race))
        }
    }

    @Test func lapChartWholeRaceOptIn() throws {
        let race = try RaceFixture.race()
        let whole = LapChart.rows(until: nil, session: race)
        // check:raceLapChartColumnsWholeFixture = 8, check:raceLapChartCar12WholeFixture
        #expect(whole.allSatisfy { $0.positions.count == 8 })
        #expect(whole.first { $0.number == "12" }?.positions == [1, 1, 1, 1, 1, 1, 1, 1])
        // The first six laps are the cut chart's: the whole race only adds laps.
        let cut = LapChart.rows(until: RaceFixture.raceT, session: race)
        for row in cut {
            #expect(whole.first { $0.number == row.number }.map { Array($0.positions.prefix(6)) } == row.positions)
        }
        // Qualifying and practice show only the event strip.
        #expect(LapChart.rows(until: nil, session: try RaceFixture.quali()).isEmpty)
    }
}

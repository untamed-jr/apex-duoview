import Testing
import Foundation
import F1TV
@testable import LiveTiming

/// The committed São Paulo fixtures loaded as `TimingArchive.loadOutcome` assembles them, once per
/// test run. Values the tests assert come from `spike/tower_checks.py`, by its "check:" names.
enum FixtureSession {
    static let loadedRace: LoadedSession? = try? load("sp26-race", streamStart: Fixture.raceStart)
    static let loadedQuali: LoadedSession? = try? load("sp26-quali", streamStart: Fixture.qualiStart)

    /// The session as the archive gives it, with the timing streams cut after `cutAt` when given
    /// (to check nothing later than `t` is used).
    static func load(_ folder: String, streamStart: UTCms, cutAt: UTCms? = nil) throws -> LoadedSession {
        func stream(_ name: String) throws -> [StreamLine] {
            let all = try Fixture.lines("\(folder)/\(name).jsonStream")
            guard let cutAt else { return all }
            return all.filter { F1Values.add(streamStart, $0.offsetMs) <= cutAt }
        }
        let info = try #require(TimingSessionInfo.parse(try Fixture.json("\(folder)/SessionInfo.json")))
        return LoadedSession(
            info: info,
            drivers: Drivers.parse(try Fixture.json("\(folder)/DriverList.json")),
            streamStart: streamStart,
            positions: PositionSeries.parse(lines: try Fixture.lines("\(folder)/Position.z.jsonStream")),
            timing: TimingTimeline.build(lines: try stream("TimingData"), streamStart: streamStart),
            stints: StintTimeline.build(lines: try stream("TimingAppData"), streamStart: streamStart),
            header: HeaderTimeline.build(lapCount: [], clock: [], weather: [], streamStart: streamStart),
            flags: TrackFlags.build(trackStatus: [], raceControl: [], streamStart: streamStart, gmtOffsetSeconds: info.gmtOffsetSeconds),
            missing: []
        )
    }

    static func race() throws -> LoadedSession { try #require(loadedRace) }
    static func quali() throws -> LoadedSession { try #require(loadedQuali) }

    /// A session from hand-written TimingData lines, with no positions.
    static func synthetic(type: String, timing: [StreamLine], drivers: [String: DriverInfo] = [:], start: UTCms = 1_000_000) -> LoadedSession {
        LoadedSession(
            info: TimingSessionInfo(key: 1, name: type, type: type, path: "x/", start: start, gmtOffsetSeconds: 0,
                                    circuitKey: 14, meetingName: "Test", year: 2026),
            drivers: drivers,
            streamStart: start,
            positions: PositionSeries(cars: [:]),
            timing: TimingTimeline.build(lines: timing, streamStart: start),
            stints: StintTimeline.build(lines: [], streamStart: start),
            header: HeaderTimeline.build(lapCount: [], clock: [], weather: [], streamStart: start),
            flags: TrackFlags.build(trackStatus: [], raceControl: [], streamStart: start, gmtOffsetSeconds: 0),
            missing: []
        )
    }
}

/// One TimingData line holding one object per car, each `"n":{...}`.
func timingLine(_ stamp: String, _ cars: [(String, String)], top: String = "") -> StreamLine {
    let body = cars.map { #""\#($0.0)":{\#($0.1)}"# }.joined(separator: ",")
    return line(stamp + "{" + top + #""Lines":{"# + body + "}}")
}

@Suite struct TowerTests {
    /// Ten minutes after lights out in the race.
    static let raceT = Fixture.raceLightsOut + 600_000

    @Test func towerSortedByPosition() throws {
        let rows = Tower.rows(at: Self.raceT, session: try FixtureSession.race(), favourite: nil)
        // check:raceTowerOrderAtLightsOutPlus10min (22 cars; 77, retired, is last at P22)
        #expect(rows.map(\.number).joined(separator: ",")
                == "12,1,6,30,63,27,3,81,23,44,87,41,16,14,55,10,43,51,18,5,11,77")
        #expect(rows.map(\.position) == (1...22).map(Optional.some))

        // check:raceTowerRow12AtLightsOutPlus10min, check:driver12
        let leader = rows[0]
        #expect(leader.tla == "ANT")
        #expect(leader.teamColour == "00D7B6")
        #expect(leader.lastLap == "1:26.162")
        #expect(leader.lastLapPace == .set)
        #expect(leader.gap == "LAP 7")
        #expect(leader.interval == "LAP 7")
        #expect(leader.tyre?.compound == "I")
        #expect(leader.tyre?.laps == 6)
        // check:raceTowerRow1AtLightsOutPlus10min, check:raceTowerRow6AtLightsOutPlus10min
        #expect(rows[1].lastLap == "1:26.906")
        #expect(rows[1].gap == "+4.401")
        #expect(rows[1].interval == "+4.401")
        #expect(rows[2].lastLap == "1:27.067")
        #expect(rows[2].gap == "+6.236")
        #expect(rows[2].interval == "+1.835")
        #expect(rows.allSatisfy { !$0.inKnockoutZone && !$0.battle })

        // Unknown positions go last, in number order.
        let synthetic = FixtureSession.synthetic(type: "Race", timing: [timingLine("00:00:01.000", [
            ("44", #""Position":"2""#), ("7", #""Line":3"#), ("3", #""Position":"1""#), ("10", #""Line":4"#),
        ])])
        let ordered = Tower.rows(at: 1_001_000, session: synthetic, favourite: nil)
        #expect(ordered.map(\.number) == ["3", "44", "7", "10"])
        #expect(ordered.map(\.position) == [1, 2, nil, nil])
        #expect(Tower.rows(at: 1_000_999, session: synthetic, favourite: nil).isEmpty)
    }

    @Test func towerPitShowsPIT() throws {
        let race = try FixtureSession.race()
        // check:raceCar77At3200000 = ('17', True, False, ''): in the pit lane before the start.
        let before = try #require(Tower.rows(at: Fixture.raceStart + 3_200_000, session: race, favourite: nil).first { $0.number == "77" })
        #expect(before.position == 17)
        #expect(before.lastLap == "PIT")
        #expect(before.lastLapPace == .empty)
        #expect(!before.dimmed)
        // check:raceCar77AtLightsOutPlus10min = ('22', True, True, True): retired in the pits.
        let after = try #require(Tower.rows(at: Self.raceT, session: race, favourite: nil).last)
        #expect(after.number == "77")
        #expect(after.lastLap == "PIT")
        #expect(after.dimmed)
        // A car out of the pits shows its last lap again.
        let session = FixtureSession.synthetic(type: "Race", timing: [
            timingLine("00:00:01.000", [("4", #""Position":"1","InPit":false,"LastLapTime":{"Value":"1:30.000","PersonalFastest":true}"#)]),
            timingLine("00:00:02.000", [("4", #""InPit":true"#)]),
            timingLine("00:00:30.000", [("4", #""PitOut":true"#)]),
        ])
        #expect(Tower.rows(at: 1_001_000, session: session, favourite: nil).first?.lastLap == "1:30.000")
        #expect(Tower.rows(at: 1_001_000, session: session, favourite: nil).first?.lastLapPace == .personalBest)
        #expect(Tower.rows(at: 1_002_000, session: session, favourite: nil).first?.lastLap == "PIT")
        #expect(Tower.rows(at: 1_030_000, session: session, favourite: nil).first?.lastLap == "1:30.000")
    }

    @Test func towerQualiKnockoutZoneBottomFive() throws {
        // 20 cars in Q1: the bottom five (16–20) are in the zone.
        let twenty = (1...20).map { (String($0 + 100), #""Position":"\#($0)","KnockedOut":false"#) }
        let q1 = FixtureSession.synthetic(type: "Qualifying", timing: [timingLine("00:00:01.000", twenty, top: #""SessionPart":1,"#)])
        let rows = Tower.rows(at: 1_001_000, session: q1, favourite: nil)
        #expect(rows.filter(\.inKnockoutZone).map(\.number) == ["116", "117", "118", "119", "120"])
        #expect(rows.allSatisfy { !$0.dimmed })

        // Q2: 15 cars still in, five knocked out (dimmed, outside the zone); P11–P15 are in it.
        var q2Lines = [timingLine("00:00:01.000", twenty, top: #""SessionPart":1,"#)]
        q2Lines.append(timingLine("00:10:00.000", (16...20).map { (String($0 + 100), #""KnockedOut":true"#) }, top: #""SessionPart":2,"#))
        let q2 = FixtureSession.synthetic(type: "Qualifying", timing: q2Lines)
        let rows2 = Tower.rows(at: 1_600_000, session: q2, favourite: nil)
        #expect(rows2.filter(\.inKnockoutZone).map(\.number) == ["111", "112", "113", "114", "115"])
        #expect(rows2.filter(\.dimmed).map(\.number) == ["116", "117", "118", "119", "120"])
        // Q3: no zone.
        q2Lines.append(timingLine("00:20:00.000", [], top: #""SessionPart":3,"#))
        let q3 = FixtureSession.synthetic(type: "Qualifying", timing: q2Lines)
        #expect(Tower.rows(at: 2_200_000, session: q3, favourite: nil).allSatisfy { !$0.inKnockoutZone })
        #expect(Tower.knockoutZoneSize(carsStillIn: 20, part: 1) == 5)
        #expect(Tower.knockoutZoneSize(carsStillIn: 15, part: 2) == 5)
        #expect(Tower.knockoutZoneSize(carsStillIn: 10, part: 3) == 0)
        #expect(Tower.knockoutZoneSize(carsStillIn: 8, part: 1) == 0)

        // 2026 has 22 cars, and F1 knocks out six per part (NoEntries [22,16,10]; the raw archive
        // flags six KnockedOut at each of Q2's and Q3's starts), so the zone is six there.
        // check:qualiTowerOrderAtQ1Plus10min, check:qualiKnockedOutAtQ1Plus10min = [],
        // check:qualiBottomSixAtQ1Plus10min = ['23', '14', '55', '11', '77', '18']
        let quali = try FixtureSession.quali()
        let real = Tower.rows(at: Fixture.qualiQ1 + 600_000, session: quali, favourite: nil)
        #expect(real.count == 22)
        #expect(real.filter(\.inKnockoutZone).map(\.number) == ["23", "14", "55", "11", "77", "18"])
        #expect(Tower.gapHeader(session: quali) == "Fastest")
        #expect(Tower.gapHeader(session: try FixtureSession.race()) == "Leader")
        #expect(Tower.rows(at: TowerTests.raceT, session: try FixtureSession.race(), favourite: nil).allSatisfy { !$0.inKnockoutZone })
    }

    @Test func towerUnknownCarKeepsNumber() throws {
        var race = try FixtureSession.race()
        race.drivers["44"] = nil
        let row = try #require(Tower.rows(at: Self.raceT, session: race, favourite: nil).first { $0.number == "44" })
        #expect(row.tla == "44")
        #expect(row.teamColour == "")
        #expect(row.position == 10)  // check:raceTowerOrderAtLightsOutPlus10min (44 is 10th)

        let session = FixtureSession.synthetic(type: "Race", timing: [timingLine("00:00:01.000", [
            ("99", #""Position":"23","GapToLeader":"+1 LAP","IntervalToPositionAhead":{"Value":"+0.5"}"#),
        ])])
        let unknown = try #require(Tower.rows(at: 1_001_000, session: session, favourite: "99").first)
        #expect(unknown.number == "99")
        #expect(unknown.tla == "99")
        #expect(unknown.gap == "+1 LAP")
        #expect(unknown.interval == "+0.5")
        #expect(unknown.tyre == nil)
        #expect(unknown.lastLap == "")
        #expect(!unknown.battle)
    }

    @Test func retiredCarLeavesMap() throws {
        let race = try FixtureSession.race()
        let retired = Fixture.raceStart + 3_347_533  // car 77: Retired and Stopped
        let t = retired + 60_000
        // check:raceCar77SamplesWithin5sOfRetiredPlus60s: 77 still sends positions, so leaving it
        // out is the retirement's doing.
        #expect(race.positions.cars["77"]?.mapPoint(at: t) != nil)
        let cars = MapCars.visible(at: t, session: race)
        #expect(!cars.contains { $0.number == "77" })
        #expect(cars.contains { $0.number == "44" })
        #expect(cars.allSatisfy { race.positions.cars[$0.number]?.mapPoint(at: t) == $0.point })
        // Before it retired: on the map, dimmed in the pit lane (check:raceCar77SamplesWithin5sOf3200000,
        // check:raceCar77At3200000).
        let early = try #require(MapCars.visible(at: Fixture.raceStart + 3_200_000, session: race).first { $0.number == "77" })
        #expect(early.dimmed)
        #expect(early.tla == race.drivers["77"]?.tla)
        #expect(!early.flying)
        // Dimmed cars are drawn first, then from the back up, so the leader is on top.
        let order = MapCars.visible(at: TowerTests.raceT, session: race)
        #expect(order.last?.number == "12")
    }

    @Test func towerUsesNothingAfterT() throws {
        // The rows, lap states and a card at t are the same from streams cut at t.
        for (folder, start, t, car) in [("sp26-race", Fixture.raceStart, TowerTests.raceT, "44"),
                                        ("sp26-quali", Fixture.qualiStart, Fixture.qualiQ1 + 120_000, "77")] {
            let full = try FixtureSession.load(folder, streamStart: start)
            let cut = try FixtureSession.load(folder, streamStart: start, cutAt: t)
            #expect(Tower.rows(at: t, session: full, favourite: "43") == Tower.rows(at: t, session: cut, favourite: "43"))
            #expect(LapStates(session: full).at(t) == LapStates(session: cut).at(t))
            #expect(DriverCardModel.at(t, number: car, session: full) == DriverCardModel.at(t, number: car, session: cut))
            #expect(MapCars.visible(at: t, session: full) == MapCars.visible(at: t, session: cut))
        }
    }
}

@Suite struct LapStatesTests {
    @Test func lapStatesFollowAndroid() {
        let lines = [
            timingLine("00:00:01.000", [("4", #""InPit":true,"PitOut":false,"KnockedOut":false"#)]),
            // In qualifying F1 sends the first lap count with PitOut: no crossing.
            timingLine("00:01:00.000", [("4", #""InPit":false,"PitOut":true,"NumberOfLaps":1"#)]),
            timingLine("00:02:30.000", [("4", #""NumberOfLaps":2"#)]),
            timingLine("00:04:00.000", [("4", #""NumberOfLaps":3"#)]),
            timingLine("00:05:30.000", [("4", #""NumberOfLaps":4"#)]),
            timingLine("00:06:00.000", [("4", #""InPit":true"#)]),
            timingLine("00:07:00.000", [("4", #""InPit":false"#)]),
            timingLine("00:10:00.000", [("4", #""KnockedOut":true"#)]),
        ]
        let timing = TimingTimeline.build(lines: lines, streamStart: 0)
        let q = LapStates(timing: timing, qualifying: true)
        #expect(q.state(of: "4", at: 0) == .unknown)
        #expect(q.state(of: "4", at: 1_000) == .pit)
        #expect(q.state(of: "4", at: 60_000) == .outLap)
        #expect(q.state(of: "4", at: 150_000) == .push)
        #expect(q.state(of: "4", at: 240_000) == .coolDown)
        #expect(q.state(of: "4", at: 330_000) == .push)
        #expect(q.state(of: "4", at: 360_000) == .pit)
        #expect(q.state(of: "4", at: 420_000) == .outLap)
        #expect(q.state(of: "4", at: 600_000) == .knockedOut)
        #expect(q.at(600_000) == ["4": .knockedOut])
        #expect(LapStates.at(150_000, timing: timing, qualifying: true) == ["4": .push])
        // Outside qualifying there are no push or cool-down laps: the line ends the out lap.
        let r = LapStates(timing: timing, qualifying: false)
        #expect(r.state(of: "4", at: 60_000) == .outLap)
        #expect(r.state(of: "4", at: 150_000) == .unknown)
        #expect(r.state(of: "4", at: 330_000) == .unknown)
        #expect(r.state(of: "4", at: 360_000) == .pit)
    }

    @Test func lapStatesFromTheFixtures() throws {
        // check:qualiLapStates77 = [(8058, pit), (803106, outLap), (920916, pit)]
        let quali = LapStates(session: try FixtureSession.quali())
        #expect(quali.state(of: "77", at: Fixture.qualiStart + 803_105) == .pit)
        #expect(quali.state(of: "77", at: Fixture.qualiStart + 803_106) == .outLap)
        #expect(quali.state(of: "77", at: Fixture.qualiStart + 920_915) == .outLap)
        #expect(quali.state(of: "77", at: Fixture.qualiStart + 920_916) == .pit)
        // check:qualiLapStateCountsAt900000 = [(outLap, 15), (pit, 7)]
        let counts = Dictionary(grouping: quali.at(Fixture.qualiStart + 900_000).values, by: { $0 }).mapValues(\.count)
        #expect(counts == [.outLap: 15, .pit: 7])
        // check:raceLapStatesSeen = [outLap, pit, unknown]; check:raceLapStatesAtLightsOutPlus10min = [(77, pit)]
        let race = try FixtureSession.race()
        let states = LapStates(session: race)
        let all = Set(race.timing.updateTimes.flatMap { states.at($0).values })
        #expect(all == [.outLap, .pit, .unknown])
        #expect(states.at(TowerTests.raceT).filter { $0.value != .unknown } == ["77": .pit])
        #expect(states.state(of: "77", at: Fixture.raceStart + 3_200_000) == .pit)  // check:raceLapState77At3200000
    }
}

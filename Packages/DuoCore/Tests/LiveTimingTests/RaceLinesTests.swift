import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct RaceLinesTests {
    @Test func raceLinesTrendClosing() throws {
        let race = try RaceFixture.race()
        let t = RaceFixture.raceT
        // spike/race_checks.py, check:raceLines44AtLightsOutPlus10min = (10, '23', '+0.969', '87',
        // '+1.254'). Three of 44's laps back is offset 3559657; then 44 was 1.470 s behind 23
        // (now 0.969) and 87 1.603 s behind 44 (now 1.254): check:raceLines44TrendAhead,
        // check:raceLines44TrendBehind. Both gaps shrink.
        let hamilton = try #require(RaceLines.at(t, car: "44", session: race))
        #expect(hamilton.position == 10)
        #expect(hamilton.ahead?.tla == "ALB")
        #expect(hamilton.ahead?.gap == "+1.0s")
        #expect(hamilton.ahead?.closing == true)
        #expect(hamilton.aheadNumber == "23")
        #expect(hamilton.behind?.tla == "BEA")  // DriverList.json: 87 is BEA
        #expect(hamilton.behindNumber == "87")
        #expect(hamilton.behind?.gap == "-1.3s")
        #expect(hamilton.behind?.closing == true)
        // check:raceTyre44CompoundAtLightsOutPlus10min = INTERMEDIATE,
        // check:raceTyres44And1AtLightsOutPlus10min = [('I', 6), ...]
        #expect(hamilton.tyre?.compound == "Intermediate")
        #expect(hamilton.tyre?.laps == 6)
        // check:raceRejoin44At22sAtLightsOutPlus10min, with no stop measured yet (22 s).
        #expect(hamilton.pitNow == "Pit now → P21 behind PER")
        #expect(RaceLines.at(t, car: "44", session: race, storedPitLossMs: 5_000)?.pitNow == "Pit now → P13 behind LEC")

        // check:raceLines1AtLightsOutPlus10min = (2, '12', '+4.401', '6', '+1.835'); 3 laps back
        // 12 led 1 by 3.707 s and 6 was 1.379 s behind: both gaps grow (check:raceLines1TrendAhead,
        // check:raceLines1TrendBehind).
        let second = try #require(RaceLines.at(t, car: "1", session: race))
        #expect(second.position == 2)
        #expect(second.ahead?.tla == "ANT" && second.ahead?.gap == "+4.4s" && second.ahead?.closing == false)
        #expect(second.behindNumber == "6" && second.behind?.gap == "-1.8s" && second.behind?.closing == false)
        // The leader has no car ahead.
        let leader = try #require(RaceLines.at(t, car: "12", session: race))
        #expect(leader.ahead == nil && leader.aheadNumber == nil)
        #expect(leader.behindNumber == "1" && leader.behind?.gap == "-4.4s" && leader.behind?.closing == false)

        // Fewer than 3 laps in: no trend. 44's fourth crossing is check:raceLines44LastFiveLaps's
        // lap 4 at 3589477 (its first is lap 1).
        let early = try #require(RaceLines.at(Fixture.raceStart + 3_589_476, car: "44", session: race))
        #expect(early.ahead != nil && early.ahead?.closing == nil)
        #expect(RaceLines.at(Fixture.raceStart + 3_589_477, car: "44", session: race)?.ahead?.closing != nil)

        // No car's timing: nothing. Qualifying: no cars ahead or behind, no pit line.
        #expect(RaceLines.at(t, car: "99", session: race) == nil)
        let quali = try #require(RaceLines.at(Fixture.qualiQ1 + 600_000, car: "44", session: try RaceFixture.quali()))
        #expect(quali.ahead == nil && quali.behind == nil && quali.pitNow == nil)

        // Nothing later than t is read.
        let cut = try RaceFixture.load("sp26-race", streamStart: Fixture.raceStart, cutAt: t)
        #expect(RaceLines.at(t, car: "44", session: cut) == hamilton)
        #expect(RaceLines.at(t, car: "1", session: cut) == second)
    }

    @Test func lastFiveLapsWithSectors() throws {
        let race = try RaceFixture.race()
        // check:raceLines44LastFiveLaps: newest first, LastLapTime and sector paces per lap.
        let lines = try #require(RaceLines.at(RaceFixture.raceT, car: "44", session: race))
        #expect(lines.lastLaps.map(\.lap) == [6, 5, 4, 3, 2])
        #expect(lines.lastLaps.map(\.time) == ["1:28.304", "1:28.181", "1:28.427", "1:28.313", "1:29.518"])
        #expect(lines.lastLaps.map(\.sectors) == [
            [.personalBest, .set, .set],
            [.set, .personalBest, .set],
            [.personalBest, .set, .personalBest],
            [.personalBest, .personalBest, .personalBest],
            [.personalBest, .personalBest, .set],
        ])
        // check:raceCar12LastFiveLapsWholeFixture: purple sectors too.
        let end = try #require(RaceLines.at(Fixture.raceStart + 3_921_228, car: "12", session: race))
        #expect(end.lastLaps.map(\.lap) == [8, 7, 6, 5, 4])
        #expect(end.lastLaps.map(\.time) == ["1:25.980", "1:26.442", "1:26.162", "1:26.187", "1:26.086"])
        #expect(end.lastLaps.first?.sectors == [.overallBest, .personalBest, .set])
        #expect(end.lastLaps.last?.sectors == [.overallBest, .overallBest, .set])
        // F1 sends no time for lap 1 (check:raceLeaderLap1LastLapTimeValue = '').
        let one = try #require(RaceLines.at(Fixture.raceStart + 3_316_923, car: "12", session: race))
        #expect(one.lastLaps.map(\.lap) == [1])
        #expect(one.lastLaps.first?.time == "")

        // A final sector 2 s after the line, and a lap time 1 s after, belong to the lap just
        // done, but only from when they arrive.
        let s: UTCms = 1_000_000
        let session = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [("4", #""Position":"1","NumberOfLaps":3,"Sectors":[{"Value":""},{"Value":""},{"Value":""}]"#)]),
            timingLine("00:00:30.000", [("4", #""Sectors":{"0":{"Value":"30.1","PersonalFastest":true}}"#)]),
            timingLine("00:01:00.000", [("4", #""Sectors":{"1":{"Value":"30.2","OverallFastest":true,"PersonalFastest":true}}"#)]),
            timingLine("00:01:30.000", [("4", #""NumberOfLaps":4"#)]),
            timingLine("00:01:31.000", [("4", #""LastLapTime":{"Value":"1:30.500","PersonalFastest":true}"#)]),
            timingLine("00:01:32.000", [("4", #""Sectors":{"2":{"Value":"30.2"}}"#)]),
        ], start: s)
        func last(_ u: UTCms) -> (lap: Int, time: String, sectors: [SectorPace])? {
            RaceLines.at(u, car: "4", session: session)?.lastLaps.first
        }
        #expect(last(s + 89_999) == nil)
        #expect(last(s + 90_000)?.lap == 4)
        #expect(last(s + 90_000)?.time == "")
        #expect(last(s + 90_000)?.sectors == [.personalBest, .overallBest, .empty])
        #expect(last(s + 91_000)?.time == "1:30.500")
        #expect(last(s + 91_000)?.sectors == [.personalBest, .overallBest, .empty])
        #expect(last(s + 92_000)?.sectors == [.personalBest, .overallBest, .set])
        // The lap in progress keeps its own sectors blank (TimingTimeline's rule), and the late
        // sector and lap time make no timing update of their own.
        #expect(session.timing.state(of: "4", at: s + 92_000)?.sectors == [.empty, .empty, .empty])
        #expect(!session.timing.updateTimes.contains(s + 92_000))
    }
}

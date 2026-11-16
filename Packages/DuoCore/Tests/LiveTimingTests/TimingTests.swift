import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct TimingTests {
    static let t0: UTCms = 1_000_000

    static func race() throws -> TimingTimeline {
        TimingTimeline.build(lines: try Fixture.lines("sp26-race/TimingData.jsonStream"), streamStart: Fixture.raceStart)
    }

    @Test func timingAtReturnsStateNotLaterThanT() throws {
        let timing = try Self.race()
        let fiveMin = timing.at(Fixture.raceLightsOut + 300_000)
        let laps = fiveMin.values.compactMap(\.numberOfLaps)
        #expect(laps.max() == 3)     // check:raceMaxNumberOfLapsAtLightsOutPlus5min
        #expect(laps.count == 21)    // check:raceCarsWithLapsAtLightsOutPlus5min
        // The next lap count arrives at offset 3576430 (check:firstLapCountUpdateAfterT5Offset),
        // taking the leader to 4 (check:raceMaxNumberOfLapsJustAfterThat).
        let next = Fixture.raceStart + 3_576_430
        #expect(timing.at(next - 1).values.compactMap(\.numberOfLaps).max() == 3)
        #expect(timing.at(next).values.compactMap(\.numberOfLaps).max() == 4)
        #expect(timing.at(Fixture.raceStart).isEmpty)
        #expect(zip(timing.updateTimes, timing.updateTimes.dropFirst()).allSatisfy { $0 < $1 })
        #expect(timing.updateTimes.contains(next))
    }

    @Test func sectorColoursFollowF1sFlagsAndBlankAtTheLine() throws {
        let timing = try Self.race()
        // check:car44Lap2CrossingOffset and check:car44Lap2CrossingDelta: lap 2 ends with S3
        // "19.789" in the same delta, so it belongs to lap 2 and the new lap's sectors are blank.
        let crossing = Fixture.raceStart + 3_412_677
        let atLine = try #require(timing.state(of: "44", at: crossing))
        #expect(atLine.numberOfLaps == 2)
        #expect(atLine.lineCrossedAt == crossing)
        #expect(atLine.sectors == [.empty, .empty, .empty])
        #expect(atLine.lastLapMs == 89_518)
        #expect(atLine.lastLapPace == .personalBest)
        // check:car44AtOffset3435379: S1 "22.676" comes with no flag key; F1's PersonalFastest
        // (true since 22.951) still holds, and it is a personal best. S2 and S3 were emptied.
        let s1 = try #require(timing.state(of: "44", at: Fixture.raceStart + 3_435_379))
        #expect(s1.sectors == [.personalBest, .empty, .empty])
        #expect(s1.bestLapMs == 89_518)
        #expect(s1.lineCrossedAt == crossing)
    }

    @Test func timingRetiredCarFlagged() {
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"4":{"Position":"7","Retired":false,"Stopped":false,"NumberOfLaps":10}}}"#,
            #"00:01:00.000{"Lines":{"4":{"Stopped":true}}}"#,
            #"00:01:30.000{"Lines":{"4":{"Retired":true}}}"#
        ), streamStart: Self.t0)
        #expect(timing.state(of: "4", at: Self.t0 + 59_000)?.retired == false)
        #expect(timing.state(of: "4", at: Self.t0 + 60_000)?.stopped == true)
        #expect(timing.state(of: "4", at: Self.t0 + 60_000)?.retired == false)
        let out = timing.state(of: "4", at: Self.t0 + 90_000)
        #expect(out?.retired == true)
        #expect(out?.position == 7)
        #expect(timing.updateTimes == [Self.t0 + 1000, Self.t0 + 60_000, Self.t0 + 90_000])
    }

    @Test func unknownCarNumberTolerated() throws {
        let drivers = Drivers.parse(try Fixture.json("sp26-race/DriverList.json"))
        #expect(drivers["99"] == nil)
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"99":{"Position":"23","GapToLeader":"+1 LAP","IntervalToPositionAhead":{"Value":"+0.5"}},"1":{"Position":"1"}}}"#
        ), streamStart: Self.t0)
        let row = try #require(timing.at(Self.t0 + 1000)["99"])
        #expect(row.position == 23)
        #expect(row.gapToLeader == "+1 LAP")
        #expect(row.interval == "+0.5")
        #expect(timing.at(Self.t0 + 1000).keys.sorted() == ["1", "99"])
    }

    @Test func pitInAndOutFollowAndroid() {
        // Before a race the last run to the grid can end with just InPit false; PitOut clears it too.
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"4":{"InPit":true,"PitOut":false}}}"#,
            #"00:01:00.000{"Lines":{"4":{"PitOut":true}}}"#,
            #"00:01:10.000{"Lines":{"4":{"PitOut":false}}}"#,
            #"00:02:00.000{"Lines":{"4":{"InPit":true}}}"#,
            #"00:03:00.000{"Lines":{"4":{"InPit":false}}}"#
        ), streamStart: Self.t0)
        #expect(timing.state(of: "4", at: Self.t0 + 30_000)?.inPit == true)
        #expect(timing.state(of: "4", at: Self.t0 + 60_000)?.inPit == false)
        #expect(timing.state(of: "4", at: Self.t0 + 60_000)?.pitOut == true)
        #expect(timing.state(of: "4", at: Self.t0 + 70_000)?.inPit == false)
        #expect(timing.state(of: "4", at: Self.t0 + 120_000)?.inPit == true)
        #expect(timing.state(of: "4", at: Self.t0 + 180_000)?.inPit == false)
    }

    @Test func aLateFinalSectorStillCountsForTheLapItFinished() {
        // Android's DriverTimingTest: S3 1 s after the line belongs to the lap just done.
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"4":{"NumberOfLaps":3,"Sectors":[{"Value":"30.0"},{"Value":"31.0"},{"Value":"32.0"}]}}}"#,
            #"00:01:00.000{"Lines":{"4":{"NumberOfLaps":4,"LastLapTime":{"Value":"1:33.100"}}}}"#,
            #"00:01:01.000{"Lines":{"4":{"Sectors":{"2":{"Value":"30.100","OverallFastest":true}}}}}"#,
            #"00:01:30.000{"Lines":{"4":{"Sectors":{"0":{"Value":"29.9","PersonalFastest":true},"1":{"Value":""},"2":{"Value":""}}}}}"#,
            #"00:02:00.000{"Lines":{"4":{"Sectors":{"1":{"Value":"30.5"}}}}}"#
        ), streamStart: Self.t0)
        #expect(timing.state(of: "4", at: Self.t0 + 1000)?.sectors == [.set, .set, .set])
        #expect(timing.state(of: "4", at: Self.t0 + 62_000)?.sectors == [.empty, .empty, .empty])
        #expect(timing.state(of: "4", at: Self.t0 + 62_000)?.lastLapMs == 93_100)
        #expect(timing.state(of: "4", at: Self.t0 + 62_000)?.lastLapPace == .set)
        #expect(timing.state(of: "4", at: Self.t0 + 90_000)?.sectors == [.personalBest, .empty, .empty])
        #expect(timing.state(of: "4", at: Self.t0 + 120_000)?.sectors == [.personalBest, .set, .empty])
    }

    @Test func qualifyingGapsComeFromThePartsStats() throws {
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"SessionPart":1,"Lines":{"3":{"Position":"2","Stats":[{"TimeDiffToFastest":"+0.100","TimeDifftoPositionAhead":"+0.100"},{"TimeDiffToFastest":"","TimeDifftoPositionAhead":""},{}],"KnockedOut":false}}}"#,
            #"00:10:00.000{"SessionPart":2}"#,
            #"00:11:00.000{"Lines":{"3":{"Stats":{"1":{"TimeDiffToFastest":"+0.250","TimeDifftoPositionAhead":"+0.050"}},"KnockedOut":true}}}"#
        ), streamStart: Self.t0)
        let q1 = try #require(timing.state(of: "3", at: Self.t0 + 5000))
        #expect(q1.gapToLeader == "+0.100")
        #expect(q1.interval == "+0.100")
        #expect(timing.sessionPart(at: Self.t0 + 5000) == 1)
        #expect(timing.state(of: "3", at: Self.t0 + 600_000)?.gapToLeader == "")
        #expect(timing.sessionPart(at: Self.t0 + 600_000) == 2)
        let q2 = try #require(timing.state(of: "3", at: Self.t0 + 660_000))
        #expect(q2.gapToLeader == "+0.250")
        #expect(q2.interval == "+0.050")
        #expect(q2.knockedOut)
    }

    @Test func qualifyingFixtureReadsItsPart() throws {
        let timing = TimingTimeline.build(lines: try Fixture.lines("sp26-quali/TimingData.jsonStream"), streamStart: Fixture.qualiStart)
        let t = Fixture.qualiQ1 + 600_000
        #expect(timing.sessionPart(at: t) == 1)
        // check:qualiP2AtQ1Plus10min: car 12 is P2 with no gaps yet (red flag 2½ min in).
        let p2 = try #require(timing.state(of: "12", at: t))
        #expect(p2.position == 2)
        #expect(p2.gapToLeader == "")
        #expect(p2.interval == "")
        #expect(timing.at(t).count == 22)
    }

    @Test func stintsTrackCompoundAndLaps() throws {
        let stints = StintTimeline.build(lines: try Fixture.lines("sp26-race/TimingAppData.jsonStream"), streamStart: Fixture.raceStart)
        let at = stints.at(Fixture.raceLightsOut + 600_000)
        // check:stints1AtLightsOutPlus10min and check:stints44AtLightsOutPlus10min
        #expect(at["1"] == [Stint(compound: "INTERMEDIATE", isNew: true, startLaps: 0, totalLaps: 6)])
        #expect(at["44"] == [Stint(compound: "INTERMEDIATE", isNew: true, startLaps: 0, totalLaps: 6)])

        let synthetic = StintTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"4":{"RacingNumber":"4","Stints":[]}}}"#,
            #"00:00:02.000{"Lines":{"4":{"Stints":[{"Compound":"MEDIUM","New":"true","StartLaps":0,"TotalLaps":0}]}}}"#,
            #"00:10:00.000{"Lines":{"4":{"Stints":{"0":{"TotalLaps":20}}}}}"#,
            #"00:11:00.000{"Lines":{"4":{"Stints":{"1":{"TotalLaps":3,"StartLaps":3}}}}}"#,
            #"00:11:01.000{"Lines":{"4":{"Stints":{"1":{"Compound":"HARD","New":"false"}}}}}"#
        ), streamStart: Self.t0)
        #expect(synthetic.at(Self.t0 + 1000)["4"] == [])
        #expect(synthetic.at(Self.t0 + 600_000)["4"] == [Stint(compound: "MEDIUM", isNew: true, startLaps: 0, totalLaps: 20)])
        #expect(synthetic.at(Self.t0 + 660_500)["4"]?.count == 1)  // no compound yet: left out
        #expect(synthetic.at(Self.t0 + 661_000)["4"]?.last == Stint(compound: "HARD", isNew: false, startLaps: 3, totalLaps: 3))
        #expect(synthetic.at(Self.t0)["4"] == nil)
    }

    @Test func headerLapCount() throws {
        let header = HeaderTimeline.build(
            lapCount: try Fixture.lines("sp26-race/LapCount.jsonStream"),
            clock: try Fixture.lines("sp26-race/ExtrapolatedClock.jsonStream"),
            weather: try Fixture.lines("sp26-race/WeatherData.jsonStream"),
            streamStart: Fixture.raceStart
        ).at(Fixture.raceLightsOut + 300_000)
        #expect(header.lap == 4)                 // check:raceLapCountAtLightsOutPlus5min
        #expect(header.totalLaps == 71)
        #expect(header.clockRemaining == 6897)  // check:raceClockRemainingSecondsAtLightsOutPlus5min
        #expect(header.airTemp == 16.1)          // check:raceWeatherAtLightsOutPlus5min
        #expect(header.trackTemp == 26.2)
        #expect(header.raining == false)
    }

    @Test func headerClockStopsAtARedFlag() throws {
        let header = HeaderTimeline.build(lapCount: [], clock: try Fixture.lines("sp26-quali/ExtrapolatedClock.jsonStream"),
                                          weather: [], streamStart: Fixture.qualiStart)
        // check:qualiStoppedClockMark: stopped at 00:15:37 at 1794074543996
        #expect(header.at(1_794_074_543_996 + 60_000).clockRemaining == 937)
        #expect(header.at(1_794_074_543_996 + 60_000).lap == nil)
        // check:qualiClockAtQ1MarkPlus10s: running from 00:17:59 at Q1's start; 10 s later, 17:49.
        #expect(header.at(1_794_074_401_011 + 10_000).clockRemaining == 1069)
    }

    @Test func clockLinesMayLeaveFieldsOut() {
        let header = HeaderTimeline.build(lapCount: [], clock: lines(
            #"00:00:01.000{"Utc":"2026-11-07T18:00:00Z","Remaining":"00:10:00","Extrapolating":true}"#,
            #"00:01:00.000{"Utc":"2026-11-07T18:01:00Z","Extrapolating":false}"#,
            #"00:02:00.000{"Utc":"2026-11-07T18:02:00Z","Remaining":"00:09:00"}"#
        ), weather: [], streamStart: 0)
        #expect(header.at(SignalR.utc("2026-11-07T18:00:30Z")!).clockRemaining == 570)
        #expect(header.at(SignalR.utc("2026-11-07T18:01:30Z")!).clockRemaining == 540)
        #expect(header.at(SignalR.utc("2026-11-07T18:02:30Z")!).clockRemaining == 540)
        #expect(HeaderTimeline.build(lapCount: [], clock: [], weather: [], streamStart: 0).at(0).clockRemaining == nil)
    }

    @Test func weatherOptionalMissingIsNil() throws {
        let header = HeaderTimeline.build(lapCount: try Fixture.lines("sp26-race/LapCount.jsonStream"), clock: [], weather: [],
                                          streamStart: Fixture.raceStart).at(Fixture.raceLightsOut + 300_000)
        #expect(header == SessionHeader(lap: 4, totalLaps: 71, clockRemaining: nil, airTemp: nil, trackTemp: nil, raining: false))
        let wet = HeaderTimeline.build(lapCount: [], clock: [], weather: lines(
            #"00:00:01.000{"AirTemp":"20.1","TrackTemp":"29.0","Rainfall":"0"}"#,
            #"00:01:00.000{"Rainfall":"1"}"#
        ), streamStart: Self.t0)
        #expect(wet.at(Self.t0).airTemp == nil)
        #expect(wet.at(Self.t0 + 1000) == SessionHeader(airTemp: 20.1, trackTemp: 29.0, raining: false))
        #expect(wet.at(Self.t0 + 60_000).raining)
        #expect(wet.at(Self.t0 + 60_000).airTemp == 20.1)
    }
}

import Testing
import Foundation
import F1TV
@testable import LiveTiming

/// Laps of `lapMs` for cars "1" (leader) and "44" (`gap` behind): both cross the line at
/// `firstLine` seconds and every `lapMs` after, `count` times. `more` lines are merged in by time.
private func laps(_ count: Int, lapMs: Int = 90_000, firstLine: Int = 100, gap: String = "+2.000",
                  more: [StreamLine] = []) -> [StreamLine] {
    var out = [timingLine("00:00:00.000", [("1", #""Position":"1","GapToLeader":"","IntervalToPositionAhead":{"Value":""}"#),
                                          ("44", #""Position":"2","GapToLeader":"\#(gap)","IntervalToPositionAhead":{"Value":"\#(gap)"}"#)])]
    for lap in 1...count {
        let ms = firstLine * 1000 + (lap - 1) * lapMs
        let stamp = String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        out.append(timingLine(stamp, [("1", #""NumberOfLaps":\#(lap)"#)]))
        out.append(timingLine(stamp, [("44", #""NumberOfLaps":\#(lap)"#)]))
    }
    return (out + more).enumerated().sorted { ($0.element.offsetMs, $0.offset) < ($1.element.offsetMs, $1.offset) }.map(\.element)
}

@Suite struct PitCircleTests {
    @Test func referenceUsesLastFiveGreen() throws {
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [99_000, 91_000, 92_000, 93_000, 94_000, 95_000],
                                         typicalLapMs: 80_000, lastLapMs: 70_000) == 93_000)
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [91_000, 92_000, 93_000, 94_000, 95_001],
                                         typicalLapMs: 80_000, lastLapMs: nil) == 93_000)
        // Before 5 green laps the spec's fallback applies: typical, then last; no average of fewer.
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [91_000, 92_000, 93_000, 94_000],
                                         typicalLapMs: 80_000, lastLapMs: 70_000) == 80_000)
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [91_000], typicalLapMs: nil, lastLapMs: 70_000) == 70_000)

        // The race at lights out + 10 min. spike/race_checks.py: the leader is 12
        // (check:raceLeaderAtLightsOutPlus10min), its laps between crossings are
        // check:raceLeaderLapWindowsAtLightsOutPlus10min, all green (no stops; TrackStatus 1 from
        // 00:28:19), so the reference is their average, check:raceReferenceLapAtLightsOutPlus10min.
        let race = try RaceFixture.race()
        let t = RaceFixture.raceT
        #expect(PitCircle.greenLaps(of: "12", at: t, session: race) == [87_098, 86_394, 86_015, 86_230, 86_190])
        // check:raceTypicalLapAtLightsOutPlus10min
        #expect(PitCircle.typicalLapMs(of: "12", at: t, session: race) == 86_230)
        let circle = try #require(PitCircle.layout(at: t, session: race))
        #expect(circle.referenceLapMs == 86_385)
        #expect(circle.greenLaps == 5)
        // With 3 green laps (the leader's 4th crossing) it is the typical lap, not their
        // average: check:raceReferenceAtLeader4thCrossing = (3576430, [87098, 86394, 86015], 86394).
        let fewer = try #require(PitCircle.layout(at: Fixture.raceStart + 3_576_430, session: race))
        #expect(fewer.referenceLapMs == 86_394)
        #expect(fewer.greenLaps == 0)

        // A lap under a safety car at its midpoint, or with a stop in it, isn't green.
        let session = RaceFixture.synthetic(
            timing: laps(8, more: [timingLine("00:07:50.000", [("44", #""InPit":true"#)]),
                                   timingLine("00:08:15.000", [("44", #""InPit":false,"PitOut":true"#)])]),
            trackStatus: lines(#"00:06:40.000{"Status":"4"}"#, #"00:07:10.000{"Status":"1"}"#))
        let s: UTCms = 1_000_000
        // Leader's crossings at 100, 190, ... 730 s; the SC covers the midpoint of 370–460 s.
        #expect(PitCircle.greenLaps(of: "1", at: s + 730_000, session: session).count == 6)
        // 44 is in the pits from 470 s to 495 s: its lap 460–550 isn't green, nor is 370–460
        // (the SC); at 500 s the lap with the stop isn't finished.
        #expect(PitCircle.greenLaps(of: "44", at: s + 730_000, session: session).count == 5)
        #expect(PitCircle.greenLaps(of: "44", at: s + 500_000, session: session).count == 3)
    }

    @Test func referenceFallsBackToTypicalThenLast() throws {
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [], typicalLapMs: 88_000, lastLapMs: 90_000) == 88_000)
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [], typicalLapMs: nil, lastLapMs: 90_000) == 90_000)
        #expect(PitCircle.referenceLapMs(leaderGreenLaps: [], typicalLapMs: nil, lastLapMs: nil) == nil)

        // 0.98: joined live part-way, the opening snapshot already has the leader on lap 30 with a
        // last lap of 1:26.500, but no crossing has been seen here. Once it crosses, its last lap
        // stands in until two crossings make a lap; then its typical lap (86 s between crossings,
        // not F1's 1:25.800) takes over until it has 5 green laps.
        let s: UTCms = 1_000_000
        let joined = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [("1", #""Position":"1","NumberOfLaps":30,"LastLapTime":{"Value":"1:26.500"},"GapToLeader":"LAP 31""#),
                                        ("4", #""Position":"2","NumberOfLaps":30,"GapToLeader":"+3.000","IntervalToPositionAhead":{"Value":"+3.000"}"#)]),
            timingLine("00:00:40.000", [("1", #""NumberOfLaps":31,"LastLapTime":{"Value":"1:26.900"}"#)]),
            timingLine("00:02:06.000", [("1", #""NumberOfLaps":32,"LastLapTime":{"Value":"1:25.800"}"#)]),
        ], start: s)
        #expect(PitCircle.layout(at: s + 39_999, session: joined) == nil)
        #expect(PitCircle.layout(at: s + 40_000, session: joined)?.referenceLapMs == 86_900)
        #expect(PitCircle.layout(at: s + 40_000, session: joined)?.greenLaps == 0)
        #expect(PitCircle.layout(at: s + 126_000, session: joined)?.referenceLapMs == 86_000)
        #expect(PitCircle.layout(at: s + 126_000, session: joined)?.greenLaps == 0)

        // Every lap so far under a safety car: none green, so the typical lap (the median of the
        // last 5) stands in.
        let yellow = RaceFixture.synthetic(timing: laps(4, lapMs: 120_000), trackStatus: lines(#"00:00:01.000{"Status":"4"}"#))
        let underSC = try #require(PitCircle.layout(at: s + 500_000, session: yellow))
        #expect(underSC.referenceLapMs == 120_000)
        #expect(underSC.greenLaps == 0)
    }

    @Test func noCircleOnAZeroReferenceLap() throws {
        // Joined live part-way; F1's last lap reads "0.000" when the leader crosses, and no lap
        // has been timed here yet: no reference, so no circle (and no trap dividing by it).
        let s: UTCms = 1_000_000
        let zero = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [("1", #""Position":"1","NumberOfLaps":30,"GapToLeader":"LAP 31""#),
                                        ("4", #""Position":"2","NumberOfLaps":30,"GapToLeader":"+3.000","IntervalToPositionAhead":{"Value":"+3.000"}"#)]),
            timingLine("00:00:40.000", [("1", #""NumberOfLaps":31,"LastLapTime":{"Value":"0.000"}"#)]),
        ], start: s)
        #expect(PitCircle.layout(at: s + 40_000, session: zero) == nil)
        #expect(PitCircle.layout(at: s + 60_000, session: zero) == nil)
        // A real last lap later brings it in.
        let later = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [("1", #""Position":"1","NumberOfLaps":30,"GapToLeader":"LAP 31""#)]),
            timingLine("00:00:40.000", [("1", #""NumberOfLaps":31,"LastLapTime":{"Value":"0.000"}"#)]),
            timingLine("00:00:41.000", [("1", #""LastLapTime":{"Value":"1:26.900"}"#)]),
        ], start: s)
        #expect(PitCircle.layout(at: s + 41_000, session: later)?.referenceLapMs == 86_900)
    }

    @Test func circleHoldsLeaderOnASlowLap() throws {
        // Five green 90 s laps (lines at 100 … 550 s), then a 150 s lap (a safety car, a stop or
        // a red flag): the leader is held just short of the line until it crosses at 700 s,
        // instead of wrapping round and jumping back.
        let s: UTCms = 1_000_000
        let session = RaceFixture.synthetic(timing: laps(6, more: [timingLine("00:11:40.000", [("1", #""NumberOfLaps":7"#)])]),
                                            start: s)
        func leader(_ u: UTCms) throws -> Double { try #require(PitCircle.layout(at: u, session: session)?.cars.first?.fraction) }
        #expect(PitCircle.layout(at: s + 595_000, session: session)?.referenceLapMs == 90_000)
        #expect(abs(try leader(s + 595_000) - 0.5) < 1e-9)
        #expect(try leader(s + 640_000) == 0.999)
        #expect(try leader(s + 699_999) == 0.999)
        // A red flag that runs on: still held, never spinning.
        #expect(try leader(s + 3_600_000) == 0.999)
        #expect(try leader(s + 700_000) == 0)
        // The others keep their gap behind the held leader.
        let held = try #require(PitCircle.layout(at: s + 690_000, session: session))
        #expect(abs(try #require(held.cars.last?.fraction) - (0.999 - 2.0 / 90)) < 1e-9)
    }

    @Test func lappedCarsStayOnTheCircle() throws {
        // 3 is a lap down ("1L" gap and interval); 4 is 2 s behind it with its gap also "+1 LAP".
        // 3's gap is its crossing of the latest lap both it and the leader finished, less the
        // leader's; 4 chains from 3.
        let s: UTCms = 1_000_000
        let session = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [
                ("1", #""Position":"1","GapToLeader":"","IntervalToPositionAhead":{"Value":""}"#),
                ("2", #""Position":"2","GapToLeader":"+5.000","IntervalToPositionAhead":{"Value":"+5.000"}"#),
                ("3", #""Position":"3","GapToLeader":"1L","IntervalToPositionAhead":{"Value":"1L"}"#),
                ("4", #""Position":"4","GapToLeader":"+1 LAP","IntervalToPositionAhead":{"Value":"+2.000"}"#),
            ]),
            timingLine("00:01:40.000", [("1", #""NumberOfLaps":1"#)]),
            timingLine("00:01:45.000", [("2", #""NumberOfLaps":1"#)]),
            timingLine("00:03:10.000", [("1", #""NumberOfLaps":2"#)]),
            timingLine("00:03:15.000", [("2", #""NumberOfLaps":2"#), ("3", #""NumberOfLaps":1"#)]),
            timingLine("00:03:17.000", [("4", #""NumberOfLaps":1"#)]),
            timingLine("00:04:40.000", [("1", #""NumberOfLaps":3"#)]),
            timingLine("00:04:45.000", [("2", #""NumberOfLaps":3"#)]),
            timingLine("00:04:50.000", [("3", #""NumberOfLaps":2"#)]),
            timingLine("00:04:52.000", [("4", #""NumberOfLaps":2"#)]),
        ], start: s)
        // At 289 s the latest lap both finished is lap 1 (195 − 100 s), but the leader finished
        // lap 2 at 190 s and 3 hasn't: 3 is at least 289 − 190 = 99 s behind.
        let early = try #require(PitCircle.layout(at: s + 289_000, session: session))
        #expect(early.cars.map(\.number) == ["1", "2", "3", "4"])
        #expect(early.cars.map(\.gapToLeaderMs) == [0, 5_000, 99_000, 101_000])
        // At 280 s that bound (90 s) is less than the crossings' 95 s.
        let atLap1 = try #require(PitCircle.layout(at: s + 280_000, session: session))
        #expect(atLap1.cars.map(\.gapToLeaderMs) == [0, 5_000, 95_000, 97_000])
        // At 300 s it is lap 2: 290 − 190 s.
        let circle = try #require(PitCircle.layout(at: s + 300_000, session: session))
        #expect(circle.cars.map(\.gapToLeaderMs) == [0, 5_000, 100_000, 102_000])
        // Placed by the crossings, labelled with F1's own words where F1's gap isn't a time.
        let three = try #require(circle.cars.first { $0.number == "3" })
        let four = try #require(circle.cars.first { $0.number == "4" })
        #expect(three.gapToLeader == "1L" && three.gapToAhead == "1L")
        #expect(four.gapToLeader == "+1 LAP" && four.gapToAhead == "+2.0")
        // And the stop maths counts them: 2 stopping for 96 s comes out 1 s behind 3, in P3.
        #expect(PitCircle.rejoin(car: "2", at: s + 300_000, session: session, pitLossMs: 96_000)
                == Rejoin(position: 3, behind: "3", gapMs: 1_000))
    }

    @Test func parkedCarDropsBackAndIsNoRejoinMark() throws {
        // 3 ("1L") crosses lap 1 at 195 s, then goes into its garage at 250 s and stays there.
        // The leader crosses at 100, 190, 280, 370 s. 3's gap is at least the time since the
        // leader finished lap 2 (190 s), so it grows with t instead of freezing at 95 s.
        let s: UTCms = 1_000_000
        let session = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [
                ("1", #""Position":"1","GapToLeader":"","IntervalToPositionAhead":{"Value":""}"#),
                ("2", #""Position":"2","GapToLeader":"+5.000","IntervalToPositionAhead":{"Value":"+5.000"}"#),
                ("3", #""Position":"3","GapToLeader":"1L","IntervalToPositionAhead":{"Value":"1L"}"#),
            ]),
            timingLine("00:01:40.000", [("1", #""NumberOfLaps":1"#)]),
            timingLine("00:01:45.000", [("2", #""NumberOfLaps":1"#)]),
            timingLine("00:03:10.000", [("1", #""NumberOfLaps":2"#)]),
            timingLine("00:03:15.000", [("2", #""NumberOfLaps":2"#), ("3", #""NumberOfLaps":1"#)]),
            timingLine("00:04:10.000", [("3", #""InPit":true"#)]),
            timingLine("00:04:40.000", [("1", #""NumberOfLaps":3"#)]),
            timingLine("00:04:45.000", [("2", #""NumberOfLaps":3"#)]),
            timingLine("00:06:10.000", [("1", #""NumberOfLaps":4"#)]),
            timingLine("00:06:15.000", [("2", #""NumberOfLaps":4"#)]),
        ], start: s)
        func gap(_ u: UTCms) -> Int? { PitCircle.layout(at: s + u, session: session)?.cars.first { $0.number == "3" }?.gapToLeaderMs }
        #expect(gap(300_000) == 110_000)
        #expect(gap(360_000) == 170_000)
        #expect(gap(600_000) == 410_000)
        // 2 stopping for 106 s would come out at 111 s: without the parked car's 110 s it comes
        // out behind the leader, in P2, not "behind 3".
        let rejoin = try #require(PitCircle.rejoin(car: "2", at: s + 300_000, session: session, pitLossMs: 106_000))
        #expect(rejoin == Rejoin(position: 2, behind: "1", gapMs: 111_000))
        // Out of the pit lane it counts again (the same 3 on track at 245 s: 95 s behind as of
        // its lap 1 crossing, 245 − 190 = 55 s at least).
        #expect(PitCircle.rejoin(car: "2", at: s + 245_000, session: session, pitLossMs: 91_000)
                == Rejoin(position: 3, behind: "3", gapMs: 1_000))
    }

    @Test func fallbackGapNeverAheadOfTheLeader() throws {
        // 2 takes the lead mid-lap; 1, now second, sends no gap yet. By the crossings 1 finished
        // lap 1 5 s before 2 did: −5 s, floored at 0, and the leader still sorts first.
        let s: UTCms = 1_000_000
        let session = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [("1", #""Position":"1""#), ("2", #""Position":"2","GapToLeader":"+5.000""#)]),
            timingLine("00:01:40.000", [("1", #""NumberOfLaps":1"#)]),
            timingLine("00:01:45.000", [("2", #""NumberOfLaps":1,"LastLapTime":{"Value":"1:30.000"}"#)]),
            timingLine("00:02:30.000", [("2", #""Position":"1","GapToLeader":"","IntervalToPositionAhead":{"Value":""}"#),
                                        ("1", #""Position":"2","GapToLeader":"","IntervalToPositionAhead":{"Value":""}"#)]),
        ], start: s)
        let circle = try #require(PitCircle.layout(at: s + 160_000, session: session))
        #expect(circle.leader == "2")
        #expect(circle.cars.map(\.number) == ["2", "1"])
        #expect(circle.cars.map(\.gapToLeaderMs) == [0, 0])
    }

    @Test func pitLossMedianThenStoredThen22s() {
        #expect(PitCircle.pitLossMs(sessionStops: [25_000, 21_000, 20_000], storedMs: 19_000) == 21_000)
        #expect(PitCircle.pitLossMs(sessionStops: [20_000, 24_000], storedMs: nil) == 24_000)
        #expect(PitCircle.pitLossMs(sessionStops: [], storedMs: 19_500) == 19_500)
        #expect(PitCircle.pitLossMs(sessionStops: [], storedMs: nil) == 22_000)
        #expect(PitCircle.typicalLossMs == 22_000)

        // 44 laps in 90 s (lines at 100, 190, 280, 370 s), then pits: in at 445 s, the count
        // rising in the lane at 465 s, out at 470 s, and the next line at 576 s. In-lap and
        // out-lap 95 + 111 s against 2 × 90 s: 26 s lost.
        let s: UTCms = 1_000_000
        let timing = laps(4, more: [
            timingLine("00:07:25.000", [("44", #""InPit":true"#)]),
            timingLine("00:07:45.000", [("44", #""NumberOfLaps":5"#)]),
            timingLine("00:07:50.000", [("44", #""InPit":false,"PitOut":true"#)]),
            timingLine("00:09:36.000", [("44", #""NumberOfLaps":6"#)]),
        ])
        let session = RaceFixture.synthetic(timing: timing, start: s)
        #expect(PitCircle.sessionStops(until: s + 575_999, session: session).isEmpty)
        #expect(PitCircle.sessionStops(until: s + 576_000, session: session) == [26_000])
        #expect(PitCircle.pitLossMs(at: s + 576_000, session: session, storedMs: 19_000) == 26_000)
        #expect(PitCircle.pitLossMs(at: s + 575_999, session: session, storedMs: 19_000) == 19_000)
        #expect(PitCircle.layout(at: s + 576_000, session: session)?.pitLossMs == 26_000)
        #expect(PitCircle.layout(at: s + 576_000, session: session)?.measuredStops == 1)
        // With a VSC during those laps the same stop isn't clean.
        let flagged = RaceFixture.synthetic(timing: timing, trackStatus: lines(#"00:08:20.000{"Status":"6"}"#, #"00:08:30.000{"Status":"1"}"#), start: s)
        #expect(PitCircle.sessionStops(until: s + 576_000, session: flagged).isEmpty)
        #expect(PitCircle.layout(at: s + 576_000, session: flagged)?.pitLossMs == 22_000)

        // The baseline is green pace only: two 150 s safety-car laps (lines at 100, 190, 340,
        // 490, 580 s; SC 200–480 s) don't count, so the stop (in 655 s, line in the lane 675 s,
        // out 680 s, next line 786 s: 95 + 111 s) still costs 206 − 2 × 90 = 26 s. With every
        // lap as the baseline the median would be 150 s and the stop would be thrown out.
        let slow = RaceFixture.synthetic(
            timing: [timingLine("00:00:00.000", [("44", #""Position":"1""#)])]
                + ["00:01:40.000", "00:03:10.000", "00:05:40.000", "00:08:10.000", "00:09:40.000"].enumerated().map {
                    timingLine($0.element, [("44", #""NumberOfLaps":\#($0.offset + 1)"#)])
                }
                + [timingLine("00:10:55.000", [("44", #""InPit":true"#)]),
                   timingLine("00:11:15.000", [("44", #""NumberOfLaps":6"#)]),
                   timingLine("00:11:20.000", [("44", #""InPit":false,"PitOut":true"#)]),
                   timingLine("00:13:06.000", [("44", #""NumberOfLaps":7"#)])],
            trackStatus: lines(#"00:03:20.000{"Status":"4"}"#, #"00:08:00.000{"Status":"1"}"#), start: s)
        #expect(PitCircle.sessionStops(until: s + 786_000, session: slow) == [26_000])
    }

    @Test func circleNilBeforeFirstLap() throws {
        let race = try RaceFixture.race()
        let first = Fixture.raceStart + 3_316_923  // check:raceCar12CrossingOffsets
        #expect(PitCircle.layout(at: Fixture.raceLightsOut + 1, session: race) == nil)
        #expect(PitCircle.layout(at: first - 1, session: race) == nil)
        // F1 sends no time for lap 1 (check:raceLeaderLap1LastLapTimeValue = ''): its last lap
        // is lights out to the line, check:raceLeaderLap1FromLightsOut = 92347.
        let start = try #require(PitCircle.layout(at: first, session: race))
        #expect(start.referenceLapMs == 92_347)
        #expect(start.greenLaps == 0)
        #expect(start.cars.first?.number == "12")
        #expect(start.cars.first?.angle == 0)
        #expect(PitCircle.layout(at: RaceFixture.raceT, session: try RaceFixture.quali()) == nil)
        // A first lap that can't have been run on track (5 minutes from lights out: a red flag on
        // lap 1) isn't a reference: the circle waits for a lap between two crossings.
        let s: UTCms = 1_000_000
        let redLapOne = RaceFixture.synthetic(
            timing: [timingLine("00:00:00.000", [("1", #""Position":"1""#)]),
                     timingLine("00:05:10.000", [("1", #""NumberOfLaps":1"#)]),
                     timingLine("00:06:40.000", [("1", #""NumberOfLaps":2"#)])],
            sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#), start: s)
        #expect(PitCircle.layout(at: s + 310_000, session: redLapOne) == nil)
        #expect(PitCircle.layout(at: s + 400_000, session: redLapOne)?.referenceLapMs == 90_000)
        let quickLapOne = RaceFixture.synthetic(
            timing: [timingLine("00:00:00.000", [("1", #""Position":"1""#)]),
                     timingLine("00:01:45.000", [("1", #""NumberOfLaps":1"#)])],
            sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#), start: s)
        #expect(PitCircle.layout(at: s + 105_000, session: quickLapOne)?.referenceLapMs == 95_000)

        // At lights out + 10 min: check:raceLeaderFractionAtLightsOutPlus10min,
        // check:raceCar1FractionAtLightsOutPlus10min, check:raceCar44FractionAtLightsOutPlus10min,
        // and every racing car in gap order (check:raceGapsToLeaderAtLightsOutPlus10min; 77 retired).
        let t = RaceFixture.raceT
        let circle = try #require(PitCircle.layout(at: t, session: race))
        #expect(circle.leader == "12")
        #expect(circle.lap == 7)  // check:raceLapCountCurrentLapAtLightsOutPlus10min
        #expect(circle.pitLossMs == 22_000 && circle.measuredStops == 0)
        #expect(circle.cars.map(\.number).joined(separator: ",") == "12,1,6,30,63,27,3,81,23,44,87,41,16,14,55,10,43,51,18,5,11")
        #expect(circle.cars.map(\.gapToLeaderMs).prefix(3) == [0, 4_401, 6_236])
        func car(_ n: String) throws -> PitCircleCar { try #require(circle.cars.first { $0.number == n }) }
        #expect(abs(try car("12").fraction - 0.876611) < 1e-6)
        #expect(abs(try car("1").fraction - 0.825664) < 1e-6)
        #expect(abs(try car("44").fraction - 0.668345) < 1e-6)
        #expect(abs(try car("44").angle - 0.668345 * 360) < 1e-3)
        #expect(try car("12").gapToLeader == "Leader")
        #expect(try car("1").gapToLeader == "+4.4")
        #expect(try car("1").gapToAhead == "+4.4")
        #expect(try car("6").gapToAhead == "+1.8")
        // The leader's car ahead round the circle is the last car: a lap less its 29.925 s.
        #expect(try car("12").gapToAhead == "+56.5")
        #expect(try car("44").tla == "HAM")  // check:raceTlas11_16_44

        // Nothing later than t is read.
        for u in [first - 1, first, t] {
            let cut = try RaceFixture.load("sp26-race", streamStart: Fixture.raceStart, cutAt: u)
            #expect(PitCircle.layout(at: u, session: cut) == PitCircle.layout(at: u, session: race))
        }
    }

    @Test func rejoinTextFormat() throws {
        let race = try RaceFixture.race()
        let t = RaceFixture.raceT
        // check:raceRejoin44At22sAtLightsOutPlus10min = (21, '11', 10066), check:raceTlas11_16_44
        let late = try #require(PitCircle.rejoin(car: "44", at: t, session: race, pitLossMs: 22_000))
        #expect(late == Rejoin(position: 21, behind: "11", gapMs: 10_066))
        #expect(late.text(car: "44", session: race) == "If HAM stops now, out 10.1 s behind PER")
        #expect(late.consoleText(session: race) == "Pit now → P21 behind PER")
        // check:raceRejoin44At5sAtLightsOutPlus10min = (13, '16', 2252)
        let quick = try #require(PitCircle.rejoin(car: "44", at: t, session: race, pitLossMs: 5_000))
        #expect(quick == Rejoin(position: 13, behind: "16", gapMs: 2_252))
        #expect(quick.text(car: "44", session: race) == "If HAM stops now, out 2.3 s behind LEC")
        #expect(quick.consoleText(session: race) == "Pit now → P13 behind LEC")
        // The leader with a stop shorter than its lead stays ahead: 4.401 s over 1, less 1 s.
        let lead = try #require(PitCircle.rejoin(car: "12", at: t, session: race, pitLossMs: 1_000))
        #expect(lead == Rejoin(position: 1, behind: nil, gapMs: 3_401))
        #expect(lead.text(car: "12", session: race) == "If ANT stops now, out in the lead")  // check:raceTlas12_23_87
        #expect(lead.consoleText(session: race) == "Pit now → P1")
        // A retired car, a car with no timing and a non-race session have none.
        #expect(PitCircle.rejoin(car: "77", at: t, session: race, pitLossMs: 22_000) == nil)
        #expect(PitCircle.rejoin(car: "99", at: t, session: race, pitLossMs: 22_000) == nil)
        #expect(PitCircle.rejoin(car: "44", at: t, session: try RaceFixture.quali(), pitLossMs: 22_000) == nil)

        let cut = try RaceFixture.load("sp26-race", streamStart: Fixture.raceStart, cutAt: t)
        #expect(PitCircle.rejoin(car: "44", at: t, session: cut, pitLossMs: 22_000) == late)
    }
}

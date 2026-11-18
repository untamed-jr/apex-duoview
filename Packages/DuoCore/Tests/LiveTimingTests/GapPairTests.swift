import Testing
import Foundation
@testable import LiveTiming

@Suite struct GapPairTests {
    static let s: UTCms = 1_000_000

    /// A race of five cars, P1...P5 (numbers 1, 2, 3, 4, 5). Each of `extra` lines is added after.
    static func session(type: String = "Race", cars: [(String, String)]? = nil, extra: [StreamLine] = [],
                        laps: Bool = true) -> LoadedSession {
        let base: [(String, String)] = cars ?? [
            ("1", #""Position":"1","GapToLeader":"LAP 3","IntervalToPositionAhead":{"Value":""}"#),
            ("2", #""Position":"2","GapToLeader":"+2.000","IntervalToPositionAhead":{"Value":"+2.000"}"#),
            ("3", #""Position":"3","GapToLeader":"+5.500","IntervalToPositionAhead":{"Value":"+3.000"}"#),
            ("4", #""Position":"4","GapToLeader":"+9.000","IntervalToPositionAhead":{"Value":"+3.500"}"#),
            ("5", #""Position":"5","GapToLeader":"1L","IntervalToPositionAhead":{"Value":"1L"}"#),
        ]
        var lines = [timingLine("00:00:00.000", base)]
        if laps {
            lines.append(timingLine("00:01:40.000", ["1", "2", "3", "4", "5"].map { ($0, #""NumberOfLaps":1"#) }))
        }
        return RaceFixture.synthetic(type: type, timing: lines + extra, start: s)
    }

    static let t: UTCms = s + 110_000

    @Test func adjacentUsesInterval() {
        let session = Self.session()
        // 3 is 5.500 behind the leader and 2 is 2.000 behind it, but the interval says 3.000.
        #expect(GapPair.reading("2", "3", at: Self.t, session: session)
                == .gap(ms: 3000, ahead: "2", behind: "3", trend: nil, heat: 0))
        // Either way round.
        #expect(GapPair.reading("3", "2", at: Self.t, session: session)
                == .gap(ms: 3000, ahead: "2", behind: "3", trend: nil, heat: 0))
        #expect(GapPair.reading("3", "4", at: Self.t, session: session)
                == .gap(ms: 3500, ahead: "3", behind: "4", trend: nil, heat: 0))
    }

    @Test func nonAdjacentSubtractsGaps() {
        let session = Self.session()
        #expect(GapPair.reading("2", "4", at: Self.t, session: session)
                == .gap(ms: 7000, ahead: "2", behind: "4", trend: nil, heat: 0))
        // With the leader, the gap to the leader is the whole gap.
        #expect(GapPair.reading("1", "3", at: Self.t, session: session)
                == .gap(ms: 5500, ahead: "1", behind: "3", trend: nil, heat: 0))
    }

    @Test func lappedKeepsF1Text() {
        let session = Self.session()
        #expect(GapPair.reading("4", "5", at: Self.t, session: session)
                == .lapped(text: "1L", ahead: "4", behind: "5"))
        // A non-adjacent pair with one lapped car: F1's word for it.
        #expect(GapPair.reading("3", "5", at: Self.t, session: session)
                == .lapped(text: "1L", ahead: "3", behind: "5"))
    }

    @Test func inPitAndOut() {
        let pit = Self.session(extra: [timingLine("00:01:45.000", [("3", #""InPit":true"#)])])
        #expect(GapPair.reading("2", "3", at: Self.t, session: pit) == .inPit(car: "3"))
        #expect(GapPair.reading("3", "4", at: Self.t, session: pit) == .inPit(car: "3"))
        let out = Self.session(extra: [timingLine("00:01:45.000", [("4", #""Retired":true,"Stopped":true"#)])])
        #expect(GapPair.reading("3", "4", at: Self.t, session: out) == .out(car: "4"))
        // A car with no timing at all is out.
        #expect(GapPair.reading("3", "99", at: Self.t, session: out) == .out(car: "99"))
    }

    @Test func notRaceInQualifying() {
        let session = Self.session(type: "Qualifying")
        #expect(GapPair.reading("2", "3", at: Self.t, session: session) == .notRace)
        #expect(GapPair.defaultPair(favourite: "2", at: Self.t, session: session) == nil)
    }

    @Test func beforeFirstLap() {
        let session = Self.session(laps: false)
        #expect(GapPair.reading("2", "3", at: Self.t, session: session) == .beforeFirstLap)
        // Before any car has crossed the line, even where laps are later.
        #expect(GapPair.reading("2", "3", at: Self.s + 90_000, session: Self.session()) == .beforeFirstLap)
    }

    @Test func trendClosingOverThreeLaps() {
        // Car 3 crosses at 100, 190, 280 and 370 s; at 380 s its last 3 laps took 270 s, so the
        // gap then is read at 110 s: car 3 was 5.000 behind the leader and car 2 2.000 (3.000
        // apart). Later the gap to the leader changes, giving the gap now.
        var crossings: [StreamLine] = []
        for (i, stamp) in ["00:03:10.000", "00:04:40.000", "00:06:10.000"].enumerated() {
            crossings.append(timingLine(stamp, [("3", #""NumberOfLaps":\#(i + 2)"#)]))
        }
        let cars = [
            ("1", #""Position":"1","GapToLeader":"","IntervalToPositionAhead":{"Value":""}"#),
            ("2", #""Position":"2","GapToLeader":"+2.000","IntervalToPositionAhead":{"Value":"+2.000"}"#),
            ("3", #""Position":"3","GapToLeader":"+5.000","IntervalToPositionAhead":{"Value":"+3.000"}"#),
        ]
        func run(laterGap: String, interval: String) -> GapReading {
            let change = timingLine("00:05:00.000", [
                ("3", #""GapToLeader":"\#(laterGap)","IntervalToPositionAhead":{"Value":"\#(interval)"}"#),
            ])
            let session = Self.session(cars: cars, extra: crossings + [change])
            return GapPair.reading("2", "3", at: Self.s + 380_000, session: session)
        }
        #expect(run(laterGap: "+4.000", interval: "+2.000") == .gap(ms: 2000, ahead: "2", behind: "3", trend: .closing, heat: 0.5))
        #expect(run(laterGap: "+6.000", interval: "+4.000") == .gap(ms: 4000, ahead: "2", behind: "3", trend: .growing, heat: 0))
        // Within 100 ms is steady.
        #expect(run(laterGap: "+5.050", interval: "+3.050") == .gap(ms: 3050, ahead: "2", behind: "3", trend: .steady, heat: 0))
        // Fewer than 3 laps in: no trend.
        let early = Self.session(cars: cars, extra: Array(crossings.prefix(1)))
        guard case let .gap(_, _, _, trend, _) = GapPair.reading("2", "3", at: Self.s + 200_000, session: early) else {
            Issue.record("expected a gap")
            return
        }
        #expect(trend == nil)
    }

    @Test func heatStops() {
        #expect(GapPair.heat(gapMs: 3000) == 0)
        #expect(GapPair.heat(gapMs: 2000) == 0.5)
        #expect(GapPair.heat(gapMs: 1000) == 1)
        #expect(GapPair.heat(gapMs: 500) == 1)
        #expect(GapPair.heat(gapMs: 5000) == 0)
        #expect(abs(GapPair.heat(gapMs: 1500) - 0.75) < 1e-9)
        #expect(GapPair.heat(gapMs: 0) == 1)
    }

    @Test func defaultPairNearerRival() throws {
        let session = Self.session()
        // 3 has 3.000 to 2 ahead and 3.500 to 4 behind: the car ahead is nearer.
        #expect(try #require(GapPair.defaultPair(favourite: "3", at: Self.t, session: session)) == ("2", "3"))
        #expect(try #require(GapPair.defaultPair(favourite: "2", at: Self.t, session: session)) == ("1", "2"))
        // The leader has only the car behind.
        #expect(try #require(GapPair.defaultPair(favourite: "1", at: Self.t, session: session)) == ("1", "2"))
        // 4: 3.500 ahead; 5 behind is lapped (no time), so the car ahead.
        #expect(try #require(GapPair.defaultPair(favourite: "4", at: Self.t, session: session)) == ("3", "4"))
        // The last car has only the car ahead.
        #expect(try #require(GapPair.defaultPair(favourite: "5", at: Self.t, session: session)) == ("4", "5"))
        // A nearer car behind.
        let close = Self.session(extra: [timingLine("00:01:45.000", [("4", #""IntervalToPositionAhead":{"Value":"+1.000"}"#)])])
        #expect(try #require(GapPair.defaultPair(favourite: "3", at: Self.t, session: close)) == ("3", "4"))
    }

    @Test func defaultPairWithoutFavourite() throws {
        let session = Self.session()
        #expect(try #require(GapPair.defaultPair(favourite: nil, at: Self.t, session: session)) == ("1", "2"))
        // A favourite who isn't in the race.
        #expect(try #require(GapPair.defaultPair(favourite: "99", at: Self.t, session: session)) == ("1", "2"))
    }

    @Test func shiftStopsAtEnds() throws {
        let session = Self.session()
        #expect(try #require(GapPair.shifted(("2", "3"), by: 1, at: Self.t, session: session)) == ("3", "4"))
        #expect(try #require(GapPair.shifted(("2", "3"), by: -1, at: Self.t, session: session)) == ("1", "2"))
        #expect(GapPair.shifted(("1", "2"), by: -1, at: Self.t, session: session) == nil)
        #expect(GapPair.shifted(("4", "5"), by: 1, at: Self.t, session: session) == nil)
        #expect(try #require(GapPair.shifted(("3", "2"), by: 1, at: Self.t, session: session)) == ("3", "4"))
        // A retired car is stepped over.
        let out = Self.session(extra: [timingLine("00:01:45.000", [("4", #""Retired":true,"Stopped":true"#)])])
        #expect(try #require(GapPair.shifted(("2", "3"), by: 1, at: Self.t, session: out)) == ("3", "5"))
    }

    @Test func extremeInputsDoNotTrap() {
        #expect(GapPair.heat(gapMs: Int.min) == 1)
        #expect(GapPair.heat(gapMs: Int.max) == 0)
        let session = Self.session()
        #expect(GapPair.shifted(("2", "3"), by: Int.max, at: Self.t, session: session) == nil)
        #expect(GapPair.shifted(("2", "3"), by: Int.min, at: Self.t, session: session) == nil)
    }

    @Test func outBeatsPit() {
        let both = Self.session(extra: [timingLine("00:01:45.000", [
            ("3", #""InPit":true"#), ("4", #""Retired":true,"Stopped":true"#),
        ])])
        #expect(GapPair.reading("3", "4", at: Self.t, session: both) == .out(car: "4"))
        #expect(GapPair.reading("4", "3", at: Self.t, session: both) == .out(car: "4"))
    }

    @Test func shiftFromPairWithFrontCarOut() throws {
        // 3 has retired; the pair (3, 4) is read from its place, between 2 and 4.
        let out = Self.session(extra: [timingLine("00:01:45.000", [("3", #""Retired":true,"Stopped":true"#)])])
        #expect(try #require(GapPair.shifted(("3", "4"), by: 1, at: Self.t, session: out)) == ("4", "5"))
        #expect(try #require(GapPair.shifted(("3", "4"), by: -1, at: Self.t, session: out)) == ("2", "4"))
    }

    @Test func nothingAfterT() {
        let later = timingLine("00:02:00.000", [("3", #""IntervalToPositionAhead":{"Value":"+0.800"}"#)])
        let session = Self.session(extra: [later])
        #expect(GapPair.reading("2", "3", at: Self.t, session: session)
                == .gap(ms: 3000, ahead: "2", behind: "3", trend: nil, heat: 0))
        #expect(GapPair.reading("2", "3", at: Self.s + 120_000, session: session)
                == .gap(ms: 800, ahead: "2", behind: "3", trend: nil, heat: 1))
    }
}

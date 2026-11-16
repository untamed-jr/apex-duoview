import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct BattleTests {
    static func car(_ position: Int, _ interval: String) -> DriverTimingState {
        DriverTimingState(position: position, interval: interval)
    }

    @Test func battleNeedsTwoUpdates() {
        let apart: [String: DriverTimingState] = ["1": Self.car(1, "LAP 3"), "4": Self.car(2, "+1.400"), "16": Self.car(3, "+2.000")]
        let close: [String: DriverTimingState] = ["1": Self.car(1, "LAP 3"), "4": Self.car(2, "+0.900"), "16": Self.car(3, "+2.000")]
        #expect(Battle.rivals(of: "4", updates: []).isEmpty)
        #expect(Battle.rivals(of: "4", updates: [close]).isEmpty)
        #expect(Battle.rivals(of: "4", updates: [apart, close]).isEmpty)
        let closer: [String: DriverTimingState] = ["1": Self.car(1, "LAP 3"), "4": Self.car(2, "+0.800"), "16": Self.car(3, "+2.000")]
        #expect(Battle.rivals(of: "4", updates: [close, closer]) == ["1"])
        #expect(Battle.rivals(of: "1", updates: [close, closer]) == ["4"])
        // An unchanged snapshot is no second update.
        #expect(Battle.rivals(of: "4", updates: [close, close]).isEmpty)
        #expect(Battle.rivals(of: "4", updates: [close, closer, apart]).isEmpty)  // the last two only
        #expect(Battle.rivals(of: "4", updates: [apart, close, closer]) == ["1"])
        // Exactly 1.0 s counts; the car behind counts too, ahead first.
        let both: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+1.000"), "16": Self.car(3, "+0.300")]
        let both2: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+0.950"), "16": Self.car(3, "+0.250")]
        #expect(Battle.rivals(of: "4", updates: [both, both2]) == ["1", "16"])
        // An overtake between the updates: still the same pair, still within 1.0 s.
        let swapped: [String: DriverTimingState] = ["4": Self.car(1, ""), "1": Self.car(2, "+0.200"), "16": Self.car(3, "+3.0")]
        #expect(Battle.rivals(of: "4", updates: [close, swapped]) == ["1"])
        // A car that changed between the updates isn't a battle of two updates.
        let other: [String: DriverTimingState] = ["16": Self.car(1, ""), "4": Self.car(2, "+0.500"), "1": Self.car(3, "+5.0")]
        #expect(Battle.rivals(of: "4", updates: [close, other]).isEmpty)
        // Laps, blanks, and cars in the pits or out are no battle; unknown cars neither.
        let laps: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "1L"), "16": Self.car(3, "")]
        let laps2: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+1 LAP"), "16": Self.car(3, "")]
        #expect(Battle.rivals(of: "4", updates: [laps, laps2]).isEmpty)
        var pitting = closer
        pitting["1"]?.inPit = true
        #expect(Battle.rivals(of: "4", updates: [close, pitting]).isEmpty)
        #expect(Battle.rivals(of: "99", updates: [close, closer]).isEmpty)
        #expect(Battle.gapSeconds("+0.454") == 0.454)
        #expect(Battle.gapSeconds("LAP 7") == nil)
        #expect(Battle.gapSeconds("+1 LAP") == nil)
        #expect(Battle.gapSeconds("") == nil)
        #expect(Battle.gapSeconds("-0.2") == nil)
    }

    @Test func battleIgnoresOtherCarsUpdates() throws {
        let apart: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+1.500"), "16": Self.car(3, "+2.000")]
        let close: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+0.900"), "16": Self.car(3, "+2.000")]
        let other1: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+0.900"), "16": Self.car(3, "+2.100")]
        let other2: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+0.900"), "16": Self.car(3, "+2.200")]
        // Two updates of car 16 since 4 closed up: still one update of the pair.
        #expect(Battle.rivals(of: "4", updates: [apart, close, other1, other2]).isEmpty)
        // The rival's own update is the second.
        var rival = other2
        rival["1"]?.lastLapMs = 86_000
        #expect(Battle.rivals(of: "4", updates: [apart, close, other1, other2, rival]) == ["1"])

        // The same from the timeline, as the tower reads it.
        let session = FixtureSession.synthetic(type: "Race", timing: [
            timingLine("00:00:01.000", [("1", #""Position":"1""#), ("4", #""Position":"2","IntervalToPositionAhead":{"Value":"+1.500"}"#),
                                        ("16", #""Position":"3","IntervalToPositionAhead":{"Value":"+2.000"}"#)]),
            timingLine("00:00:02.000", [("4", #""IntervalToPositionAhead":{"Value":"+0.900"}"#)]),
            timingLine("00:00:03.000", [("16", #""IntervalToPositionAhead":{"Value":"+2.100"}"#)]),
            timingLine("00:00:04.000", [("16", #""IntervalToPositionAhead":{"Value":"+2.200"}"#)]),
            timingLine("00:00:05.000", [("1", #""LastLapTime":{"Value":"1:26.000"}"#)]),
        ])
        #expect(Battle.rivals(of: "4", at: 1_004_500, timing: session.timing).isEmpty)
        #expect(Tower.rows(at: 1_004_500, session: session, favourite: "4").allSatisfy { !$0.battle })
        #expect(Battle.rivals(of: "4", at: 1_005_000, timing: session.timing) == ["1"])
        #expect(Tower.rows(at: 1_005_000, session: session, favourite: "4").filter(\.battle).map(\.number) == ["1", "4"])
        // Nothing after t: at 4.5 s the rival's update at 5 s isn't read.
        #expect(Battle.rivals(of: "1", at: 1_004_999, timing: session.timing).isEmpty)
    }

    @Test func battleOffWithoutFavourite() throws {
        let race = try FixtureSession.race()
        let t = TowerTests.raceT
        #expect(Tower.rows(at: t, session: race, favourite: nil).allSatisfy { !$0.battle })
        // check:raceBattlesSteadyFor10sToLightsOutPlus10min: (10,43) and (43,51) within 1.0 s at
        // every line for the 10 s before t (check:raceInterval43to10…, check:raceInterval51to43…).
        let rows = Tower.rows(at: t, session: race, favourite: "43")
        #expect(rows.filter(\.battle).map(\.number) == ["10", "43", "51"])
        let rows30 = Tower.rows(at: t, session: race, favourite: "30")
        #expect(rows30.filter(\.battle).map(\.number) == ["30", "63"])
        // P1 (12) is 4.401 s clear of P2 (1): no battle (check:raceTowerRow1AtLightsOutPlus10min).
        #expect(Tower.rows(at: t, session: race, favourite: "12").allSatisfy { !$0.battle })
        // Outside races the intervals are lap-time differences: never a battle.
        let lines = [timingLine("00:00:01.000", [("1", #""Position":"1""#), ("4", #""Position":"2","TimeDiffToPositionAhead":"+0.100""#)]),
                     timingLine("00:00:02.000", [("4", #""TimeDiffToPositionAhead":"+0.050""#)])]
        let quali = FixtureSession.synthetic(type: "Qualifying", timing: lines)
        #expect(Tower.rows(at: 1_003_000, session: quali, favourite: "4").allSatisfy { !$0.battle })
        let raceLike = FixtureSession.synthetic(type: "Race", timing: lines)
        #expect(Tower.rows(at: 1_003_000, session: raceLike, favourite: "4").filter(\.battle).map(\.number) == ["1", "4"])
        // One update so far: not yet.
        #expect(Tower.rows(at: 1_001_500, session: raceLike, favourite: "4").allSatisfy { !$0.battle })
    }

    @Test func favouriteFoundByLastName() throws {
        let race = try FixtureSession.race()
        #expect(Tower.carNumber(forDriver: "Hamilton", in: race) == "44")
        #expect(Tower.carNumber(forDriver: "hamilton", in: race) == "44")
        #expect(Tower.carNumber(forDriver: "Nobody", in: race) == nil)
    }
}

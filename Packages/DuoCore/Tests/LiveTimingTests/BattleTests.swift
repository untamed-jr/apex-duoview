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
        #expect(Battle.rivals(of: "4", updates: [close, close]) == ["1"])
        #expect(Battle.rivals(of: "1", updates: [close, close]) == ["4"])
        #expect(Battle.rivals(of: "4", updates: [close, close, apart]).isEmpty)  // the last two only
        #expect(Battle.rivals(of: "4", updates: [apart, close, close]) == ["1"])
        // Exactly 1.0 s counts; the car behind counts too, ahead first.
        let both: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "+1.000"), "16": Self.car(3, "+0.300")]
        #expect(Battle.rivals(of: "4", updates: [both, both]) == ["1", "16"])
        // An overtake between the updates: still the same pair, still within 1.0 s.
        let swapped: [String: DriverTimingState] = ["4": Self.car(1, ""), "1": Self.car(2, "+0.200"), "16": Self.car(3, "+3.0")]
        #expect(Battle.rivals(of: "4", updates: [close, swapped]) == ["1"])
        // A car that changed between the updates isn't a battle of two updates.
        let other: [String: DriverTimingState] = ["16": Self.car(1, ""), "4": Self.car(2, "+0.500"), "1": Self.car(3, "+5.0")]
        #expect(Battle.rivals(of: "4", updates: [close, other]).isEmpty)
        // Laps, blanks, and cars in the pits or out are no battle; unknown cars neither.
        let laps: [String: DriverTimingState] = ["1": Self.car(1, ""), "4": Self.car(2, "1L"), "16": Self.car(3, "")]
        #expect(Battle.rivals(of: "4", updates: [laps, laps]).isEmpty)
        var pitting = close
        pitting["1"]?.inPit = true
        #expect(Battle.rivals(of: "4", updates: [pitting, pitting]).isEmpty)
        #expect(Battle.rivals(of: "99", updates: [close, close]).isEmpty)
        #expect(Battle.gapSeconds("+0.454") == 0.454)
        #expect(Battle.gapSeconds("LAP 7") == nil)
        #expect(Battle.gapSeconds("+1 LAP") == nil)
        #expect(Battle.gapSeconds("") == nil)
        #expect(Battle.gapSeconds("-0.2") == nil)
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

import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct DriverCardTests {
    @Test func cardFlashLasts6s() throws {
        let race = try FixtureSession.race()
        // check:car44Lap2CrossingOffset; check:car44LastLapAtLap2Crossing = ('1:29.518', 'personalBest')
        let crossing = Fixture.raceStart + 3_412_677
        let at = try #require(DriverCardModel.at(crossing, number: "44", session: race))
        #expect(at.flash?.text == "1:29.518")
        #expect(at.flash?.pace == .personalBest)
        #expect(at.lapClock == nil)
        #expect(at.number == "44")
        #expect(at.surname == "HAMILTON")      // check:driver44
        #expect(at.teamColour == "ED1131")
        #expect(!at.inPit)
        #expect(DriverCardModel.at(crossing + 5_999, number: "44", session: race)?.flash?.text == "1:29.518")
        let after = try #require(DriverCardModel.at(crossing + 6_000, number: "44", session: race))
        #expect(after.flash == nil)
        #expect(after.lapClock == "0:06.0")
        // Just before: lap 2 running since lap 1 ended (check:car44Lap1CrossingOffset = 3323236),
        // 89 440 ms in.
        let before = try #require(DriverCardModel.at(crossing - 1, number: "44", session: race))
        #expect(before.flash == nil)
        #expect(before.lapClock == "1:29.4")
        // Before its first crossing a car has no clock.
        let start = try #require(DriverCardModel.at(Fixture.raceStart + 3_323_235, number: "44", session: race))
        #expect(start.lapClock == nil)
        #expect(start.flash == nil)
    }

    @Test func cardSectorsColoured() throws {
        let race = try FixtureSession.race()
        // check:raceMixedSectorsMidLap = (3729693, '12', [set, overallBest, empty], ['22.189', '44.821', '']):
        // after its crossing at 3662660 (check:raceMixedSectorsCarLapsAndLastCountOffset), until
        // its next line at 3733678 (check:raceMixedSectorsCarNextLineOffset).
        for offset: Int64 in [3_729_693, 3_733_677] {
            let card = try #require(DriverCardModel.at(Fixture.raceStart + offset, number: "12", session: race))
            #expect(card.sectors == [.set, .overallBest, .empty])
            #expect(card.surname == "ANTONELLI")   // check:driver12
            #expect(card.position == 1)
        }
        // Blank from the line: every bar grey just after car 44's lap-2 crossing.
        let fresh = try #require(DriverCardModel.at(Fixture.raceStart + 3_412_677, number: "44", session: race))
        #expect(fresh.sectors == [.empty, .empty, .empty])
    }

    @Test func cardInThePitsShowsPIT() throws {
        // check:raceCar77At3200000 = ('17', True, False, '')
        let card = try #require(DriverCardModel.at(Fixture.raceStart + 3_200_000, number: "77", session: try FixtureSession.race()))
        #expect(card.inPit)
        #expect(card.lapClock == nil)
        #expect(card.flash == nil)
        #expect(card.position == 17)
        #expect(DriverCardModel.at(Fixture.raceStart + 3_200_000, number: "99", session: try FixtureSession.race()) == nil)
    }

    @Test func cardShowsNoStaleLapLeavingThePits() {
        // In qualifying F1 raises the lap count with PitOut (raw São Paulo qualifying, car 12 at
        // 7348411, holding its last run's 1:32.229): no flash then, the clock runs from the exit.
        let session = FixtureSession.synthetic(type: "Qualifying", timing: [
            timingLine("00:00:01.000", [("12", #""InPit":false,"PitOut":false,"NumberOfLaps":9"#)]),
            timingLine("00:01:00.000", [("12", #""NumberOfLaps":10,"LastLapTime":{"Value":"1:32.229","PersonalFastest":true}"#)]),
            timingLine("00:02:00.000", [("12", #""InPit":true"#)]),
            timingLine("00:10:00.000", [("12", #""NumberOfLaps":11,"InPit":false,"PitOut":true"#)]),
            timingLine("00:10:30.000", [("12", #""PitOut":false"#)]),
        ])
        #expect(DriverCardModel.at(1_060_000, number: "12", session: session)?.flash?.text == "1:32.229")
        let exit = DriverCardModel.at(1_600_000, number: "12", session: session)
        #expect(exit?.flash == nil)
        #expect(exit?.lapClock == "0:00.0")
        #expect(DriverCardModel.at(1_605_000, number: "12", session: session)?.lapClock == "0:05.0")
    }

    @Test func cardGapIsIntervalInRacesAndToFastestInQualifying() {
        let lines = [timingLine("00:00:01.000", [("4", #""Position":"2","GapToLeader":"+3.000","IntervalToPositionAhead":{"Value":"+0.800"},"TimeDiffToFastest":"+0.300","TimeDiffToPositionAhead":"+0.100""#)])]
        let race = FixtureSession.synthetic(type: "Race", timing: lines)
        #expect(DriverCardModel.at(1_001_000, number: "4", session: race)?.gap == "+0.800")
        let quali = FixtureSession.synthetic(type: "Qualifying", timing: lines)
        // GapToLeader is read before TimeDiffToFastest; a qualifying line has only the latter.
        let qLines = [timingLine("00:00:01.000", [("4", #""Position":"2","TimeDiffToFastest":"+0.300","TimeDiffToPositionAhead":"+0.100""#)])]
        #expect(DriverCardModel.at(1_001_000, number: "4", session: FixtureSession.synthetic(type: "Qualifying", timing: qLines))?.gap == "+0.300")
        #expect(DriverCardModel.at(1_001_000, number: "4", session: quali)?.surname == "4")
    }

    @Test func lapTextsAreF1s() {
        #expect(Tower.lapText(89_518) == "1:29.518")
        #expect(Tower.lapText(60_000) == "1:00.000")
        #expect(Tower.lapText(59_005) == "0:59.005")
        #expect(DriverCardModel.clockText(0) == "0:00.0")
        #expect(DriverCardModel.clockText(89_449) == "1:29.4")
        #expect(DriverCardModel.clockText(600_000) == "10:00.0")
    }
}

import Foundation
import Testing
@testable import LiveTiming

@Suite struct SessionStatusTests {
    @Test func raceStartedIsLightsOut() throws {
        let status = SessionStatusTimeline.build(lines: try Fixture.lines("sp26-race/SessionStatus.jsonStream"),
                                                 streamStart: Fixture.raceStart)
        // check:raceLightsOutUtc: "Started" at 00:53:44.576 into the stream.
        #expect(status.started == Fixture.raceLightsOut)
        #expect(status.changes.map(\.status) == ["Inactive", "Started"])
        #expect(status.changes[0].at == Fixture.raceStart + 9_830)
        #expect(status.status(at: Fixture.raceStart) == nil)
        #expect(status.status(at: Fixture.raceStart + 9_830) == "Inactive")
        #expect(status.status(at: Fixture.raceLightsOut - 1) == "Inactive")
        #expect(status.status(at: Fixture.raceLightsOut) == "Started")
        #expect(status.status(at: .max) == "Started")
    }

    @Test func qualifyingStartedThenAborted() throws {
        let status = SessionStatusTimeline.build(lines: try Fixture.lines("sp26-quali/SessionStatus.jsonStream"),
                                                 streamStart: Fixture.qualiStart)
        #expect(status.started == Fixture.qualiQ1)
        #expect(status.status(at: Fixture.qualiQ1 + 60_000) == "Started")
        // Q1's red flag, 2:23 in.
        #expect(status.status(at: Fixture.qualiStart + 943_900) == "Aborted")
    }

    @Test func laterChangesAndOddLines() {
        let status = SessionStatusTimeline.build(lines: lines(
            #"00:00:01.000{"Status":"Inactive"}"#,
            #"00:00:02.000{"Started":"Started"}"#,          // no Status: skipped
            #"00:00:03.000{"Status":""}"#,                  // empty: skipped
            #"00:00:04.000{"Status":"Started"}"#,
            #"00:00:05.000{"Status":"Aborted"}"#,
            #"00:00:06.000{"Status":"Started"}"#,
            #"00:00:07.000{"Status":"Finished"}"#,
            #"00:00:08.000{"Status":"Finalised"}"#,
            #"00:00:08.000{"Status":"Ends"}"#
        ), streamStart: 1_000_000)
        #expect(status.changes.map(\.status) == ["Inactive", "Started", "Aborted", "Started", "Finished", "Finalised", "Ends"])
        #expect(status.started == 1_004_000)  // the first Started
        #expect(status.first("Finished") == 1_007_000)
        #expect(status.first("Aborted") == 1_005_000)
        #expect(status.first("Red") == nil)
        #expect(status.status(at: 1_005_500) == "Aborted")
        // Two changes at one moment: the later line holds.
        #expect(status.status(at: 1_008_000) == "Ends")
        // A stream start near Int64's end saturates instead of trapping.
        let far = SessionStatusTimeline.build(lines: lines(#"00:00:01.000{"Status":"Started"}"#), streamStart: .max - 10)
        #expect(far.started == .max)
    }

    @Test func emptyHasNoStart() {
        let none = SessionStatusTimeline.build(lines: [], streamStart: 0)
        #expect(none.changes.isEmpty)
        #expect(none.started == nil)
        #expect(none.status(at: 0) == nil)
        #expect(SessionStatusTimeline() == none)
    }
}

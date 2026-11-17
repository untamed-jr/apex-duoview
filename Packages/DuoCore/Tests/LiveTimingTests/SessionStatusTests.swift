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

    @Test func aStateOnJoiningIsNoChange() {
        // Line 0 is a live feed's opening snapshot (at the stream's start): the session was
        // already under way, so when the lights went out isn't known.
        let joined = SessionStatusTimeline.build(lines: lines(
            #"00:00:00.000{"Status":"Started"}"#,
            #"12:00:10.000{"Status":"Aborted"}"#,
            #"12:00:20.000{"Status":"Started"}"#,
            #"12:00:30.000{"Status":"Finished"}"#
        ), streamStart: 0, snapshotLines: [0])
        #expect(joined.status(at: 0) == "Started")
        #expect(joined.changes.map(\.isSnapshot) == [true, false, false, false])
        #expect(joined.started == nil)
        #expect(joined.first("Finished") == 43_230_000)
        // Joined before the start: the first Started is lights out.
        let early = SessionStatusTimeline.build(lines: lines(
            #"00:00:00.000{"Status":"Inactive"}"#,
            #"12:00:20.000{"Status":"Started"}"#
        ), streamStart: 0, snapshotLines: [0])
        #expect(early.started == 43_220_000)
        // Joined after the flag: no chequered flag at the stream's start.
        let after = SessionStatusTimeline.build(lines: lines(#"00:00:00.000{"Status":"Finished"}"#), streamStart: 0,
                                                snapshotLines: [0])
        #expect(after.first("Finished") == nil)
        #expect(after.status(at: 0) == "Finished")
    }

    @Test func joiningLiveAfterTheStartMarksNoLightsOut() async throws {
        let replay = try ArchiveReplay()
        let joined = Fixture.raceLightsOut + 240_000
        var feed = LiveFeed()
        for m in replay.snapshot(at: joined, through: joined) + replay.changes.filter({ $0.utc > joined }) { feed.apply(m) }
        let live = try #require(feed.built())
        #expect(live.sessionStatus.status(at: joined - 60_000) == "Started")
        #expect(live.sessionStatus.started == nil)
        #expect(!TimelineMark.marks(for: live, pictureTime: joined + 60_000, playerSeconds: 1_000, wholeRace: true)
            .contains { if case .lightsOut = $0 { return true } else { return false } })
        #expect(!RaceEvents.list(until: nil, session: live).contains { $0.kind == .lightsOut })

        // An archive that ends before the lights went out: what it lacks of the snapshot is no
        // change either.
        var lagging = feed
        lagging.topUp(archive: replay.streams.mapValues { $0.filter { replay.utc($0) < Fixture.raceLightsOut - 60_000 } },
                      archiveStart: replay.start)
        let early = try #require(lagging.built())
        #expect(early.sessionStatus.status(at: joined - 60_000) == "Inactive")  // the archive's last, until the join
        #expect(early.sessionStatus.status(at: joined) == "Started")
        #expect(early.sessionStatus.started == nil)

        // The whole archive: lights out where it was.
        feed.topUp(archive: replay.streams, archiveStart: replay.start)
        let full = try #require(feed.built())
        #expect(full.sessionStatus.started == Fixture.raceLightsOut)
        #expect(RaceEvents.list(until: nil, session: full).contains { $0.kind == .lightsOut && $0.t == Fixture.raceLightsOut })
    }
}

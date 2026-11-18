import Foundation
import Testing
import F1TV
@testable import LiveTiming

@Suite struct CompanionEventsTests {
    static let s: UTCms = 1_000_000

    /// Steps a detector from `from` (a seek, which only sets the baseline) to `to` in `stepMs`
    /// plays, and gathers what comes back.
    @discardableResult
    static func run(_ d: inout EventDetector, _ session: LoadedSession, radio: RadioClips = RadioClips(),
                    from: UTCms, to: UTCms, stepMs: Int64 = 500, favourite: String? = nil,
                    listening: Set<String> = [], seekFirst: Bool = true) -> [CompanionEvent] {
        var out: [CompanionEvent] = []
        if seekFirst {
            out += d.step(to: from, motion: .seek, session: session, radio: radio, favourite: favourite, listening: listening)
        }
        var t = from
        while t < to {
            t = min(t + stepMs, to)
            out += d.step(to: t, motion: .play, session: session, radio: radio, favourite: favourite, listening: listening)
        }
        return out
    }

    static func yellows(_ stamps: [String]) -> [StreamLine] {
        stamps.enumerated().map { i, stamp in line(stamp + #"{"Status":""# + (i % 2 == 0 ? "2" : "1") + #""}"#) }
    }

    static func radioLine(_ offset: String, _ clips: [(UTCms, String, String)]) -> StreamLine {
        let body = clips.map { #"{"Utc":"\#(iso($0.0))","RacingNumber":"\#($0.1)","Path":"TeamRadio/\#($0.2).mp3"}"# }.joined(separator: ",")
        return line(offset + #"{"Captures":["# + body + "]}")
    }

    static func timing(_ session: [StreamLine], type: String = "Race", track: [StreamLine] = [],
                       status: [StreamLine] = [], laps: [StreamLine] = []) -> LoadedSession {
        RaceFixture.synthetic(type: type, timing: session, trackStatus: track, sessionStatus: status, lapCount: laps, start: s)
    }

    // MARK: Whole-session fixtures

    @Test func raceYellowsOnLaps17And20() throws {
        let session = try RadioRaceTests.longRace()
        let from: UTCms = 1_794_158_820_000   // 17:27:00Z
        let to: UTCms = 1_794_159_120_000     // 17:32:00Z
        var d = EventDetector()
        let events = Self.run(&d, session, from: from, to: to)
        #expect(events.map(\.kind) == [.yellow, .yellow])
        #expect(events.map(\.lap) == [17, 20])
        #expect(events.allSatisfy { $0.t > from && $0.t <= to })
    }

    @Test func qualifyingTwoRedFlags() throws {
        let folder = "sp26-quali-long", start = Fixture.qualiStart
        func stream(_ name: String) throws -> [StreamLine] { try Fixture.lines("\(folder)/\(name).jsonStream") }
        let info = try #require(TimingSessionInfo.parse(try Fixture.json("\(folder)/SessionInfo.json")))
        let session = LoadedSession(
            info: info, drivers: Drivers.parse(try Fixture.json("\(folder)/DriverList.json")), streamStart: start,
            positions: PositionSeries(cars: [:]), timing: TimingTimeline.build(lines: [], streamStart: start),
            stints: StintTimeline.build(lines: [], streamStart: start),
            header: HeaderTimeline.build(lapCount: [], clock: [], weather: [], streamStart: start),
            flags: TrackFlags.build(trackStatus: try stream("TrackStatus"), raceControl: try stream("RaceControlMessages"),
                                    streamStart: start, gmtOffsetSeconds: info.gmtOffsetSeconds),
            sessionStatus: SessionStatusTimeline.build(lines: try stream("SessionStatus"), streamStart: start),
            missing: [])
        var d = EventDetector()
        // Whole session, in 10 s plays so it is quick: still below jumpMs, so nothing is skipped.
        let events = Self.run(&d, session, from: start + 60_000, to: start + 3 * 3_600_000, stepMs: 5_000)
        let reds = events.filter { $0.kind == .red }
        #expect(reds.count == 2)
        // 18:02:25 and 20:03:20 UTC (race control's flag a little before TrackStatus's).
        let wanted: [UTCms] = [1_794_074_545_000, 1_794_081_800_000]
        for (event, at) in zip(reds, wanted) { #expect(abs(event.t - at) <= 5_000) }
        #expect(reds.allSatisfy { $0.lap == nil })
        // Qualifying has no lap on any track event.
        #expect(events.allSatisfy { $0.lap == nil })
    }

    @Test func nothingLaterThanTLeaks() throws {
        let session = try RadioRaceTests.longRace()
        let from: UTCms = 1_794_158_820_000
        let to: UTCms = 1_794_159_100_000
        var d = EventDetector()
        let whole = Self.run(&d, session, from: from, to: to)
        var cut = session
        // Drop every status line after `to`: the events up to `to` are the same.
        cut.flags = TrackFlags.build(
            trackStatus: try Fixture.lines("sp26-race-long/TrackStatus.jsonStream").filter { session.streamStart + $0.offsetMs <= to },
            raceControl: [], streamStart: session.streamStart, gmtOffsetSeconds: session.info.gmtOffsetSeconds)
        var d2 = EventDetector()
        #expect(Self.run(&d2, cut, from: from, to: to).map(\.kind) == whole.map(\.kind))
    }

    // MARK: Baseline and quiet period

    @Test func seekAcrossYellowFiresNothing() {
        let session = Self.timing([line(#"00:00:01.000{"Lines":{"1":{"Position":"1"}}}"#)],
                                  track: Self.yellows(["00:00:10.000"]))
        var d = EventDetector()
        #expect(d.step(to: Self.s + 5_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        #expect(d.step(to: Self.s + 20_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        #expect(Self.run(&d, session, from: Self.s + 20_000, to: Self.s + 30_000, seekFirst: false).isEmpty)
    }

    @Test func firstStepOnlySetsTheBaseline() {
        let session = Self.timing([], track: Self.yellows(["00:00:10.000"]))
        var d = EventDetector()
        // A play as the very first step has nothing to compare with.
        #expect(d.step(to: Self.s + 20_000, motion: .play, session: session, radio: RadioClips(), favourite: nil).isEmpty)
    }

    @Test func quietTwoSecondsAfterSeek() {
        // Yellow at 10 s (inside the quiet 2 s after a seek to 9 s), clear at 10.5, yellow at 12.
        let session = Self.timing([], track: Self.yellows(["00:00:10.000", "00:00:10.500", "00:00:12.000"]))
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 9_000, to: Self.s + 15_000)
        #expect(events.map(\.t) == [Self.s + 12_000])
        #expect(events.map(\.kind) == [.yellow])
    }

    @Test func backwardOrLongStepIsASeek() {
        let session = Self.timing([], track: Self.yellows(["00:00:10.000", "00:00:10.500"]))
        var d = EventDetector()
        _ = d.step(to: Self.s + 20_000, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        // Backwards.
        #expect(d.step(to: Self.s + 5_000, motion: .play, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        // Past 10 s of picture time in one step: a jump over the yellow.
        #expect(d.step(to: Self.s + 15_001, motion: .play, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        // Exactly jumpMs is still a play (after the quiet 2 s).
        var e = EventDetector()
        _ = e.step(to: Self.s + 4_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil)
        _ = e.step(to: Self.s + 6_000, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        let crossed = e.step(to: Self.s + 6_000 + EventDetector.jumpMs, motion: .play, session: session,
                             radio: RadioClips(), favourite: nil)
        #expect(crossed.map(\.kind) == [.yellow])
    }

    @Test func yellowOncePerMinute() {
        // Yellow at +10 s, +40 s and +71 s, each cleared 5 s after: 30 s after the first is
        // too soon, 61 s after is not.
        let session = Self.timing([], track: Self.yellows([
            "00:00:10.000", "00:00:15.000", "00:00:40.000", "00:00:45.000", "00:01:11.000", "00:01:16.000"]))
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 1_000, to: Self.s + 90_000, stepMs: 1_000)
        #expect(events.map(\.t) == [Self.s + 10_000, Self.s + 71_000])
        #expect(EventDetector.yellowRepeatMs == 60_000 && EventDetector.seekQuietMs == 2_000 && EventDetector.jumpMs == 10_000)
    }

    @Test func forwardBaselinesKeepTheYellowRule() {
        // Yellow at 10 s; a forward seek of 20 s, and then a step over jumpMs, must not let a
        // second yellow through inside 60 s of picture time.
        let stamps = ["00:00:10.000", "00:00:11.000", "00:00:40.000", "00:00:41.000", "00:01:05.000", "00:01:06.000", "00:01:20.000"]
        let session = Self.timing([], track: Self.yellows(stamps))
        var d = EventDetector()
        let first = Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 15_000, stepMs: 1_000)
        #expect(first.map(\.t) == [Self.s + 10_000])
        // Forward seek of 20 s: baseline at 35 s; the yellow at 40 s is 30 s after the first.
        _ = d.step(to: Self.s + 35_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil)
        let second = Self.run(&d, session, from: Self.s + 35_000, to: Self.s + 50_000, stepMs: 1_000, seekFirst: false)
        #expect(second.isEmpty)
        // A jump over 10 s of picture time (50 s to 62 s) is a baseline too; 65 s is 55 s after the first.
        _ = d.step(to: Self.s + 62_000, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        let third = Self.run(&d, session, from: Self.s + 62_000, to: Self.s + 68_000, stepMs: 1_000, seekFirst: false)
        #expect(third.isEmpty)
        // 80 s is 70 s after the first yellow: allowed.
        let fourth = Self.run(&d, session, from: Self.s + 68_000, to: Self.s + 85_000, stepMs: 1_000, seekFirst: false)
        #expect(fourth.map(\.t) == [Self.s + 80_000])
    }

    @Test func rewindBeforeTheLastYellowFiresItAgain() {
        let session = Self.timing([], track: Self.yellows(["00:00:10.000", "00:00:11.000"]))
        var d = EventDetector()
        #expect(Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 15_000, stepMs: 1_000).map(\.t) == [Self.s + 10_000])
        // Back to 3 s (before the yellow) and play over it again, past the quiet period.
        #expect(d.step(to: Self.s + 3_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        let again = Self.run(&d, session, from: Self.s + 3_000, to: Self.s + 15_000, stepMs: 1_000, seekFirst: false)
        #expect(again.map(\.t) == [Self.s + 10_000])
    }

    @Test func smallBackwardStepIsAnEmptyStepNotABaseline() {
        // Yellow at 10.4 s. Step to 10.2 s, back 200 ms: no baseline, so nothing is lost.
        let session = Self.timing([], track: Self.yellows(["00:00:10.400", "00:00:11.000"]))
        var d = EventDetector()
        _ = d.step(to: Self.s + 5_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil)
        _ = d.step(to: Self.s + 10_000, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        #expect(d.step(to: Self.s + 9_800, motion: .play, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        let events = d.step(to: Self.s + 10_500, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        #expect(events.map(\.t) == [Self.s + 10_400])
        // It doesn't reset the yellow rule either: a back step of 200 ms leaves the yellow remembered.
        let again = Self.timing([], track: Self.yellows(["00:00:10.000", "00:00:10.100", "00:00:10.600", "00:00:10.700"]))
        var e = EventDetector()
        _ = e.step(to: Self.s + 5_000, motion: .seek, session: again, radio: RadioClips(), favourite: nil)
        #expect(e.step(to: Self.s + 10_050, motion: .play, session: again, radio: RadioClips(), favourite: nil).map(\.t) == [Self.s + 10_000])
        _ = e.step(to: Self.s + 9_850, motion: .play, session: again, radio: RadioClips(), favourite: nil)
        #expect(e.step(to: Self.s + 10_800, motion: .play, session: again, radio: RadioClips(), favourite: nil).isEmpty)
        // 600 ms back is a baseline: quiet 2 s, so the yellow just after it is not reported.
        var f = EventDetector()
        _ = f.step(to: Self.s + 5_000, motion: .seek, session: session, radio: RadioClips(), favourite: nil)
        _ = f.step(to: Self.s + 10_000, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        #expect(f.step(to: Self.s + 9_400, motion: .play, session: session, radio: RadioClips(), favourite: nil).isEmpty)
        #expect(f.step(to: Self.s + 10_500, motion: .play, session: session, radio: RadioClips(), favourite: nil).isEmpty)
    }

    @Test func twoClipsOfOneCarAtOneMomentKeepTheirOwnPaths() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [
            (Self.s + 20_000, "12", "A_12_20261108_140000"), (Self.s + 20_000, "12", "A_12_20261108_140001")])])
        var d = EventDetector()
        let events = Self.run(&d, Self.timing([]), radio: radio, from: Self.s + 10_000, to: Self.s + 30_000, favourite: "12")
        #expect(events.map(\.kind) == [.radio(car: "12", path: "TeamRadio/A_12_20261108_140000.mp3"),
                                       .radio(car: "12", path: "TeamRadio/A_12_20261108_140001.mp3")])
    }

    @Test func favouritePitsBeforeLightsOutAreNotEvents() throws {
        let session = try RadioRaceTests.longRace()
        let started = RadioRaceTests.started
        let from = started - 2_700_000   // covers the pre-race pit-lane exits and entries
        var d = EventDetector()
        let events = Self.run(&d, session, from: from, to: started + 5_400_000, stepMs: 5_000, favourite: "12")
        let mine = events.filter { $0.kind == .pit(car: "12") || $0.kind == .out(car: "12") }
        #expect(mine.allSatisfy { $0.t >= started })
        // The real stops are the ones RaceEvents lists for the car after the start, all still reported.
        let real = RaceEvents.list(until: started + 5_400_000, session: session).filter { $0.kind == .pit(car: "12") }
        #expect(!real.isEmpty)
        #expect(events.filter { $0.kind == .pit(car: "12") }.map(\.t) == real.map(\.t).filter { $0 > from + EventDetector.seekQuietMs })
    }

    @Test func trackEventsForScVscRedAndChequered() {
        // Yellow, then SC (4) ("in this lap" is the same SC), VSC (6, 7), clear, red (5), clear.
        let session = Self.timing([], track: lines(
            #"00:00:10.000{"Status":"2"}"#, #"00:00:20.000{"Status":"4"}"#, #"00:00:30.000{"Status":"1"}"#,
            #"00:00:40.000{"Status":"6"}"#, #"00:00:50.000{"Status":"7"}"#, #"00:01:00.000{"Status":"1"}"#,
            #"00:01:10.000{"Status":"5"}"#, #"00:01:20.000{"Status":"1"}"#),
            status: lines(#"00:00:01.000{"Status":"Started"}"#, #"00:01:30.000{"Status":"Finished"}"#,
                          #"00:01:31.000{"Status":"Finalised"}"#))
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 100_000, stepMs: 1_000)
        #expect(events.map(\.kind) == [.yellow, .safetyCar, .vsc, .red, .chequered])
        #expect(events.map(\.t) == [10_000, 20_000, 40_000, 70_000, 90_000].map { Self.s + $0 })
        // A race's track events carry the leader's lap; the chequered flag at least lap 1.
        #expect(events.map(\.lap) == [1, 1, 1, 1, 1])
    }

    @Test func yellowDirectlyToSafetyCarIsAnEvent() {
        let session = Self.timing([], track: lines(#"00:00:10.000{"Status":"2"}"#, #"00:00:20.000{"Status":"4"}"#,
                                                   #"00:00:21.000{"Status":"2"}"#))
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 30_000, stepMs: 1_000)
        // SC back to yellow is not entering yellow from clear.
        #expect(events.map(\.kind) == [.yellow, .safetyCar])
    }

    @Test func preRaceYellowHasNoLap() {
        let session = Self.timing([line(#"00:00:01.000{"Lines":{"1":{"Position":"1","NumberOfLaps":0}}}"#)],
                                  track: Self.yellows(["00:00:10.000", "00:00:11.000", "00:01:20.000"]),
                                  status: lines(#"00:00:00.000{"Status":"Inactive"}"#, #"00:00:20.000{"Status":"Started"}"#))
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 100_000, stepMs: 1_000)
        #expect(events.map(\.kind) == [.yellow, .yellow])
        #expect(events.map(\.lap) == [nil, 1])
    }

    // MARK: Driver events

    static let driverLines = [
        #"00:00:01.000{"Lines":{"12":{"Position":"2","NumberOfLaps":4,"InPit":false,"PitOut":false,"Retired":false,"Stopped":false},"1":{"Position":"1","NumberOfLaps":4,"InPit":false}}}"#,
        #"00:00:10.000{"Lines":{"12":{"InPit":true},"1":{"InPit":true}}}"#,
        #"00:00:20.000{"Lines":{"12":{"Sectors":{"1":{"Value":"30.1","OverallFastest":true}}},"1":{"Sectors":{"1":{"Value":"30.0","OverallFastest":true}}}}}"#,
        #"00:00:30.000{"Lines":{"12":{"Retired":true},"1":{"Retired":true}}}"#,
    ].map(line)

    @Test func noFavouriteNoDriverEvents() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [(Self.s + 40_000, "12", "A_12_20261108_140000")])])
        let session = Self.timing(Self.driverLines, track: Self.yellows(["00:00:12.000"]))
        var d = EventDetector()
        let events = Self.run(&d, session, radio: radio, from: Self.s + 5_000, to: Self.s + 50_000, stepMs: 1_000)
        #expect(events.map(\.kind) == [.yellow])
    }

    @Test func favouriteRadioPitOutPurple() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [
            (Self.s + 40_000, "12", "A_12_20261108_140000"), (Self.s + 41_000, "1", "B_1_20261108_140001")])])
        let session = Self.timing(Self.driverLines)
        var d = EventDetector()
        let events = Self.run(&d, session, radio: radio, from: Self.s + 5_000, to: Self.s + 50_000, stepMs: 1_000, favourite: "12")
        #expect(events.map(\.kind) == [.pit(car: "12"), .purpleSector(car: "12"), .out(car: "12"), .radio(car: "12", path: "TeamRadio/A_12_20261108_140000.mp3")])
        #expect(events.map(\.t) == [10_000, 20_000, 30_000, 40_000].map { Self.s + $0 })
        // Car events carry that car's lap: laps done 4, so lap 5.
        #expect(events.map(\.lap) == [5, 5, 5, 5])
    }

    @Test func stoppedCarIsOut() {
        let session = Self.timing([line(#"00:00:01.000{"Lines":{"12":{"Position":"2","Stopped":false}}}"#),
                                   line(#"00:00:10.000{"Lines":{"12":{"Stopped":true}}}"#)])
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 20_000, stepMs: 1_000, favourite: "12")
        #expect(events.map(\.kind) == [.out(car: "12")])
    }

    @Test func passedOnePlaceNamesOther() {
        let session = Self.timing([
            line(#"00:00:01.000{"Lines":{"12":{"Position":"2"},"1":{"Position":"1"},"3":{"Position":"3"}}}"#),
            line(#"00:00:10.000{"Lines":{"12":{"Position":"1"},"1":{"Position":"2"}}}"#),
            line(#"00:00:20.000{"Lines":{"12":{"Position":"2"},"1":{"Position":"1"}}}"#),
        ])
        var d = EventDetector()
        let events = Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 30_000, stepMs: 1_000, favourite: "12")
        // 12 passes 1 for P1; then 1 passes 12 for P1.
        #expect(events.map(\.kind) == [.passed(car: "12", other: "1", position: 1), .passed(car: "1", other: "12", position: 1)])
        #expect(events.map(\.t) == [10_000, 20_000].map { Self.s + $0 })
    }

    @Test func passedNotInQualifying() {
        let session = Self.timing([
            line(#"00:00:01.000{"Lines":{"12":{"Position":"2"},"1":{"Position":"1"}}}"#),
            line(#"00:00:10.000{"Lines":{"12":{"Position":"1"},"1":{"Position":"2"}}}"#),
        ], type: "Qualifying")
        var d = EventDetector()
        #expect(Self.run(&d, session, from: Self.s + 5_000, to: Self.s + 20_000, stepMs: 1_000, favourite: "12").isEmpty)
    }

    @Test func pitCycleShuffleNoPassed() {
        // 12 pits from P2 and drops to P3 (3 moves up): one place, but it is in the pit lane.
        let a = Self.timing([
            line(#"00:00:01.000{"Lines":{"12":{"Position":"2","InPit":false},"1":{"Position":"1"},"3":{"Position":"3"}}}"#),
            line(#"00:00:10.000{"Lines":{"12":{"Position":"3","InPit":true},"3":{"Position":"2"}}}"#),
        ])
        var d = EventDetector()
        #expect(Self.run(&d, a, from: Self.s + 5_000, to: Self.s + 20_000, stepMs: 1_000, favourite: "12").map(\.kind)
                == [.pit(car: "12")])
        // The other car comes out of the pits (PitOut) as the places change.
        let b = Self.timing([
            line(#"00:00:01.000{"Lines":{"12":{"Position":"2"},"3":{"Position":"3","PitOut":true}}}"#),
            line(#"00:00:10.000{"Lines":{"12":{"Position":"3"},"3":{"Position":"2"}}}"#),
        ])
        var e = EventDetector()
        #expect(Self.run(&e, b, from: Self.s + 5_000, to: Self.s + 20_000, stepMs: 1_000, favourite: "12").isEmpty)
        // A jump of several places gives nothing.
        let c = Self.timing([
            line(#"00:00:01.000{"Lines":{"12":{"Position":"2"},"1":{"Position":"1"},"3":{"Position":"3"},"4":{"Position":"4"}}}"#),
            line(#"00:00:10.000{"Lines":{"12":{"Position":"4"},"3":{"Position":"2"},"4":{"Position":"3"}}}"#),
        ])
        var f = EventDetector()
        #expect(Self.run(&f, c, from: Self.s + 5_000, to: Self.s + 20_000, stepMs: 1_000, favourite: "12").isEmpty)
    }

    // MARK: Radio

    @Test func radioEventOnlyWhenCrossed() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [(Self.s + 20_000, "12", "A_12_20261108_140000")])])
        let session = Self.timing([line(#"00:00:01.000{"Lines":{"12":{"Position":"2","NumberOfLaps":2}}}"#)])
        var d = EventDetector()
        let before = Self.run(&d, session, radio: radio, from: Self.s + 10_000, to: Self.s + 19_999, favourite: "12")
        #expect(before.isEmpty)
        let at = d.step(to: Self.s + 20_000, motion: .play, session: session, radio: radio, favourite: "12")
        #expect(at.map(\.kind) == [.radio(car: "12", path: "TeamRadio/A_12_20261108_140000.mp3")])
        #expect(at.map(\.t) == [Self.s + 20_000])
        // Not again.
        #expect(d.step(to: Self.s + 20_500, motion: .play, session: session, radio: radio, favourite: "12").isEmpty)
    }

    @Test func listenedCarsRadioCrossed() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [
            (Self.s + 20_000, "44", "A_44_20261108_140000"), (Self.s + 20_000, "1", "B_1_20261108_140000")])])
        let session = Self.timing([])
        var d = EventDetector()
        let events = Self.run(&d, session, radio: radio, from: Self.s + 10_000, to: Self.s + 30_000, listening: ["44"])
        #expect(events.map(\.kind) == [.radio(car: "44", path: "TeamRadio/A_44_20261108_140000.mp3")])
    }

    @Test func seekAcrossClipDoesNotAutoPlay() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [(Self.s + 20_000, "44", "A_44_20261108_140000")])])
        let session = Self.timing([])
        var d = EventDetector()
        _ = d.step(to: Self.s + 10_000, motion: .seek, session: session, radio: radio, favourite: nil, listening: ["44"])
        #expect(d.step(to: Self.s + 30_000, motion: .seek, session: session, radio: radio, favourite: nil, listening: ["44"]).isEmpty)
        #expect(Self.run(&d, session, radio: radio, from: Self.s + 30_000, to: Self.s + 40_000, listening: ["44"], seekFirst: false).isEmpty)
    }

    @Test func clipInsideQuietPeriodIsNotReported() {
        let radio = RadioClips(lines: [Self.radioLine("00:00:05.000", [(Self.s + 21_000, "44", "A_44_20261108_140000")])])
        var d = EventDetector()
        #expect(Self.run(&d, Self.timing([]), radio: radio, from: Self.s + 20_000, to: Self.s + 30_000, listening: ["44"]).isEmpty)
    }

    // MARK: Extremes

    @Test func extremeInputsDoNotTrap() {
        let session = Self.timing(Self.driverLines, track: Self.yellows(["00:00:10.000"]))
        var d = EventDetector()
        for t: UTCms in [.min, .max, 0, -1, .max - 1, Self.s] {
            for motion in [PictureMotion.play, .seek] {
                _ = d.step(to: t, motion: motion, session: session, radio: RadioClips(), favourite: "12", listening: ["12", "x"])
            }
        }
        _ = d.step(to: .max, motion: .play, session: session, radio: RadioClips(), favourite: "nope")
        _ = d.step(to: .min, motion: .play, session: session, radio: RadioClips(), favourite: nil)
        let empty = EventDetector.self
        #expect(empty.jumpMs > 0)
    }
}

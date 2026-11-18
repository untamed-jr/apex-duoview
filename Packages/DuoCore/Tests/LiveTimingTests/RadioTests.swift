import Foundation
import Testing
@testable import LiveTiming

@Suite struct RadioTests {
    // MARK: Clips and the parser

    @Test func clipReadsItsFileName() {
        let clip = RadioClip(utc: 1, racingNumber: "12", path: "TeamRadio/ANT_12_20261108_141229.mp3")
        #expect(clip.fileTime == RadioFileTime(year: 2026, month: 11, day: 8, hour: 14, minute: 12, second: 29))
        // The name is the track's clock: São Paulo is 3 hours behind GMT, so 14:12:29 there is 17:12:29Z.
        #expect(clip.fileUtc(gmtOffsetSeconds: -3 * 3600) == 1_794_157_949_000)
        #expect(clip.fileTime?.utc(gmtOffsetSeconds: 0) == 1_794_147_149_000)
        // Without the folder, upper-case extension, a code with no number.
        #expect(RadioClip(utc: 1, racingNumber: "1", path: "NOR_1_20261108_132915.MP3").fileTime?.second == 15)
        for odd in ["", "TeamRadio/", "TeamRadio/ANT_12.mp3", "TeamRadio/ANT_12_2026110_141229.mp3",
                    "TeamRadio/ANT_12_20261308_141229.mp3", "TeamRadio/ANT_12_20261108_241229.mp3",
                    "TeamRadio/ANT_12_20261108_146029.mp3", "TeamRadio/ANT_12_2026110x_141229.mp3",
                    "TeamRadio/ANT_12_20261100_141229.mp3", "TeamRadio/ANT_12_20261108_14122.mp3",
                    "TeamRadio/ANT_12_20261108_1412290.mp3", "TeamRadio/ANT_12_٢٠٢٦١١٠٨_141229.mp3"] {
            #expect(RadioClip(utc: 1, racingNumber: "12", path: odd).fileTime == nil, "\(odd)")
            #expect(RadioClip(utc: 1, racingNumber: "12", path: odd).fileUtc(gmtOffsetSeconds: 0) == nil, "\(odd)")
        }
    }

    @Test func raceFixtureListThenKeyed() throws {
        let clips = RadioClips(lines: try Fixture.lines("sp26-race/TeamRadio.jsonStream")).all
        // The opening list (two pre-race clips published together), then entries keyed "2" and "3".
        #expect(clips.map(\.path) == ["TeamRadio/NOR_1_20261108_132915.mp3", "TeamRadio/ANT_12_20261108_132331.mp3",
                                      "TeamRadio/LEC_16_20261108_135537.mp3", "TeamRadio/ANT_12_20261108_141229.mp3"])
        #expect(clips.map(\.racingNumber) == ["1", "12", "16", "12"])
        // "…22.43Z": two digits of fraction.
        #expect(clips[0].utc == 1_794_156_922_430)
        #expect(clips[1].utc == 1_794_156_922_430)
        #expect(clips[2].utc == 1_794_156_952_508)
        #expect(clips[3].utc == 1_794_157_986_215)
        #expect(clips.allSatisfy { $0.fileTime != nil })
    }

    @Test func qualifyingFixtureKeyedFromOne() throws {
        let clips = RadioClips(lines: try Fixture.lines("sp26-quali/TeamRadio.jsonStream")).all
        // Counted independently (Python) over the committed file, Q1's first 12 minutes: 16 clips
        // from 8 drivers. The whole session has 36 from 15; see `measuredCounts`.
        #expect(clips.count == 16)
        #expect(Set(clips.map(\.racingNumber)).count == 8)
        // "…48.5300321Z": seven digits of fraction, truncated to the millisecond.
        #expect(clips[0].utc == 1_794_074_148_530)
        #expect(clips[0].path == "TeamRadio/ALB_23_20261107_145514.mp3")
        #expect(clips.last?.utc == 1_794_074_820_736)
        // Keys "8"…"14" in one line, read in number order ("10" after "9").
        #expect(clips[8...].map(\.path) == [
            "TeamRadio/BOR_5_20261107_150551.mp3", "TeamRadio/LAW_30_20261107_150552.mp3",
            "TeamRadio/LAW_30_20261107_150555.mp3", "TeamRadio/BEA_87_20261107_150556.mp3",
            "TeamRadio/BEA_87_20261107_150600.mp3", "TeamRadio/BEA_87_20261107_150604.mp3",
            "TeamRadio/BOR_5_20261107_150605.mp3", "TeamRadio/HUL_27_20261107_150641.mp3",
        ])
        #expect(zip(clips, clips.dropFirst()).allSatisfy { $0.utc <= $1.utc })
    }

    @Test func duplicatesBadEntriesAndDayPrefix() {
        let clips = RadioClips(lines: lines(
            #"00:00:01.000{"Captures":[{"Utc":"2026-11-08T17:00:00Z","RacingNumber":"1","Path":"TeamRadio/A_1_20261108_140000.mp3"},null,7,{"Utc":"","RacingNumber":"1","Path":"TeamRadio/NoTime.mp3"}]}"#,
            // Sent again: kept once, with the first one's time.
            #"00:00:02.000{"Captures":{"2":{"Utc":"2026-11-08T17:05:00Z","RacingNumber":"1","Path":"TeamRadio/A_1_20261108_140000.mp3"}}}"#,
            #"00:00:03.000{"Captures":{"3":{"Utc":"2026-11-08T17:01:00Z","RacingNumber":"44","Path":""},"4":{"Utc":"nonsense","RacingNumber":"44","Path":"TeamRadio/Bad.mp3"},"x":{"Utc":"2026-11-08T17:01:00Z","RacingNumber":"44","Path":"TeamRadio/KeyX.mp3"}}}"#,
            #"00:00:04.000{"Captures":"none"}"#,
            #"00:00:05.000{"Other":1}"#,
            #"00:00:06.000[1,2]"#,
            // Race control leaves the Z off; Android adds it. A number as a number.
            #"1.02:32:50.914{"Captures":{"5":{"Utc":"2026-11-08T16:59:00","RacingNumber":63,"Path":"TeamRadio/RUS_63_20261108_135830.mp3"}}}"#,
            #"00:00:08.000{"Captures":{"6":{"Utc":"2026-11-08T16:59:00Z","Path":"TeamRadio/NoNumber.mp3"}}}"#
        )).all
        #expect(clips.map(\.path) == ["TeamRadio/RUS_63_20261108_135830.mp3", "TeamRadio/NoNumber.mp3",
                                      "TeamRadio/A_1_20261108_140000.mp3", "TeamRadio/KeyX.mp3"])
        #expect(clips.map(\.utc) == [1_794_157_140_000, 1_794_157_140_000, 1_794_157_200_000, 1_794_157_260_000])
        #expect(clips.map(\.racingNumber) == ["63", "", "1", "44"])
    }

    @Test func addingALineAtATimeMatchesBuildingAtOnce() throws {
        let all = try Fixture.lines("sp26-quali/TeamRadio.jsonStream")
        var clips = RadioClips()
        #expect(clips.all.isEmpty)
        for line in all { clips.add(line) }
        #expect(clips == RadioClips(lines: all))
        // A line read twice adds nothing.
        clips.add(all[3])
        #expect(clips == RadioClips(lines: all))
        // A clip published late with an earlier time goes in its place; equal times keep arrival order.
        clips.add(line(#"00:30:00.000{"Captures":{"99":{"Utc":"2026-11-07T17:55:48.530Z","RacingNumber":"81","Path":"TeamRadio/PIA_81_20261107_145500.mp3"}}}"#))
        #expect(clips.all[0].path == "TeamRadio/ALB_23_20261107_145514.mp3")
        #expect(clips.all[1].path == "TeamRadio/PIA_81_20261107_145500.mp3")
        #expect(clips.all.count == 17)
    }

    /// The committed files are the fixtures' windows (Fixtures/README.md), not whole sessions:
    /// the race's every line to 12 minutes after lights out, qualifying's to 12 minutes into Q1.
    /// Over the owner's whole private copies (not in the repo) this parser gives the spec's
    /// counts: the race 30 clips from 8 drivers (ANT 8, NOR 5, RUS 5, VER 4, HAM 3, HAD 3,
    /// LEC 1, GAS 1), qualifying 36 from 15. These are the windows' counts, measured in Python.
    @Test func measuredCounts() throws {
        func perCar(_ path: String) throws -> [String: Int] {
            RadioClips(lines: try Fixture.lines(path)).all.reduce(into: [:]) { $0[$1.racingNumber, default: 0] += 1 }
        }
        // NOR is car 1, ANT 12, LEC 16.
        #expect(try perCar("sp26-race/TeamRadio.jsonStream") == ["1": 1, "12": 2, "16": 1])
        // ANT 4, BEA 3, HAD 2, BOR 2, LAW 2, ALB 1, RUS 1, HUL 1.
        #expect(try perCar("sp26-quali/TeamRadio.jsonStream") == ["12": 4, "87": 3, "6": 2, "5": 2, "30": 2, "23": 1, "63": 1, "27": 1])
    }

    /// The spec's "Utc is 6–43 s after the file name's time in qualifying, 11–50 s in the race"
    /// (São Paulo is GMT−3), on the committed lines after each opening list. Rounded: the
    /// shortest, LAW_30_20261107_150555, is 5.514 s.
    @Test func publishedAfterTheFileNameTime() throws {
        for (path, range) in [("sp26-race/TeamRadio.jsonStream", Int64(10_000)...51_000), ("sp26-quali/TeamRadio.jsonStream", 5_000...44_000)] {
            let lines = try Fixture.lines(path)
            let opening = Set(RadioClips(lines: [lines[0]]).all.map(\.path))
            for clip in RadioClips(lines: lines).all where !opening.contains(clip.path) {
                let delay = clip.utc - (try #require(clip.fileUtc(gmtOffsetSeconds: -3 * 3600)))
                #expect(range.contains(delay), "\(clip.path): \(delay) ms")
            }
        }
        // The race's opening list holds older, pre-race clips: NOR's is 26 minutes old.
        let nor = RadioClips(lines: try Fixture.lines("sp26-race/TeamRadio.jsonStream")).all[0]
        #expect(nor.fileUtc(gmtOffsetSeconds: -3 * 3600).map { nor.utc - $0 } == 1_567_430)
    }

    // MARK: Audio address

    @Test func audioURLFromTheSessionPath() throws {
        let info = try #require(TimingSessionInfo.parse(try Fixture.json("sp26-race/SessionInfo.json")))
        let url = RadioClips.audioURL(sessionPath: info.path, clipPath: "TeamRadio/ANT_12_20261108_141229.mp3")
        #expect(url?.absoluteString == "https://livetiming.formula1.com/static/2026/2026-11-08_S%C3%A3o_Paulo_Grand_Prix/2026-11-08_Race/TeamRadio/ANT_12_20261108_141229.mp3")
        #expect(url?.host == "livetiming.formula1.com")
        // A session path without its closing slash gets one; never two.
        #expect(RadioClips.audioURL(sessionPath: "2026/x/2026-11-08_Race", clipPath: "TeamRadio/a.mp3")?.absoluteString
            == "https://livetiming.formula1.com/static/2026/x/2026-11-08_Race/TeamRadio/a.mp3")
        #expect(RadioClips.audioURL(sessionPath: "2026/x/2026-11-08_Race/", clipPath: "TeamRadio/a.mp3")?.absoluteString
            == "https://livetiming.formula1.com/static/2026/x/2026-11-08_Race/TeamRadio/a.mp3")
        // Spaces, "?" and "#" can't change what is asked for.
        #expect(RadioClips.audioURL(sessionPath: "2026/a b/", clipPath: "TeamRadio/x?y#z.mp3")?.absoluteString
            == "https://livetiming.formula1.com/static/2026/a%20b/TeamRadio/x%3Fy%23z.mp3")
    }

    @Test func audioURLStaysUnderTheArchive() {
        for (session, clip) in [("", "TeamRadio/a.mp3"), ("2026/x/", ""), ("/2026/x/", "TeamRadio/a.mp3"),
                                ("2026/x/", "/TeamRadio/a.mp3"), ("2026/x/", "../../../a.mp3"), ("2026/../x/", "a.mp3"),
                                ("2026/x/", "TeamRadio/./a.mp3"), ("2026/x/", "TeamRadio/"), ("2026/x/", "https://evil.example/a.mp3"),
                                ("2026/x/", "TeamRadio//a.mp3")] {
            #expect(RadioClips.audioURL(sessionPath: session, clipPath: clip) == nil, "\(session) + \(clip)")
        }
    }

    // MARK: At picture time

    @Test func visibleFromItsUtc() throws {
        let radio = RadioClips(lines: try Fixture.lines("sp26-race/TeamRadio.jsonStream"))
        let ant = radio.all[3]
        #expect(radio.visible(at: ant.utc - 1).count == 3)
        #expect(radio.visible(at: ant.utc).map(\.path) == radio.all.map(\.path))
        // Two clips published at the same moment appear together.
        #expect(radio.visible(at: 1_794_156_922_429).isEmpty)
        #expect(radio.visible(at: 1_794_156_922_430).count == 2)
        #expect(radio.visible(at: .min).isEmpty)
        #expect(radio.visible(at: .max).count == 4)
        // nil is "Show the whole race": everything.
        #expect(radio.visible(at: nil).count == 4)
        // One driver.
        #expect(radio.visible(at: ant.utc - 1, driver: "12").map(\.path) == ["TeamRadio/ANT_12_20261108_132331.mp3"])
        #expect(radio.visible(at: ant.utc, driver: "12").count == 2)
        #expect(radio.visible(at: nil, driver: "16").map(\.racingNumber) == ["16"])
        #expect(radio.visible(at: nil, driver: "44").isEmpty)
        #expect(RadioClips().visible(at: nil).isEmpty)
    }

    // MARK: Lap labels

    @Test func raceLabelsFromTheFixture() throws {
        let session = try RaceFixture.race()
        let clips = RadioClips(lines: try Fixture.lines("sp26-race/TeamRadio.jsonStream")).all
        // Three pre-race clips (lights out is 17:03:23.965Z), then ANT at 17:13:06.215Z: F1's
        // NumberOfLaps for car 12 was 6 from 17:12:08.239Z (checked in Python over the committed
        // TimingData), so lap 7, as Android's lapAt.
        #expect(clips.map { RadioClips.lapLabel(for: $0, in: session) } == [.beforeStart, .beforeStart, .beforeStart, .lap(7)])
    }

    @Test func raceLabelReadsNothingAfterTheClip() throws {
        // A session cut at each clip's Utc labels it as the whole session does.
        let full = try RaceFixture.race()
        for clip in RadioClips(lines: try Fixture.lines("sp26-race/TeamRadio.jsonStream")).all {
            let cut = try RaceFixture.load("sp26-race", streamStart: Fixture.raceStart, cutAt: clip.utc)
            #expect(RadioClips.lapLabel(for: clip, in: cut) == RadioClips.lapLabel(for: clip, in: full))
        }
    }

    @Test func raceLabelsAroundTheStartAndTheFlag() {
        let session = RaceFixture.synthetic(
            timing: lines(#"00:00:01.000{"Lines":{"44":{"Position":"1"},"1":{"Position":"2"}}}"#,
                          #"00:01:40.000{"Lines":{"44":{"NumberOfLaps":1}}}"#,
                          #"00:03:20.000{"Lines":{"44":{"NumberOfLaps":2}}}"#),
            sessionStatus: lines(#"00:00:00.500{"Status":"Inactive"}"#,
                                 #"00:00:10.000{"Status":"Started"}"#,
                                 #"00:03:20.000{"Status":"Finished"}"#,
                                 #"00:05:00.000{"Status":"Finalised"}"#),
            start: 1_000_000)
        func label(_ offset: Int64, _ car: String = "44") -> RadioLapLabel {
            RadioClips.lapLabel(for: RadioClip(utc: 1_000_000 + offset, racingNumber: car, path: "p"), in: session)
        }
        #expect(label(0) == .beforeStart)
        #expect(label(9_999) == .beforeStart)
        // Lights out with no count yet: F1 sends none until lap 1 ends, so lap 1 (Android shows nothing).
        #expect(label(10_000) == .lap(1))
        #expect(label(99_999) == .lap(1))
        #expect(label(100_000) == .lap(2))
        #expect(label(199_999) == .lap(2))
        #expect(label(199_999, "1") == .lap(1))
        // The leader's flag: after it, every car.
        #expect(label(200_000) == .afterFlag)
        #expect(label(200_000, "1") == .afterFlag)
        #expect(label(400_000) == .afterFlag)
        // A car with no timing at all, during the race: lap 1 as well.
        #expect(label(50_000, "99") == .lap(1))
    }

    @Test func raceLabelsWithoutTheStart() {
        // Joined with the race under way: the opening state says "Started", so the start isn't
        // known and a car with no count yet has no lap.
        var joined = RaceFixture.synthetic(timing: lines(#"00:00:30.000{"Lines":{"44":{"NumberOfLaps":12}}}"#), start: 1_000_000)
        joined.sessionStatus = SessionStatusTimeline.build(lines: lines(#"00:00:00.000{"Status":"Started"}"#),
                                                           streamStart: 1_000_000, snapshotLines: [0])
        func label(_ offset: Int64, _ car: String = "44", in session: LoadedSession) -> RadioLapLabel {
            RadioClips.lapLabel(for: RadioClip(utc: 1_000_000 + offset, racingNumber: car, path: "p"), in: session)
        }
        #expect(label(10_000, in: joined) == .unknown)
        #expect(label(30_000, in: joined) == .lap(13))
        #expect(label(30_000, "1", in: joined) == .unknown)
        // Joined before lights out: "Inactive" on joining is still before the start.
        var early = joined
        early.sessionStatus = SessionStatusTimeline.build(lines: lines(#"00:00:00.000{"Status":"Inactive"}"#),
                                                          streamStart: 1_000_000, snapshotLines: [0])
        #expect(label(10_000, in: early) == .beforeStart)
        // Joined after the flag.
        var late = joined
        late.sessionStatus = SessionStatusTimeline.build(lines: lines(#"00:00:00.000{"Status":"Finished"}"#),
                                                         streamStart: 1_000_000, snapshotLines: [0])
        #expect(label(30_000, in: late) == .afterFlag)
        // No SessionStatus at all: only the count.
        let bare = RaceFixture.synthetic(timing: lines(#"00:00:30.000{"Lines":{"44":{"NumberOfLaps":12}}}"#), start: 1_000_000)
        #expect(label(10_000, in: bare) == .unknown)
        #expect(label(30_000, in: bare) == .lap(13))
    }

    @Test func qualifyingLabelsFromTheFixture() throws {
        var session = try RaceFixture.quali()
        session.header = HeaderTimeline.build(lapCount: [], clock: try Fixture.lines("sp26-quali/ExtrapolatedClock.jsonStream"),
                                              weather: [], streamStart: Fixture.qualiStart)
        let labels = RadioClips(lines: try Fixture.lines("sp26-quali/TeamRadio.jsonStream")).all
            .map { RadioClips.lapLabel(for: $0, in: session) }
        // Checked in Python over the committed files. Four clips before Q1 started (18:00:02.309Z).
        #expect(Array(labels[..<4]) == Array(repeating: .beforeStart, count: 4))
        // RUS at 18:00:54.281Z: the clock said 17:59 and running at 18:00:01.011Z, so 17:05.730 left.
        #expect(labels[4] == .qualifying(part: 1, remainingMs: 1_025_730))
        // ANT at 18:01:54.570Z (seven digits of fraction, cut to the millisecond): 16:05.441 left.
        #expect(labels[5] == .qualifying(part: 1, remainingMs: 965_441))
        // The rest under Q1's red flag: the clock stopped at 15:37.
        #expect(Array(labels[6...]) == Array(repeating: .qualifying(part: 1, remainingMs: 937_000), count: 10))
    }

    @Test func practiceAndQualifyingByHand() {
        var practice = RaceFixture.synthetic(type: "Practice", timing: [],
                                             sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#,
                                                                  #"01:00:10.000{"Status":"Finished"}"#),
                                             start: 1_000_000)
        func label(_ offset: Int64, in session: LoadedSession) -> RadioLapLabel {
            RadioClips.lapLabel(for: RadioClip(utc: 1_000_000 + offset, racingNumber: "44", path: "p"), in: session)
        }
        #expect(label(9_999, in: practice) == .beforeStart)
        #expect(label(10_000, in: practice) == .practice(elapsedMs: 0))
        #expect(label(754_000, in: practice) == .practice(elapsedMs: 744_000))
        // After the session's end the time keeps counting: practice has no flag label.
        #expect(label(3_610_001, in: practice) == .practice(elapsedMs: 3_600_001))
        // Without a known start, no elapsed time.
        practice.sessionStatus = SessionStatusTimeline()
        #expect(label(10_000, in: practice) == .unknown)

        // Qualifying with no clock and no parts: both unknown, still qualifying.
        let quali = RaceFixture.synthetic(type: "Qualifying", timing: [],
                                          sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#), start: 1_000_000)
        #expect(label(20_000, in: quali) == .qualifying(part: nil, remainingMs: nil))
        #expect(label(5_000, in: quali) == .beforeStart)
    }
}

@Suite struct TranscriptionQueueTests {
    /// Clips at these picture times (seconds), named "c<seconds>".
    func clips(_ seconds: Int64...) -> [RadioClip] {
        seconds.map { RadioClip(utc: $0 * 1000, racingNumber: "1", path: "c\($0)") }
    }

    @Test func nearestThePictureFirstUpToTwoMinutesAhead() {
        let all = clips(10, 100, 200, 290, 320, 321)
        var queue = TranscriptionQueue()
        var order: [String] = []
        var now: Int64 = 0
        // Picture at 200 s: 320 is exactly 2 minutes ahead (in), 321 is past it (out). Behind has no limit.
        while let clip = queue.next(from: all, at: 200_000, now: now) {
            order.append(clip.path)
            queue.finished(path: clip.path, result: "copy")
            now += 1_000
        }
        #expect(order == ["c200", "c290", "c100", "c320", "c10"])
        #expect(queue.transcribing == nil)
        // As the picture moves on, 321 comes in range.
        #expect(queue.next(from: all, at: 201_000, now: now)?.path == "c321")
    }

    @Test func tiesGoToTheEarlierClip() {
        var queue = TranscriptionQueue()
        #expect(queue.next(from: clips(90, 110), at: 100_000, now: 0)?.path == "c90")
    }

    @Test func fixtureOrder() throws {
        let radio = RadioClips(lines: try Fixture.lines("sp26-race/TeamRadio.jsonStream")).all
        var queue = TranscriptionQueue()
        var order: [String] = []
        // A minute before ANT's race clip: it's in range and nearest; then backwards, two
        // clips published together in the order they came.
        while let clip = queue.next(from: radio, at: radio[3].utc - 60_000, now: 0) {
            order.append(clip.path)
            queue.finished(path: clip.path, result: "")
        }
        #expect(order == ["TeamRadio/ANT_12_20261108_141229.mp3", "TeamRadio/LEC_16_20261108_135537.mp3",
                          "TeamRadio/NOR_1_20261108_132915.mp3", "TeamRadio/ANT_12_20261108_132331.mp3"])
        // Nothing recognised is a result, so none of them comes back.
        #expect(Set(queue.results.values) == [TranscriptionQueue.noWords])
        #expect(queue.next(from: radio, at: .max, now: 0) == nil)
    }

    @Test func oneAtATimeAndA45SecondTimeoutSkips() {
        let all = clips(100, 110)
        var queue = TranscriptionQueue()
        #expect(queue.next(from: all, at: 100_000, now: 1_000)?.path == "c100")
        #expect(queue.transcribing == "c100")
        // Asking again while it runs gives nothing, and doesn't restart its 45 s.
        #expect(queue.next(from: all, at: 100_000, now: 20_000) == nil)
        #expect(queue.next(from: all, at: 100_000, now: 45_999) == nil)
        // 45 s after it began: skipped, and the next one starts.
        #expect(queue.next(from: all, at: 100_000, now: 46_000)?.path == "c110")
        #expect(queue.transcribing == "c110")
        queue.finished(path: "c110", result: "box box")
        // The skipped clip isn't tried again.
        #expect(queue.next(from: all, at: 100_000, now: 50_000) == nil)
        // A result arriving late for it is still kept.
        queue.finished(path: "c100", result: "late words")
        #expect(queue.results == ["c100": "late words", "c110": "box box"])
    }

    @Test func timeoutsDontCountAsFailures() {
        let all = clips(1, 2, 3, 4)
        var queue = TranscriptionQueue()
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c1")
        queue.timedOut(path: "c1")
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c2")
        queue.failed(path: "c2", at: 0)
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c3")
        queue.timedOut(path: "c3")
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c4")
        queue.failed(path: "c4", at: 0)
        #expect(queue.failuresInRow == 2)
        #expect(queue.waitingUntil == nil)
    }

    @Test func threeFailuresInARowWaitTwoMinutesThenRetry() {
        let all = clips(1, 2, 3, 4)
        var queue = TranscriptionQueue()
        for (i, path) in ["c1", "c2", "c3"].enumerated() {
            #expect(queue.next(from: all, at: 0, now: Int64(i) * 1_000)?.path == path)
            queue.failed(path: path, at: Int64(i) * 1_000)
        }
        // The third failure at 2 s: nothing until 2 minutes later.
        #expect(queue.waitingUntil == 122_000)
        #expect(queue.failuresInRow == 0)
        #expect(queue.next(from: all, at: 0, now: 2_000) == nil)
        #expect(queue.next(from: all, at: 0, now: 121_999) == nil)
        // Then the failed clips are tried again, nearest first.
        #expect(queue.next(from: all, at: 0, now: 122_000)?.path == "c1")
        #expect(queue.waitingUntil == nil)
    }

    @Test func aResultEndsTheRun() {
        let all = clips(1, 2, 3, 4)
        var queue = TranscriptionQueue()
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c1")
        queue.failed(path: "c1", at: 0)
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c2")
        queue.failed(path: "c2", at: 0)
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c3")
        queue.finished(path: "c3", result: "copy")
        #expect(queue.failuresInRow == 0)
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c4")
        queue.failed(path: "c4", at: 0)
        #expect(queue.waitingUntil == nil)
    }

    @Test func staleReportsAreIgnored() {
        let all = clips(1, 2)
        var queue = TranscriptionQueue()
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c1")
        // A failure or timeout for a clip that isn't running changes nothing.
        queue.failed(path: "c2", at: 0)
        queue.timedOut(path: "c2")
        #expect(queue.failuresInRow == 0)
        #expect(queue.transcribing == "c1")
        // c1 timed out (skipped) by the time its failure comes: not counted.
        #expect(queue.next(from: all, at: 0, now: 45_000)?.path == "c2")
        queue.failed(path: "c1", at: 45_000)
        #expect(queue.failuresInRow == 0)
        #expect(queue.transcribing == "c2")
    }

    @Test func resultsAreKeptByPath() {
        let all = clips(1, 2, 3)
        // Transcripts kept from before (a replay watched again) are never queued.
        var queue = TranscriptionQueue(results: ["c1": "copy", "c2": TranscriptionQueue.noWords])
        #expect(queue.next(from: all, at: 0, now: 0)?.path == "c3")
        queue.finished(path: "c3", result: "  \n ")
        #expect(queue.results["c3"] == "(no words recognised)")
        #expect(queue.next(from: all, at: 0, now: 0) == nil)
        // Text is kept as recognised, trimmed.
        var other = TranscriptionQueue()
        _ = other.next(from: all, at: 0, now: 0)
        other.finished(path: "c1", result: " Box this lap. ")
        #expect(other.results["c1"] == "Box this lap.")
        var empty = TranscriptionQueue()
        #expect(empty.next(from: [], at: 0, now: 0) == nil)
        #expect(empty.transcribing == nil)
    }

    @Test func extremeTimesDontTrap() {
        var queue = TranscriptionQueue()
        let far = [RadioClip(utc: .min, racingNumber: "1", path: "a"), RadioClip(utc: .max, racingNumber: "1", path: "b")]
        #expect(queue.next(from: far, at: .max, now: .max)?.path == "b")
        #expect(queue.next(from: far, at: .max, now: .min) == nil)
        queue.failed(path: "b", at: .max)
        #expect(queue.next(from: far, at: .min, now: .max)?.path == "a")
    }
}

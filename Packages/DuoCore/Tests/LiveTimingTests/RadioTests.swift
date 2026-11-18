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
}

import Foundation
import Testing
@testable import LiveTiming

/// Whole-session radio, on the long slices (`sp26-race-long`, `sp26-quali-long`). Every number
/// below is a `check:` line printed by `spike/trim_fixtures.py` (decoded independently in Python
/// from the raw archive's files).
@Suite struct RadioRaceTests {
    /// A session from a long slice: timing is the reduced TimingData, there are no stints.
    static func longRace() throws -> LoadedSession {
        let folder = "sp26-race-long", start = Fixture.raceStart
        func stream(_ name: String) throws -> [StreamLine] { try Fixture.lines("\(folder)/\(name).jsonStream") }
        let info = try #require(TimingSessionInfo.parse(try Fixture.json("\(folder)/SessionInfo.json")))
        return LoadedSession(
            info: info,
            drivers: Drivers.parse(try Fixture.json("\(folder)/DriverList.json")),
            streamStart: start,
            positions: PositionSeries(cars: [:]),
            timing: TimingTimeline.build(lines: try stream("TimingData"), streamStart: start),
            stints: StintTimeline.build(lines: [], streamStart: start),
            header: HeaderTimeline.build(lapCount: try stream("LapCount"), clock: [], weather: [], streamStart: start),
            flags: TrackFlags.build(trackStatus: try stream("TrackStatus"), raceControl: try stream("RaceControlMessages"),
                                    streamStart: start, gmtOffsetSeconds: info.gmtOffsetSeconds),
            sessionStatus: SessionStatusTimeline.build(lines: try stream("SessionStatus"), streamStart: start),
            missing: []
        )
    }

    static func raceRadio() throws -> RadioClips { RadioClips(lines: try Fixture.lines("sp26-race-long/TeamRadio.jsonStream")) }

    // check:longRaceStartedUtc, check:longRaceFinishedUtc
    static let started: UTCms = 1_794_157_403_965
    static let finished: UTCms = 1_794_163_127_728

    @Test func wholeRaceHas30ClipsFrom8Drivers() throws {
        let session = try Self.longRace()
        let clips = try Self.raceRadio().all
        // check:longRaceClipCount, check:longRaceClipsPerDriver
        #expect(clips.count == 30)
        var perDriver: [String: Int] = [:]
        for clip in clips { perDriver[try #require(session.drivers[clip.racingNumber]).tla, default: 0] += 1 }
        #expect(perDriver == ["ANT": 8, "NOR": 5, "RUS": 5, "VER": 4, "HAM": 3, "HAD": 3, "LEC": 1, "GAS": 1])
        #expect(zip(clips, clips.dropFirst()).allSatisfy { $0.utc <= $1.utc })
        #expect(Set(clips.map(\.path)).count == 30)
        // The session path and the clip path make the clip's address.
        let url = RadioClips.audioURL(sessionPath: session.info.path, clipPath: clips[1].path)
        #expect(url?.absoluteString.hasPrefix("https://livetiming.formula1.com/static/2026/") == true)
        #expect(url?.absoluteString.hasSuffix("/TeamRadio/ANT_12_20261108_132331.mp3") == true)
    }

    @Test func antOnLaps19_20_22() throws {
        let session = try Self.longRace()
        let ant = try Self.raceRadio().all.filter { $0.racingNumber == "12" }
        // check:longRaceAntClips: published 17:30:23.527Z, 17:31:23.712Z and 17:34:26.469Z when F1's
        // NumberOfLaps for car 12 was 18, 19 and 21, so Android's lapAt (count + 1) says 19, 20, 22.
        let wanted: [(UTCms, RadioLapLabel)] = [(1_794_159_023_527, .lap(19)), (1_794_159_083_712, .lap(20)), (1_794_159_266_469, .lap(22))]
        for (utc, label) in wanted {
            let clip = try #require(ant.first { $0.utc == utc })
            #expect(RadioClips.lapLabel(for: clip, in: session) == label)
        }
        // All eight: the pre-race one, lap 7, the three above, lap 25, and two late ones (laps 53, 58).
        #expect(ant.map { RadioClips.lapLabel(for: $0, in: session) } ==
                [.beforeStart, .lap(7), .lap(19), .lap(20), .lap(22), .lap(25), .lap(53), .lap(58)])
    }

    @Test func lastFourAfterTheFlag() throws {
        let session = try Self.longRace()
        let clips = try Self.raceRadio().all
        let labels = clips.map { RadioClips.lapLabel(for: $0, in: session) }
        // check:longRaceAfterFlagCount = 4 (NOR, RUS, VER, NOR) after Finished at 18:38:47.728Z.
        #expect(clips.filter { $0.utc > Self.finished }.count == 4)
        #expect(Array(labels.suffix(4)) == Array(repeating: .afterFlag, count: 4))
        #expect(!labels.dropLast(4).contains(.afterFlag))
        // check:longRaceBeforeStartCount = 3: before lights out (17:03:23.965Z).
        #expect(clips.filter { $0.utc < Self.started }.count == 3)
        #expect(Array(labels.prefix(3)) == Array(repeating: .beforeStart, count: 3))
        #expect(!labels.dropFirst(3).contains(.beforeStart))
        // Every clip in between reads a lap (none is left blank).
        for label in labels[3..<26] {
            if case .lap = label {} else { Issue.record("not a lap: \(label)") }
        }
    }

    @Test func qualifyingHas36ClipsFrom15Drivers() throws {
        // check:longQualiClipCount, check:longQualiDriverCount
        let clips = RadioClips(lines: try Fixture.lines("sp26-quali-long/TeamRadio.jsonStream")).all
        #expect(clips.count == 36)
        #expect(Set(clips.map(\.racingNumber)).count == 15)
        #expect(zip(clips, clips.dropFirst()).allSatisfy { $0.utc <= $1.utc })
    }

    @Test func lapsSeventeenToTwentyThreeShowOnlyReached() throws {
        let radio = try Self.raceRadio()
        // check:longRaceLap23PictureTime: car 12's NumberOfLaps reaches 22, so it is on lap 23.
        let t: UTCms = 1_794_159_313_992
        // check:longRaceVisibleAtLap23: ten clips have been published by then.
        let expected: [UTCms] = [1_794_156_922_430, 1_794_156_922_430, 1_794_156_952_508, 1_794_157_986_215, 1_794_158_201_094,
                                 1_794_158_352_023, 1_794_158_567_246, 1_794_159_023_527, 1_794_159_083_712, 1_794_159_266_469]
        #expect(radio.visible(at: t).map(\.utc) == expected)
        #expect(radio.visible(at: t).allSatisfy { $0.utc <= t })
        // A clip appears exactly at its Utc, not a millisecond before.
        #expect(radio.visible(at: 1_794_159_266_468).count == 9)
        #expect(radio.visible(at: 1_794_159_266_469).count == 10)
        // ANT's own by lap 23: the pre-race one, laps 7, 19, 20 and 22.
        #expect(radio.visible(at: t, driver: "12").count == 5)
        #expect(radio.visible(at: nil).count == 30)
        // Picture time before the first clip: nothing.
        #expect(radio.visible(at: 1_794_156_922_429).isEmpty)
    }
}

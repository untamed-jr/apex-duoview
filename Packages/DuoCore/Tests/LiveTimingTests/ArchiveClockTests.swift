import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct ArchiveClockTests {
    @Test func streamStartIsHeartbeatMedian() throws {
        // The race's Position clock is 2.1 s off (check:raceStartsDifferMs = −2102): under 60 s.
        let race = ArchiveClock.streamStart(heartbeat: try Fixture.lines("sp26-race/Heartbeat.jsonStream"),
                                            positions: try Fixture.lines("sp26-race/Position.z.jsonStream"))
        #expect(race == Fixture.raceStart)  // check:raceHeartbeatStart
        let quali = ArchiveClock.streamStart(heartbeat: try Fixture.lines("sp26-quali/Heartbeat.jsonStream"),
                                             positions: try Fixture.lines("sp26-quali/Position.z.jsonStream"))
        #expect(quali == Fixture.qualiStart)  // check:qualiHeartbeatStart
    }

    @Test func streamStartPositionWinsWhenHeartbeatOffBy33Hours() throws {
        let shifted = try Fixture.lines("sp26-race/Heartbeat.jsonStream").map { beat -> StreamLine in
            let utc = try #require(SignalR.utc(beat.json["Utc"].string))
            return StreamLine(offsetMs: beat.offsetMs, json: .object(["Utc": .string(iso(utc + 33 * 3_600_000))]))
        }
        let start = ArchiveClock.streamStart(heartbeat: shifted, positions: try Fixture.lines("sp26-race/Position.z.jsonStream"))
        #expect(start == 1_794_154_177_287)  // check:racePositionStart (= check:raceShiftedBy33hPicks)
    }

    @Test func oneOddBeatDoesntMoveTheStart() {
        let beats = lines(
            #"00:00:05.000{"Utc":"2026-10-26T05:00:05.0000000Z"}"#,
            #"00:00:10.000{"Utc":"2026-10-24T20:00:10.0000000Z"}"#,
            #"00:00:15.000{"Utc":"2026-10-24T20:00:15.0000000Z","_kf":true}"#
        )
        #expect(ArchiveClock.streamStart(heartbeat: beats, positions: []) == SignalR.utc("2026-10-24T20:00:00Z"))
    }

    @Test func eitherStreamAloneOrNeither() {
        let t0: UTCms = 1_794_157_400_000
        let positions = [zLine(1000, #"{"Position":[{"Timestamp":"\#(iso(t0 + 1220))","Entries":{}}]}"#)]
        #expect(ArchiveClock.streamStart(heartbeat: [], positions: positions) == t0 + 220)
        #expect(ArchiveClock.streamStart(heartbeat: lines(#"00:00:01.000{"Nope":1}"#), positions: []) == nil)
    }
}

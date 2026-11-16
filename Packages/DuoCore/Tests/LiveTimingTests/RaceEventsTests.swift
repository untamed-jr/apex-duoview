import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct RaceEventsTests {
    @Test func eventsCutAtPictureTime() throws {
        let race = try RaceFixture.race()
        let s = Fixture.raceStart
        // spike/race_checks.py, check:raceEventsAtLightsOutPlus10min: 77 retires at 3347533 on
        // lap 2; 12 sets each new fastest lap at 3404021, 3490415 and 3576430 (laps 3, 4, 5 in
        // progress). No car goes into the pits after the start in the fixture. Lights out
        // (check:raceLightsOutUtc) is on lap 1.
        let upTo10min: [RaceEvent] = [
            RaceEvent(t: Fixture.raceLightsOut, lap: 1, kind: .lightsOut, end: nil),
            RaceEvent(t: s + 3_347_533, lap: 2, kind: .retirement(car: "77"), end: nil),
            RaceEvent(t: s + 3_404_021, lap: 3, kind: .fastestLap(car: "12"), end: nil),
            RaceEvent(t: s + 3_490_415, lap: 4, kind: .fastestLap(car: "12"), end: nil),
            RaceEvent(t: s + 3_576_430, lap: 5, kind: .fastestLap(car: "12"), end: nil),
        ]
        #expect(RaceEvents.list(until: RaceFixture.raceT, session: race) == upTo10min)
        // check:raceEventsWholeFixture: 1's fastest lap at 3839709 (lap 8) comes after.
        #expect(RaceEvents.list(until: nil, session: race)
                == upTo10min + [RaceEvent(t: s + 3_839_709, lap: 8, kind: .fastestLap(car: "1"), end: nil)])
        #expect(RaceEvents.list(until: s + 3_839_708, session: race) == upTo10min)
        #expect(RaceEvents.list(until: Fixture.raceLightsOut - 1, session: race).isEmpty)
        #expect(RaceEvents.list(until: Fixture.raceLightsOut, session: race) == [upTo10min[0]])

        // Nothing later than t is read: the session cut at t gives the same list.
        for u in [Fixture.raceLightsOut, s + 3_347_533, s + 3_490_414, RaceFixture.raceT] {
            let cut = try RaceFixture.load("sp26-race", streamStart: s, cutAt: u)
            #expect(RaceEvents.list(until: u, session: cut) == RaceEvents.list(until: u, session: race))
        }
    }

    @Test func eventsIncludeSCBandWithEnd() throws {
        // A safety car from 10 s to 70 s, then a VSC from 100 s, ending at 130 s.
        let session = RaceFixture.synthetic(
            timing: [timingLine("00:00:00.000", [("1", #""Position":"1""#)])],
            trackStatus: lines(#"00:00:10.000{"Status":"4"}"#, #"00:01:10.000{"Status":"1"}"#,
                               #"00:01:40.000{"Status":"6"}"#, #"00:02:00.000{"Status":"7"}"#,
                               #"00:02:10.000{"Status":"1"}"#),
            sessionStatus: lines(#"00:00:05.000{"Status":"Started"}"#))
        let s: UTCms = 1_000_000
        let sc = RaceEvent(t: s + 10_000, lap: 1, kind: .safetyCar, end: s + 70_000)
        let vsc = RaceEvent(t: s + 100_000, lap: 1, kind: .vsc, end: s + 130_000)
        let lightsOut = RaceEvent(t: s + 5_000, lap: 1, kind: .lightsOut, end: nil)
        #expect(RaceEvents.list(until: nil, session: session) == [lightsOut, sc, vsc])
        #expect(RaceEvents.list(until: s + 130_000, session: session) == [lightsOut, sc, vsc])
        // Still out at picture time: the band has no end yet ("VSC ending" is still the VSC).
        var open = vsc
        open.end = nil
        #expect(RaceEvents.list(until: s + 129_999, session: session) == [lightsOut, sc, open])
        var openSC = sc
        openSC.end = nil
        #expect(RaceEvents.list(until: s + 69_999, session: session) == [lightsOut, openSC])
        #expect(RaceEvents.list(until: s + 9_999, session: session) == [lightsOut])

        // Qualifying's red flag in the fixture: from race control's RED FLAG
        // (check:qualiRedFlagUtc = 1794074543000, before TrackStatus's 5 at
        // check:qualiTrackStatusRedUtc) to past the data's end, so no end even for the whole
        // session. Qualifying runs by time: no laps.
        let quali = try RaceFixture.quali()
        let red = RaceEvent(t: 1_794_074_543_000, lap: nil, kind: .red, end: nil)
        let all = RaceEvents.list(until: nil, session: quali)
        #expect(all.filter { if case .red = $0.kind { return true } else { return false } } == [red])
        #expect(all.first == RaceEvent(t: Fixture.qualiQ1, lap: nil, kind: .lightsOut, end: nil))
        #expect(all.allSatisfy { $0.lap == nil })
        #expect(!RaceEvents.list(until: red.t - 1, session: quali).contains(red))
    }

    @Test func eventsPitStopsAfterTheStart() {
        // Car 44 sits in the pit lane before the start (no stop), then stops from 60 s to 85 s
        // on lap 2, with the leader's lap count rising at 50 s. LapCount caps the lap at 2.
        let session = RaceFixture.synthetic(
            timing: [
                timingLine("00:00:00.000", [("1", #""Position":"1""#), ("44", #""Position":"2","InPit":true"#)]),
                timingLine("00:00:20.000", [("44", #""InPit":false,"PitOut":true"#)]),
                timingLine("00:00:50.000", [("1", #""NumberOfLaps":1"#), ("44", #""NumberOfLaps":1"#)]),
                timingLine("00:01:00.000", [("44", #""InPit":true"#)]),
                timingLine("00:01:25.000", [("44", #""InPit":false,"PitOut":true"#)]),
                timingLine("00:01:40.000", [("1", #""NumberOfLaps":2"#)]),
                timingLine("00:01:50.000", [("44", #""Retired":true,"Stopped":true"#)]),
            ],
            sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#, #"00:02:00.000{"Status":"Finished"}"#),
            lapCount: lines(#"00:00:00.000{"CurrentLap":1,"TotalLaps":2}"#))
        let s: UTCms = 1_000_000
        let pit = RaceEvent(t: s + 60_000, lap: 2, kind: .pit(car: "44"), end: s + 85_000)
        #expect(RaceEvents.list(until: nil, session: session) == [
            RaceEvent(t: s + 10_000, lap: 1, kind: .lightsOut, end: nil),
            pit,
            RaceEvent(t: s + 110_000, lap: 2, kind: .retirement(car: "44"), end: nil),
            RaceEvent(t: s + 120_000, lap: 2, kind: .chequered, end: nil),
        ])
        var inLane = pit
        inLane.end = nil
        #expect(RaceEvents.list(until: s + 84_999, session: session).last == inLane)
    }
}

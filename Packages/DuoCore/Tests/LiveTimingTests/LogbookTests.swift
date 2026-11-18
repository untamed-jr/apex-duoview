import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct LogbookTests {
    static let s: UTCms = 1_000_000

    /// Car 44 (P2 behind 1), lap count 1 at 50 s, in the pits 60 s to 85 s, MEDIUM then HARD.
    /// Car 1 leads; car 63 is third and takes P2 when 44 comes out.
    static func session() -> LoadedSession {
        RaceFixture.synthetic(
            timing: [
                timingLine("00:00:00.000", [("1", #""Position":"1""#), ("44", #""Position":"2""#), ("63", #""Position":"3""#)]),
                timingLine("00:00:50.000", [("1", #""NumberOfLaps":1"#), ("44", #""NumberOfLaps":1,"LastLapTime":{"Value":"1:29.518"}"#)]),
                timingLine("00:01:00.000", [("44", #""InPit":true"#)]),
                timingLine("00:01:25.000", [("44", #""InPit":false,"PitOut":true,"Position":"3""#), ("63", #""Position":"2""#)]),
            ],
            sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#),
            stints: [
                line(#"00:00:00.000{"Lines":{"44":{"Stints":{"0":{"Compound":"MEDIUM","New":"true","StartLaps":0,"TotalLaps":0}}}}}"#),
                line(#"00:01:10.000{"Lines":{"44":{"Stints":{"1":{"Compound":"HARD","New":"true","StartLaps":0,"TotalLaps":0}}}}}"#),
                line(#"00:02:00.000{"Lines":{"44":{"Stints":{"1":{"TotalLaps":4}}}}}"#),
            ])
    }

    /// Radio: 44 at 30 s and 120 s, 1 at 40 s.
    static func radio() -> RadioClips {
        func clip(_ n: String, _ ms: Int64, _ name: String) -> String {
            #"{"Utc":"\#(iso(s + ms))","RacingNumber":"\#(n)","Path":"TeamRadio/\#(name).mp3"}"#
        }
        return RadioClips(lines: lines(
            #"00:00:01.000{"Captures":[\#(clip("44", 30_000, "A")),\#(clip("1", 40_000, "B")),\#(clip("44", 120_000, "C"))]}"#))
    }

    static func control() -> [RaceControlEntry] {
        RaceControlLog.parse(lines: lines(
            #"00:00:20.000{"Messages":[{"Utc":"\#(iso(s + 20_000))","Category":"Flag","Flag":"BLUE","RacingNumber":"44","Message":"WAVED BLUE FLAG FOR CAR 44 (HAM)"}]}"#,
            #"00:01:30.000{"Messages":{"1":{"Utc":"\#(iso(s + 90_000))","Category":"Other","Message":"INCIDENT INVOLVING CAR 63 (RUS) NOTED"}}}"#,
            #"00:02:30.000{"Messages":{"2":{"Utc":"\#(iso(s + 150_000))","Category":"Other","Message":"CAR 44 (HAM) TIME DELETED"}}}"#,
            #"00:02:31.000{"Messages":{"3":{"Utc":"\#(iso(s + 160_000))","Category":"Other","Message":"TRACK LIMITS"}}}"#),
            streamStart: s)
    }

    @Test func raceControlNamesCarFromText() {
        let all = Self.control()
        #expect(all.count == 4)
        #expect(all[1].cars == ["63"])
        #expect(all[2].cars == ["44"])
        #expect(all[3].cars.isEmpty)
        #expect(RaceControlLog.entries(for: "63", until: nil, in: all).map(\.text) == ["INCIDENT INVOLVING CAR 63 (RUS) NOTED"])
        // Two cars in one message, and a number written twice counts once.
        let two = RaceControlLog.parse(lines: lines(
            #"00:00:01.000{"Messages":[{"Utc":"\#(iso(Self.s))","RacingNumber":"4","Message":"CARS 87 (BEA) AND 55 (SAI) NOTED, CAR 4 (NOR) TOO"}]}"#),
            streamStart: Self.s)
        // The RacingNumber first, then the text's cars, each once.
        #expect(two.first?.cars == ["4", "87", "55"])
    }

    @Test func raceControlKeepsCategoryAndFlag() {
        let all = Self.control()
        #expect(all[0].flag == "BLUE")
        #expect(all[0].category == "Flag")
        #expect(all[1].flag == nil)
        #expect(all[1].category == "Other")
    }

    @Test func raceControlAddedLineByLineDedups() {
        var log = RaceControlLog(streamStart: Self.s)
        let first = lines(#"00:00:01.000{"Messages":[{"Utc":"\#(iso(Self.s + 5_000))","Message":"CAR 1 (VER) A"}]}"#)
        let early = lines(#"00:00:02.000{"Messages":[{"Utc":"\#(iso(Self.s))","Message":"B"}]}"#)
        for l in first + early + first { log.add(l) }
        #expect(log.all.map(\.text) == ["B", "CAR 1 (VER) A"])
        #expect(log.all == RaceControlLog.parse(lines: first + early, streamStart: Self.s))
    }

    @Test func longRaceMultiCarInvestigationReachesBothLogbooks() throws {
        let session = try RadioRaceTests.longRace()
        let control = RaceControlLog.parse(lines: try Fixture.lines("sp26-race-long/RaceControlMessages.jsonStream"),
                                           streamStart: session.streamStart)
        for number in ["87", "55"] {
            let hits = RaceControlLog.entries(for: number, until: nil, in: control)
            #expect(hits.contains { $0.text.contains("CARS 87 (BEA) AND 55 (SAI)") }, "\(number)")
        }
        #expect(control.contains { $0.flag == "BLUE" })
    }

    @Test func raceControlByNumberField() {
        let all = Self.control()
        #expect(all[0].cars == ["44"])
        // A numeric RacingNumber works, and an empty one is ignored.
        let e = RaceControlLog.parse(lines: lines(
            #"00:00:01.000{"Messages":[{"Utc":"\#(iso(Self.s))","RacingNumber":16,"Message":"WAVED BLUE FLAG"},{"Utc":"\#(iso(Self.s + 1_000))","RacingNumber":"","Message":"X"}]}"#),
            streamStart: Self.s)
        #expect(e[0].cars == ["16"])
        #expect(e[1].cars.isEmpty)
        // Dropped as duplicates: the same time and words sent again. A different time stays.
        let d = RaceControlLog.parse(lines: lines(
            #"00:00:01.000{"Messages":[{"Utc":"\#(iso(Self.s))","Message":"A"}]}"#,
            #"00:00:02.000{"Messages":{"1":{"Utc":"\#(iso(Self.s))","Message":"A"}}}"#,
            #"00:00:03.000{"Messages":{"2":{"Utc":"\#(iso(Self.s + 5_000))","Message":"A"}}}"#),
            streamStart: Self.s)
        #expect(d.map(\.t) == [Self.s, Self.s + 5_000])
    }

    @Test func stopsWithLaneTimeAndTyres() throws {
        let m = try #require(Logbook.at(Self.s + 130_000, car: "44", session: Self.session(), radio: Self.radio(), raceControl: Self.control()))
        #expect(m.stops == [LogbookStop(lap: 2, laneMs: 25_000, off: "Medium", on: "Hard")])
        #expect(m.number == "44")
        #expect(m.position == 3)
        #expect(m.tyre?.compound == "Hard")
        #expect(m.tyre?.laps == 4)
        #expect(m.lastLap == "1:29.518")
        #expect(m.laps.map(\.lap) == [1])
        #expect(m.ahead == "63")
        #expect(m.behind == nil)
    }

    @Test func stopLapIsNilWhenTheCarsOwnLapIsUnknown() throws {
        // Car 63 never reports a lap count; the leader (1) is on lap 2. The stop must not borrow it.
        let session = RaceFixture.synthetic(
            timing: [
                timingLine("00:00:00.000", [("1", #""Position":"1""#), ("63", #""Position":"2""#)]),
                timingLine("00:00:50.000", [("1", #""NumberOfLaps":1"#)]),
                timingLine("00:01:00.000", [("63", #""InPit":true"#)]),
                timingLine("00:01:25.000", [("63", #""InPit":false,"PitOut":true"#)]),
            ],
            sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#),
            stints: [])
        let m = try #require(Logbook.at(Self.s + 130_000, car: "63", session: session, radio: RadioClips(), raceControl: []))
        #expect(m.stops.count == 1)
        #expect(m.stops[0].lap == nil)
        #expect(m.stops[0].laneMs == 25_000)
    }

    @Test func unknownCompoundIsNotShown() throws {
        let session = RaceFixture.synthetic(
            timing: [timingLine("00:00:00.000", [("44", #""Position":"1""#)]),
                     timingLine("00:01:00.000", [("44", #""InPit":true"#)]),
                     timingLine("00:01:25.000", [("44", #""InPit":false"#)])],
            sessionStatus: lines(#"00:00:10.000{"Status":"Started"}"#),
            stints: [line(#"00:00:00.000{"Lines":{"44":{"Stints":{"0":{"Compound":"UNKNOWN","New":"true","StartLaps":0,"TotalLaps":0}}}}}"#),
                     line(#"00:01:10.000{"Lines":{"44":{"Stints":{"1":{"Compound":"","New":"true","StartLaps":0,"TotalLaps":0}}}}}"#)])
        let m = try #require(Logbook.at(Self.s + 130_000, car: "44", session: session, radio: RadioClips(), raceControl: []))
        #expect(m.tyre == nil)
        #expect(m.stops.first?.off == nil)
        #expect(m.stops.first?.on == nil)
    }

    @Test func stopStillInLaneHasNoTime() throws {
        let m = try #require(Logbook.at(Self.s + 65_000, car: "44", session: Self.session(), radio: Self.radio(), raceControl: Self.control()))
        #expect(m.stops.count == 1)
        #expect(m.stops[0].laneMs == nil)
        #expect(m.stops[0].lap == 2)
        #expect(m.stops[0].off == "Medium")
        #expect(m.stops[0].on == nil)
        #expect(m.position == 2)
        #expect(m.ahead == "1" && m.behind == "63")
        // The new tyres are only named once they are known: at 70 s the HARD set is in.
        let later = try #require(Logbook.at(Self.s + 80_000, car: "44", session: Self.session(), radio: Self.radio(), raceControl: []))
        #expect(later.stops[0].on == "Hard")
        #expect(later.stops[0].laneMs == nil)
    }

    @Test func nothingAfterT() throws {
        let session = Self.session()
        let t = Self.s + 100_000
        let m = try #require(Logbook.at(t, car: "44", session: session, radio: Self.radio(), raceControl: Self.control()))
        #expect(m.radio.map(\.path) == ["TeamRadio/A.mp3"])
        #expect(m.raceControl.map(\.t) == [Self.s + 20_000])
        #expect(m.tyre?.laps == 0)
        #expect(m.stops.first?.laneMs == 25_000)
        // One ms before the end of a stop it is still in the lane.
        let edge = try #require(Logbook.at(Self.s + 84_999, car: "44", session: session, radio: Self.radio(), raceControl: []))
        #expect(edge.stops.first?.laneMs == nil)
        // nil is the whole race.
        let whole = try #require(Logbook.at(nil, car: "44", session: session, radio: Self.radio(), raceControl: Self.control()))
        #expect(whole.radio.count == 2)
        #expect(whole.raceControl.count == 2)
        #expect(Logbook.at(Self.s - 1, car: "44", session: session, radio: Self.radio(), raceControl: Self.control())?.radio.isEmpty == true)
        // Extreme times don't trap.
        #expect(Logbook.at(.min, car: "44", session: session, radio: Self.radio(), raceControl: Self.control()) != nil)
        #expect(Logbook.at(.max, car: "44", session: session, radio: Self.radio(), raceControl: Self.control()) != nil)
    }

    @Test func radioOnlyThisCar() throws {
        let m = try #require(Logbook.at(nil, car: "1", session: Self.session(), radio: Self.radio(), raceControl: Self.control()))
        #expect(m.radio.map(\.path) == ["TeamRadio/B.mp3"])
        #expect(m.stops.isEmpty)
        #expect(m.tyre == nil)
        #expect(m.raceControl.isEmpty)
    }

    @Test func unknownCarGivesNil() {
        #expect(Logbook.at(nil, car: "99", session: Self.session(), radio: Self.radio(), raceControl: Self.control()) == nil)
        #expect(Logbook.at(Self.s, car: "", session: Self.session(), radio: Self.radio(), raceControl: []) == nil)
    }

    @Test func longRaceEverythingIsAtOrBeforeT() throws {
        let session = try RadioRaceTests.longRace()
        let radio = try RadioRaceTests.raceRadio()
        let control = RaceControlLog.parse(lines: try Fixture.lines("sp26-race-long/RaceControlMessages.jsonStream"),
                                           streamStart: session.streamStart)
        #expect(!control.isEmpty)
        let t = RadioRaceTests.started + 1_800_000
        var checked = 0
        for car in session.drivers.keys.sorted() {
            guard let m = Logbook.at(t, car: car, session: session, radio: radio, raceControl: control),
                  let whole = Logbook.at(nil, car: car, session: session, radio: radio, raceControl: control) else { continue }
            checked += 1
            #expect(m.radio.allSatisfy { $0.utc <= t && $0.racingNumber == car })
            #expect(m.raceControl.allSatisfy { $0.t <= t && $0.cars.contains(car) })
            #expect(m.laps.allSatisfy { $0.crossedAt <= t })
            #expect(m.radio.count <= whole.radio.count && m.laps.count <= whole.laps.count)
            #expect(m.stops.count <= whole.stops.count)
        }
        #expect(checked > 0)
    }
}

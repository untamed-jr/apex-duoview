import Testing
import Foundation
import F1TV
@testable import LiveTiming

/// Malformed feed text and extreme query times must give nil or a clamped value, never trap.
@Suite struct F1ValuesTests {
    @Test func durationsParseAndRejectHugeComponents() {
        #expect(F1Values.durationMs("1:21.024") == 81_024)
        #expect(F1Values.durationMs("21.0249") == 21_024)
        #expect(F1Values.durationMs("02:00:00") == 7_200_000)
        #expect(F1Values.durationMs("") == nil)
        #expect(F1Values.durationMs("+5.0") == nil)
        #expect(F1Values.durationMs("99999999999999999.0") == nil)
        #expect(F1Values.durationMs("9999999999:00.0") == nil)
        #expect(F1Values.durationMs("1:9999999999999999999:00") == nil)
    }

    @Test func gmtOffsetsAreBoundedTo18Hours() {
        #expect(F1Values.offsetSeconds("-03:00:00") == -10_800)
        #expect(F1Values.offsetSeconds("+05:30") == 19_800)
        #expect(F1Values.offsetSeconds("18:00:00") == 64_800)
        #expect(F1Values.offsetSeconds("18:00:01") == nil)
        #expect(F1Values.offsetSeconds("02:60:00") == nil)
        #expect(F1Values.offsetSeconds("99999999999999999:00:00") == nil)
        #expect(F1Values.offsetSeconds("-9223372036854775808") == nil)
        #expect(F1Values.offsetSeconds("") == nil)
    }

    @Test func sessionInfoWithAHugeOffsetDoesNotTrap() throws {
        let json = try JSONValue.parse(Data(#"{"Path":"2026/x/","StartDate":"2026-11-08T14:00:00","GmtOffset":"99999999999999999:00:00"}"#.utf8))
        let info = try #require(TimingSessionInfo.parse(json))
        #expect(info.gmtOffsetSeconds == 0)
        #expect(info.start == SignalR.utc("2026-11-08T14:00:00Z"))
    }

    @Test func saturatingArithmetic() {
        #expect(F1Values.add(.max, 1) == .max)
        #expect(F1Values.add(.min, -1) == .min)
        #expect(F1Values.sub(.max, -1) == .max)
        #expect(F1Values.sub(.min, 1) == .min)
        #expect(F1Values.sub(5, 3) == 2)
    }

    @Test func sessionPartOutsideOneToNineIsIgnored() throws {
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"SessionPart":"-9223372036854775808","Lines":{"3":{"Stats":[{"TimeDiffToFastest":"+0.1"}]}}}"#,
            #"00:00:02.000{"SessionPart":10}"#
        ), streamStart: 0)
        #expect(timing.sessionPart(at: 5000) == nil)
        #expect(timing.state(of: "3", at: 5000)?.gapToLeader == "+0.1")
    }

    @Test func extremeTimesDoNotTrap() throws {
        let extremes: [UTCms] = [.min, .min + 1, -1, 0, .max - 1, .max]
        for start in extremes {
            let timing = TimingTimeline.build(lines: lines(
                #"00:00:01.000{"Lines":{"4":{"Position":"1"}}}"#, #"00:00:02.000{"Lines":{"4":{"NumberOfLaps":1}}}"#,
                #"00:00:03.000{"Lines":{"4":{"Sectors":{"2":{"Value":"30.1"}}}}}"#
            ), streamStart: start)
            #expect(timing.updateTimes.count >= 1)
            _ = StintTimeline.build(lines: lines(#"00:00:01.000{"Lines":{"4":{"Stints":[{"Compound":"SOFT"}]}}}"#), streamStart: start)
            let header = HeaderTimeline.build(
                lapCount: lines(#"00:00:01.000{"CurrentLap":1}"#),
                clock: lines(#"00:00:01.000{"Remaining":"999999:00:00","Extrapolating":true}"#, #"00:00:02.000{"Extrapolating":false}"#),
                weather: lines(#"00:00:01.000{"AirTemp":"20"}"#), streamStart: start)
            let flags = TrackFlags.build(
                trackStatus: lines(#"00:00:01.000{"Status":"5"}"#),
                raceControl: lines(#"00:00:01.000{"Messages":[{"Message":"Q3 WILL RESUME AT 17:04"},{"Flag":"RED"}]}"#),
                streamStart: start, gmtOffsetSeconds: 64_800)
            for t in extremes {
                _ = timing.at(t)
                _ = header.at(t)
                _ = flags.at(t)
                _ = CarDataWindow.readout([CarSample(t: 0, rpm: 0, speedKmh: 0, gear: 0, throttle: 0, brake: 0, ch45: 0)], at: t)
            }
        }
        for offset in [Int.min, -64_801, 64_801, Int.max] {
            #expect(TrackFlags.resumption("Q3 WILL RESUME AT 17:04", said: 0, offset: offset) == nil)
        }
        #expect(TrackFlags.resumption("Q3 WILL RESUME AT 17:04", said: .max, offset: 64_800) != nil)
        let car = CarTrack(number: "1", times: [-62_000_000_000_000, 250_000_000_000_000], xs: [0, 1], ys: [0, 1])
        #expect(car.at(.max) == nil)
        #expect(car.at(.min) == nil)
    }
}

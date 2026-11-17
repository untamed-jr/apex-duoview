import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// Numbers no F1 session can hold are dropped where they are read, so nothing downstream
/// (position ± 1, lap + 1, a lap chart's columns, a map point) can overflow or go infinite.
@Suite struct ImplausibleValuesTests {
    static let t0: UTCms = 1_000_000

    @Test func positionsAndLapsOutOfRangeAreDropped() {
        let timing = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"4":{"Position":"7","NumberOfLaps":10},"1":{"Position":"1","NumberOfLaps":10}}}"#,
            // Out of range: the position isn't known, and the lap count is no crossing.
            #"00:00:02.000{"Lines":{"4":{"Position":"9223372036854775807","NumberOfLaps":"9223372036854775807"}}}"#,
            #"00:00:03.000{"Lines":{"1":{"Position":"0","NumberOfLaps":1000}}}"#,
            // Back in range: a real crossing.
            #"00:00:04.000{"Lines":{"4":{"Position":"6","NumberOfLaps":11}}}"#
        ), streamStart: Self.t0)
        let odd = timing.state(of: "4", at: Self.t0 + 2_000)
        #expect(odd?.position == nil)
        #expect(odd?.numberOfLaps == nil)
        #expect(odd?.lineCrossedAt == nil)
        #expect(timing.state(of: "1", at: Self.t0 + 3_000)?.position == nil)
        #expect(timing.state(of: "1", at: Self.t0 + 3_000)?.numberOfLaps == nil)
        #expect(timing.state(of: "1", at: Self.t0 + 3_000)?.lineCrossedAt == nil)
        #expect(timing.completedLaps(of: "1", upTo: .max).isEmpty)
        let back = timing.state(of: "4", at: Self.t0 + 4_000)
        #expect(back?.position == 6)
        #expect(back?.numberOfLaps == 11)
        #expect(back?.lineCrossedAt == Self.t0 + 4_000)
        #expect(timing.completedLaps(of: "4", upTo: .max).map(\.lap) == [11])
        // Edges: 1 and 99, 0 and 999 are kept.
        let edges = TimingTimeline.build(lines: lines(
            #"00:00:01.000{"Lines":{"4":{"Position":"99","NumberOfLaps":0},"1":{"Position":1,"NumberOfLaps":999}}}"#
        ), streamStart: Self.t0)
        #expect(edges.state(of: "4", at: Self.t0 + 1_000)?.position == 99)
        #expect(edges.state(of: "4", at: Self.t0 + 1_000)?.numberOfLaps == 0)
        #expect(edges.state(of: "1", at: Self.t0 + 1_000)?.position == 1)
        #expect(edges.state(of: "1", at: Self.t0 + 1_000)?.numberOfLaps == 999)
    }

    @Test func lapCountOutOfRangeIsIgnored() {
        let header = HeaderTimeline.build(lapCount: lines(
            #"00:00:01.000{"CurrentLap":1,"TotalLaps":71}"#,
            #"00:00:02.000{"CurrentLap":"9223372036854775807","TotalLaps":100000}"#,
            #"00:00:03.000{"CurrentLap":-1}"#,
            #"00:00:04.000{"CurrentLap":2}"#
        ), clock: [], weather: [], streamStart: Self.t0)
        #expect(header.at(Self.t0 + 2_000).lap == 1)
        #expect(header.at(Self.t0 + 2_000).totalLaps == 71)
        #expect(header.at(Self.t0 + 3_000).lap == 1)
        #expect(header.at(Self.t0 + 4_000).lap == 2)
    }

    @Test func lapChartStaysSmallWithAHugeLapCount() {
        let session = RaceFixture.synthetic(timing: [
            timingLine("00:00:00.000", [("1", #""Position":"1""#)]),
            timingLine("00:00:10.000", [("1", #""NumberOfLaps":1"#)]),
            timingLine("00:01:40.000", [("1", #""NumberOfLaps":5000"#)]),
        ], start: Self.t0)
        let rows = LapChart.rows(until: nil, session: session)
        #expect(rows.first?.positions.count == 1)
    }

    @Test func weatherOutOfRangeIsUnknown() {
        let header = HeaderTimeline.build(lapCount: [], clock: [], weather: lines(
            #"00:00:01.000{"AirTemp":"20.1","TrackTemp":"29.0","Rainfall":"0"}"#,
            #"00:00:02.000{"AirTemp":"nan","TrackTemp":"1e300"}"#,
            #"00:00:03.000{"AirTemp":"-60","TrackTemp":"inf"}"#,
            #"00:00:04.000{"AirTemp":"-50","TrackTemp":"100"}"#,
            #"00:00:05.000{"AirTemp":21.5,"Rainfall":"nan"}"#
        ), streamStart: Self.t0)
        #expect(header.at(Self.t0 + 1_000).airTemp == 20.1)
        #expect(header.at(Self.t0 + 2_000).airTemp == nil)
        #expect(header.at(Self.t0 + 2_000).trackTemp == nil)
        #expect(header.at(Self.t0 + 3_000).airTemp == nil)
        #expect(header.at(Self.t0 + 3_000).trackTemp == nil)
        #expect(header.at(Self.t0 + 4_000).airTemp == -50)
        #expect(header.at(Self.t0 + 4_000).trackTemp == 100)
        #expect(header.at(Self.t0 + 5_000).airTemp == 21.5)
        #expect(header.at(Self.t0 + 5_000).raining == false)
    }

    @Test func carPositionsFarOffTheMapAreDropped() throws {
        let t0 = PositionsTests.t0
        func sample(_ t: UTCms, _ x: String, _ y: String, _ z: String) -> String {
            PositionsTests.sample(t, #""1":{"Status":"OnTrack","X":\#(x),"Y":\#(y),"Z":\#(z)}"#)
        }
        // 1e7 (a kilometre in tenths of a metre, a hundred times any circuit) is the edge;
        // past it a sample would narrow to an infinite Float and NaN the map.
        let payload = #"{"Position":[\#(sample(t0, "10", "20", "0")),\#(sample(t0 + 100, "1e39", "20", "0")),\#(sample(t0 + 200, "10", "-1e8", "0")),\#(sample(t0 + 300, "10", "20", "1e300")),\#(sample(t0 + 400, "10000000", "-10000000", "10000000"))]}"#
        let car = try #require(PositionSeries.parse(lines: [zLine(0, payload)]).cars["1"])
        #expect(car.times == [t0, t0 + 400])
        #expect(car.point(1) == TrackPoint(x: 10_000_000, y: -10_000_000))
        #expect(car.at(t0 + 200).map { $0.x.isFinite && $0.y.isFinite } == true)
    }
}

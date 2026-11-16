import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct PositionsTests {
    static let t0: UTCms = 1_794_157_400_000

    static func sample(_ t: UTCms, _ entries: String) -> String {
        #"{"Timestamp":"\#(iso(t))","Entries":{\#(entries)}}"#
    }

    @Test func positionsInterpolateBetweenSamples() throws {
        let series = PositionSeries.parse(lines: try Fixture.lines("sp26-race/Position.z.jsonStream"))
        #expect(series.cars.count == 22)  // check:raceWindowCars
        let car = try #require(series.cars["44"])
        #expect(car.number == "44")
        // check:car44FirstLast
        #expect(car.first == 1_794_157_281_518)
        #expect(car.last == 1_794_158_121_578)
        // check:car44PairAroundLightsOutPlus1min: (…464278, −2354, −1528) then (…464398, −2376, −1496)
        #expect(car.at(1_794_157_464_278) == TrackPoint(x: -2354, y: -1528))
        #expect(car.at(1_794_157_464_398) == TrackPoint(x: -2376, y: -1496))
        #expect(car.at(1_794_157_464_338) == TrackPoint(x: -2365, y: -1512))
        // Outside the data: nothing, except that the map keeps a car waiting where first seen.
        #expect(car.at(1_794_157_281_517) == nil)
        #expect(car.at(1_794_158_121_579) == nil)
        #expect(car.atOrFirst(1_794_157_000_000) == car.point(0))
        #expect(car.atOrFirst(1_794_158_121_579) == nil)
    }

    @Test func positionsNilAcrossFiveSecondGap() throws {
        let t0 = Self.t0
        let stream = [0, 1000, 7000, 8000, 13_000].enumerated().map { i, dt in
            zLine(Int64(i) * 1000, #"{"Position":[\#(Self.sample(t0 + Int64(dt), #""44":{"Status":"OnTrack","X":\#(dt),"Y":0,"Z":0}"#))]}"#)
        }
        let car = try #require(PositionSeries.parse(lines: stream).cars["44"])
        #expect(car.at(t0 + 500) == TrackPoint(x: 500, y: 0))
        #expect(car.at(t0 + 4000) == nil)          // 6 s between samples
        #expect(car.at(t0 + 7000) == TrackPoint(x: 7000, y: 0))
        #expect(car.at(t0 + 7500) == TrackPoint(x: 7500, y: 0))
        #expect(car.at(t0 + 10_500) == TrackPoint(x: 10_500, y: 0))  // exactly 5 s still joins
    }

    @Test func offTrackEntriesSkipped() throws {
        // The São Paulo windows have none (check:raceWindowOffTrackEntries = 0), so this is synthetic.
        let t0 = Self.t0
        let payload = #"{"Position":[\#(Self.sample(t0, #""1":{"Status":"OnTrack","X":10,"Y":20,"Z":0},"99":{"Status":"OffTrack","X":5,"Y":5,"Z":0}"#)),\#(Self.sample(t0 + 220, #""1":{"Status":"OffTrack","X":0,"Y":0,"Z":0},"99":{"Status":"OffTrack","X":5,"Y":5,"Z":0}"#)),\#(Self.sample(t0 + 440, #""1":{"Status":"OnTrack","X":30,"Y":40,"Z":0}"#))]}"#
        let series = PositionSeries.parse(lines: [zLine(0, payload)])
        #expect(series.cars.keys.sorted() == ["1"])
        let car = try #require(series.cars["1"])
        #expect(car.times == [t0, t0 + 440])
        #expect(car.at(t0 + 220) == TrackPoint(x: 20, y: 30))
    }

    @Test func timesComeFromEachSampleNotTheLine() throws {
        let t0 = Self.t0
        // Both lines at offset 0, one sample repeated and one out of order: kept increasing.
        let a = zLine(0, #"{"Position":[\#(Self.sample(t0 + 200, #""5":{"Status":"OnTrack","X":2,"Y":2,"Z":0}"#))]}"#)
        let b = zLine(0, #"{"Position":[\#(Self.sample(t0 + 100, #""5":{"Status":"OnTrack","X":1,"Y":1,"Z":0}"#)),\#(Self.sample(t0 + 200, #""5":{"Status":"OnTrack","X":9,"Y":9,"Z":0}"#)),\#(Self.sample(t0 + 300, #""5":{"Status":"OnTrack","X":3,"Y":3,"Z":0}"#))]}"#)
        let bad = StreamLine(offsetMs: 0, json: .string("not base64 deflate"))
        let car = try #require(PositionSeries.parse(lines: [a, bad, b]).cars["5"])
        #expect(car.times == [t0 + 200, t0 + 300])
        #expect(car.at(t0 + 200) == TrackPoint(x: 2, y: 2))
    }
}

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

    /// The map skips (0,0) samples: before the first real one the car isn't placed, and a
    /// stray (0,0) mid-lap is passed over, not drawn as a trip to the origin.
    @Test func mapPointSkipsOriginSamples() throws {
        let t0 = Self.t0
        let xs = [0, 0, 1000, 2000, 0, 4000, 5000]
        let stream = xs.enumerated().map { i, x in
            zLine(Int64(i) * 1000, #"{"Position":[\#(Self.sample(t0 + Int64(i) * 1000, #""44":{"Status":"OnTrack","X":\#(x),"Y":\#(x == 0 ? 0 : 7),"Z":0}"#))]}"#)
        }
        let car = try #require(PositionSeries.parse(lines: stream).cars["44"])
        #expect(car.at(t0) == TrackPoint(x: 0, y: 0))        // `at` keeps them, as Android
        #expect(car.mapPoint(at: t0) == nil)
        #expect(car.mapPoint(at: t0 + 1500) == nil)          // only (0,0) at or before
        #expect(car.mapPoint(at: t0 + 2000) == TrackPoint(x: 1000, y: 7))
        #expect(car.mapPoint(at: t0 + 2500) == TrackPoint(x: 1500, y: 7))
        // Across the (0,0) at 4 s: from 2000 at 3 s to 4000 at 5 s.
        #expect(car.mapPoint(at: t0 + 4000) == TrackPoint(x: 3000, y: 7))
        #expect(car.mapPoint(at: t0 + 3500) == TrackPoint(x: 2500, y: 7))
        #expect(car.mapPoint(at: t0 + 6000) == TrackPoint(x: 5000, y: 7))
        #expect(car.mapPoint(at: t0 + 6001) == nil)          // after the last
        #expect(car.mapPoint(at: t0 - 1) == nil)
    }

    @Test func mapPointKeepsTheFiveSecondGap() throws {
        let t0 = Self.t0
        let samples: [(Int64, Int)] = [(0, 100), (1000, 0), (5500, 0), (6000, 600)]
        let stream = samples.enumerated().map { i, sample in
            zLine(Int64(i) * 1000, #"{"Position":[\#(Self.sample(t0 + sample.0, #""44":{"Status":"OnTrack","X":\#(sample.1),"Y":0,"Z":0}"#))]}"#)
        }
        let car = try #require(PositionSeries.parse(lines: stream).cars["44"])
        // The real samples either side are 6 s apart once the (0,0)s are passed over.
        #expect(car.mapPoint(at: t0 + 3000) == nil)
        #expect(car.mapPoint(at: t0) == TrackPoint(x: 100, y: 0))
        #expect(car.mapPoint(at: t0 + 6000) == TrackPoint(x: 600, y: 0))
    }

    /// On the race fixture: every car's first samples are at the origin; the map never draws one there.
    @Test func mapPointNeverAtTheOriginOnTheRace() throws {
        let series = PositionSeries.parse(lines: try Fixture.lines("sp26-race/Position.z.jsonStream"))
        var placed = 0
        for car in series.cars.values {
            guard let first = car.first, let last = car.last else { continue }
            for t in stride(from: first, through: last, by: 997) {
                guard let p = car.mapPoint(at: t) else { continue }
                placed += 1
                #expect(!(p.x == 0 && p.y == 0))
            }
        }
        #expect(placed > 10_000)
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

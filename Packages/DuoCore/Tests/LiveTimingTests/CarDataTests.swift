import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct CarDataTests {
    static func slice() throws -> [String: [CarSample]] {
        CarDataWindow.parse(lines: try Fixture.lines("sp26-quali/CarData.z.slice.jsonStream"))
    }

    @Test func carDataParsesChannels() throws {
        let cars = try Self.slice()
        #expect(cars.count == 22)  // check:carDataCars
        let car = try #require(cars["16"])
        #expect(car.count == 584)  // check:carData16Count
        // check:carData16First
        #expect(car.first == CarSample(t: 1_794_074_399_370, rpm: 3523, speedKmh: 0, gear: 0, throttle: 0, brake: 0))
        // check:carData16FirstMoving: {"0": 3227, "2": 3, "3": 1, "4": 0, "5": 0}
        #expect(car.first { $0.t == 1_794_074_417_251 } == CarSample(t: 1_794_074_417_251, rpm: 3227, speedKmh: 3, gear: 1, throttle: 0, brake: 0))
        // check:carData16Last
        #expect(car.last == CarSample(t: 1_794_074_553_890, rpm: 8016, speedKmh: 91, gear: 2, throttle: 27, brake: 0))
        #expect(zip(car, car.dropFirst()).allSatisfy { $0.t < $1.t })
        // check:carDataChannel45Present = 0: São Paulo 2026 sends no channel 45, so it is absent
        // (nil), never read as 0.
        #expect(cars.values.joined().allSatisfy { $0.ch45 == nil })
    }

    @Test func carDataTruncatedLastLineDropped() throws {
        // The slice ends mid-line, as a byte range does (check:carDataLastLineEndsWithoutNewline);
        // check:carDataCompleteLines = 153.
        let lines = try Fixture.lines("sp26-quali/CarData.z.slice.jsonStream")
        #expect(lines.count == 153)
        // A line whose JSON is whole but whose payload is cut short is skipped too.
        guard case .string(let payload) = lines[0].json else { Issue.record("not a .z line"); return }
        let cut = StreamLine(offsetMs: lines[0].offsetMs, json: .string(String(payload.prefix(payload.count / 2))))
        let whole = CarDataWindow.parse(lines: Array(lines.dropFirst()))
        #expect(CarDataWindow.parse(lines: [cut] + lines.dropFirst()) == whole)
    }

    @Test func carDataReadoutStaleAfter5s() throws {
        let t0: UTCms = 1_794_074_400_000
        let samples = [0, 300, 600].map { CarSample(t: t0 + Int64($0), rpm: 10_000, speedKmh: 200 + $0, gear: 7, throttle: 100, brake: 0) }
        #expect(CarDataWindow.readout(samples, at: t0 - 1) == nil)
        #expect(CarDataWindow.readout([], at: t0) == nil)
        let mid = try #require(CarDataWindow.readout(samples, at: t0 + 450))
        #expect(mid.sample.speedKmh == 500)
        #expect(!mid.stale)
        let edge = try #require(CarDataWindow.readout(samples, at: t0 + 5600))
        #expect(edge.sample.speedKmh == 800)
        #expect(!edge.stale)
        #expect(CarDataWindow.readout(samples, at: t0 + 5601)?.stale == true)
    }

    @Test func liveShapedMessageParses() throws {
        let t0: UTCms = 1_794_074_400_000
        let json = #"{"Entries":[{"Utc":"\#(iso(t0))","Cars":{"1":{"Channels":{"0":11000,"2":301,"3":8,"4":100,"5":0,"45":12}},"4":{"Channels":{}}}}]}"#
        let cars = CarDataWindow.parse(lines: [zLine(0, json)])
        #expect(cars["1"] == [CarSample(t: t0, rpm: 11000, speedKmh: 301, gear: 8, throttle: 100, brake: 0, ch45: 12)])
        // A car with no channels has every channel absent, not 0 (no "0 km/h" readout).
        #expect(cars["4"] == [CarSample(t: t0)])
        #expect(cars["4"]?.first?.speedKmh == nil)
    }
}

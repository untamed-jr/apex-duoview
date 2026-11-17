import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct ReadoutsTests {
    @Test func readoutStale() {
        let t0: UTCms = 1_794_074_400_000
        let samples = [
            CarSample(t: t0, rpm: 11_000, speedKmh: 287, gear: 7, throttle: 104, brake: 0, ch45: 0),
            CarSample(t: t0 + 300, rpm: 10_500, speedKmh: 250, gear: 6, throttle: 0, brake: 104, ch45: 0),
        ]
        #expect(Readouts.at(t0 - 1, samples: samples, channel45: .absent) == nil)
        // Throttle and brake are bars: F1's 104 reads as 100.
        #expect(Readouts.at(t0 + 299, samples: samples, channel45: .absent)
                == Readout(speedKmh: 287, gear: 7, rpm: 11_000, throttle: 100, brake: 0, aero: nil, stale: false))
        // The data pauses: the last values hold, then grey once more than 5 s old.
        let held = Readout(speedKmh: 250, gear: 6, rpm: 10_500, throttle: 0, brake: 100, aero: nil, stale: false)
        #expect(Readouts.at(t0 + 300 + 5_000, samples: samples, channel45: .absent) == held)
        var grey = held
        grey.stale = true
        #expect(Readouts.at(t0 + 300 + 5_001, samples: samples, channel45: .absent) == grey)
        #expect(Readouts.at(t0 + 3_600_000, samples: samples, channel45: .absent) == grey)
        #expect(Readouts.at(t0, samples: [], channel45: .absent) == nil)
    }

    @Test func readoutLightFollowsChannel45Meaning() {
        let t0: UTCms = 1_000_000
        func light(_ value: Int, _ meaning: Channel45Meaning) -> Bool? {
            Readouts.at(t0, samples: [CarSample(t: t0, rpm: 0, speedKmh: 0, gear: 0, throttle: 0, brake: 0, ch45: value)],
                        channel45: meaning)?.aero
        }
        // DRS: 10, 12 and 14 are open; 8 (eligible) and 0 are not.
        #expect([0, 8, 10, 12, 14].map { light($0, .drs) } == [false, false, true, true, true])
        #expect(light(0, .activeAero) == false)
        #expect(light(3, .activeAero) == true)
        #expect(light(12, .absent) == nil)
        // A channel left out of the sample is absent: no light, and no value, never 0.
        let bare = Readouts.at(t0, samples: [CarSample(t: t0, speedKmh: 250)], channel45: .drs)
        #expect(bare == Readout(speedKmh: 250, gear: nil, rpm: nil, throttle: nil, brake: nil, aero: nil, stale: false))
        #expect(Channel45Meaning.drs.label == "DRS")
        #expect(Channel45Meaning.activeAero.label == "Aero")
        #expect(Channel45Meaning.absent.label == nil)
    }

    @Test func channel45MeaningFromFixture() throws {
        // São Paulo 2026 qualifying, Q1's first 2.5 minutes of CarData. spike/race_checks.py:
        // check:carDataSamples = 12848 samples, check:carDataSamplesWithChannel45 = 0 carry a "45"
        // key at all, including check:carDataStraightSamplesWithChannel45 = 0 of the
        // check:carDataSamplesOnStraight = 9 taken at 150 km/h or more with the throttle at 95 % or
        // more. The channel neither changes on a straight nor holds a constant: it isn't there. So
        // 2026's channel 45 is `.absent` (no light), never "off".
        let lines = try Fixture.lines("sp26-quali/CarData.z.slice.jsonStream")
        var samples = 0
        var with45 = 0
        for line in lines {
            guard let object = F1Values.zObject(line), let entries = object["Entries"] as? [Any] else { continue }
            for case let entry as [String: Any] in entries {
                for case let car as [String: Any] in ((entry["Cars"] as? [String: Any]) ?? [:]).values {
                    guard let channels = car["Channels"] as? [String: Any] else { continue }
                    samples += 1
                    if channels["45"] != nil { with45 += 1 }
                }
            }
        }
        #expect(samples == 12_848)
        #expect(with45 == 0)

        let cars = CarDataWindow.parse(lines: lines)
        #expect(Channel45Meaning.of(year: 2026, samples: cars) == .absent)
        #expect(Channel45Meaning.of(year: nil, samples: cars) == .absent)
        #expect(Channel45Meaning.of(year: 2025, samples: cars) == .drs)
        // A channel that moves is 2026's active aero; one sent but never changing is absent.
        var steady = cars
        steady["11", default: []] += [CarSample(t: .max - 1, ch45: 1), CarSample(t: .max, ch45: 1)]
        #expect(Channel45Meaning.of(year: 2026, samples: steady) == .absent)
        var moving = cars
        moving["11", default: []] += [CarSample(t: .max - 1, ch45: 0), CarSample(t: .max, ch45: 1)]
        #expect(Channel45Meaning.of(year: 2026, samples: moving) == .activeAero)

        // check:carDataFastestSample = ('11', 1794074504771, {'0': 11541, '2': 219, '3': 5, '4': 77, '5': 100})
        let car11 = try #require(cars["11"])
        let fastest = try #require(Readouts.at(1_794_074_504_771, samples: car11, channel45: .absent))
        #expect(fastest == Readout(speedKmh: 219, gear: 5, rpm: 11_541, throttle: 77, brake: 100, aero: nil, stale: false))
    }
}

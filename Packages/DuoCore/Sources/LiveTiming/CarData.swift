import Foundation
import F1TV

/// One car's telemetry at one moment, from CarData.z. Channels: 0 rpm, 2 speed (km/h),
/// 3 gear, 4 throttle (%), 5 brake, 45 DRS on older cars. A channel F1 leaves out is nil
/// (absent), never 0: the São Paulo 2026 data has no channel 45 at all, and a readout must not
/// show a missing speed as standing still.
public struct CarSample: Sendable, Equatable {
    public var t: UTCms
    public var rpm: Int?
    public var speedKmh: Int?
    public var gear: Int?
    public var throttle: Int?
    public var brake: Int?
    public var ch45: Int?

    public init(t: UTCms, rpm: Int? = nil, speedKmh: Int? = nil, gear: Int? = nil, throttle: Int? = nil,
                brake: Int? = nil, ch45: Int? = nil) {
        self.t = t
        self.rpm = rpm
        self.speedKmh = speedKmh
        self.gear = gear
        self.throttle = throttle
        self.brake = brake
        self.ch45 = ch45
    }
}

/// Reads a stretch of CarData.z, such as one byte range of the archive's file.
public enum CarDataWindow {
    /// A readout older than this is stale.
    public static let staleMs: Int64 = 5_000

    /// Each car's samples, oldest first, at each entry's own Utc. Lines that don't decode (the
    /// cut-off last line of a byte range) are skipped; a sample not later than the car's last
    /// is dropped.
    public static func parse(lines: [StreamLine]) -> [String: [CarSample]] {
        var cars: [String: [CarSample]] = [:]
        for line in lines {
            guard let object = F1Values.zObject(line), let entries = object["Entries"] as? [Any] else { continue }
            for case let entry as [String: Any] in entries {
                guard let stamp = entry["Utc"] as? String, let t = F1Values.utc(stamp),
                      let list = entry["Cars"] as? [String: Any] else { continue }
                for (number, value) in list {
                    guard let channels = (value as? [String: Any])?["Channels"] as? [String: Any] else { continue }
                    if let last = cars[number]?.last, t <= last.t { continue }
                    func channel(_ key: String) -> Int? { F1Values.int(channels[key]) }
                    cars[number, default: []].append(CarSample(
                        t: t, rpm: channel("0"), speedKmh: channel("2"), gear: channel("3"),
                        throttle: channel("4"), brake: channel("5"), ch45: channel("45")))
                }
            }
        }
        return cars
    }

    /// The latest sample at or before `t`; nil before the first. Stale when that sample is more
    /// than 5 s before `t` (the data has stopped coming, or not reached `t` yet).
    public static func readout(_ samples: [CarSample], at t: UTCms) -> (sample: CarSample, stale: Bool)? {
        var lo = 0, hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return nil }
        let sample = samples[lo - 1]
        return (sample, F1Values.sub(t, sample.t) > staleMs)
    }
}

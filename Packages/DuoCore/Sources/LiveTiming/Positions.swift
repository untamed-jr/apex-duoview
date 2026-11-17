import Foundation
import F1TV

/// A point in archive coordinates (1/10 m), as Position and the circuit outline give them.
public struct TrackPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One car's positions over a session, as parallel sorted arrays (no per-sample objects).
public struct CarTrack: Sendable {
    /// A car with no data for longer than this is hidden until data returns.
    public static let maxGapMs: Int64 = 5_000

    public let number: String
    /// Sample times, strictly increasing.
    public let times: [UTCms]
    private let xs: [Float]
    private let ys: [Float]

    init(number: String, times: [UTCms], xs: [Float], ys: [Float]) {
        self.number = number
        self.times = times
        self.xs = xs
        self.ys = ys
    }

    public var first: UTCms? { times.first }
    public var last: UTCms? { times.last }

    /// The sample at `index` into `times`.
    public func point(_ index: Int) -> TrackPoint {
        TrackPoint(x: Double(xs[index]), y: Double(ys[index]))
    }

    /// Interpolated between the samples either side of `t`. Nil before the first sample, after
    /// the last, and between two samples more than 5 s apart.
    public func at(_ t: UTCms) -> TrackPoint? {
        guard let lo = F1Values.lastIndex(in: times, atOrBefore: t) else { return nil }
        if times[lo] == t { return point(lo) }
        let hi = lo + 1
        guard hi < times.count else { return nil }
        let span = times[hi] - times[lo]
        guard span <= Self.maxGapMs else { return nil }
        let f = Double(F1Values.sub(t, times[lo])) / Double(span)
        let a = point(lo), b = point(hi)
        return TrackPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// As `at`, but a car not heard from yet waits where it was first seen (for the map).
    public func atOrFirst(_ t: UTCms) -> TrackPoint? {
        if let first = times.first, t < first { return point(0) }
        return at(t)
    }

    /// Where the map draws the car at `t`: as `at`, but a (0,0) sample doesn't count (F1's first
    /// samples put every car at the origin), so the car is interpolated between the real samples
    /// either side of `t`. Nil before the first real sample at or before `t` (nothing later than
    /// `t` is used to place it), after the last, and when those samples are more than 5 s apart.
    public func mapPoint(at t: UTCms) -> TrackPoint? {
        guard let found = F1Values.lastIndex(in: times, atOrBefore: t) else { return nil }
        var lo = found
        while lo >= 0, isOrigin(lo) { lo -= 1 }
        guard lo >= 0 else { return nil }
        if times[lo] == t { return point(lo) }
        var hi = found + 1
        while hi < times.count, isOrigin(hi) { hi += 1 }
        guard hi < times.count else { return nil }
        let span = F1Values.sub(times[hi], times[lo])
        guard span <= Self.maxGapMs else { return nil }
        let f = Double(F1Values.sub(t, times[lo])) / Double(span)
        let a = point(lo), b = point(hi)
        return TrackPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    private func isOrigin(_ index: Int) -> Bool {
        xs[index] == 0 && ys[index] == 0
    }
}

/// Every car's positions from the Position.z topic.
public struct PositionSeries: Sendable {
    public let cars: [String: CarTrack]

    public init(cars: [String: CarTrack]) {
        self.cars = cars
    }

    /// Decodes each `.z` line and takes each sample at its own `Timestamp` (UTC), not the line's
    /// offset. `OffTrack` entries are skipped; a sample not later than the car's last is dropped
    /// (they can repeat or arrive slightly out of order). Undecodable lines are skipped.
    public static func parse(lines: [StreamLine]) -> PositionSeries {
        var builder = Builder()
        for line in lines { builder.add(line) }
        return builder.series
    }

    /// The latest sample time in each of a Position stream's lines, less that line's offset:
    /// the stream start the cars' own clocks imply (a touch early, as lines go out after their
    /// samples).
    static func impliedStreamStarts(_ lines: [StreamLine], limit: Int) -> [UTCms] {
        var out: [UTCms] = []
        for line in lines where out.count < limit {
            guard let object = F1Values.zObject(line), let samples = object["Position"] as? [Any] else { continue }
            let stamps = samples.compactMap { ($0 as? [String: Any])?["Timestamp"] as? String }
            if let latest = stamps.compactMap(F1Values.utc).max() { out.append(latest - line.offsetMs) }
        }
        return out
    }

    /// `parse`, a line at a time: the live feed keeps one and adds only the lines that came
    /// since it last asked.
    struct Builder: LineFolder {
        /// The largest X, Y or Z kept, in 1/10 m.
        static let maxCoordinate = 1e7
        private var cars: [String: Samples] = [:]

        init() {}

        init(streamStart: UTCms) {}

        /// One `.z` line's samples (as `parse`).
        mutating func add(_ line: StreamLine) {
            guard let object = F1Values.zObject(line), let samples = object["Position"] as? [Any] else { return }
            for case let sample as [String: Any] in samples {
                guard let stamp = sample["Timestamp"] as? String, let t = F1Values.utc(stamp),
                      let entries = sample["Entries"] as? [String: Any] else { continue }
                for (number, value) in entries {
                    guard let e = value as? [String: Any], (e["Status"] as? String) != "OffTrack",
                          let x = F1Values.number(e["X"]), let y = F1Values.number(e["Y"]),
                          // Past a kilometre from the origin (a hundred times any circuit) it's
                          // no position, and would narrow to an infinite Float.
                          abs(x) <= Self.maxCoordinate, abs(y) <= Self.maxCoordinate,
                          F1Values.number(e["Z"]).map({ abs($0) <= Self.maxCoordinate }) ?? true
                    else { continue }
                    cars[number, default: Samples()].add(t, Float(x), Float(y))
                }
            }
        }

        /// The cars so far.
        var series: PositionSeries {
            var out: [String: CarTrack] = [:]
            for (number, b) in cars {
                out[number] = CarTrack(number: number, times: b.times, xs: b.xs, ys: b.ys)
            }
            return PositionSeries(cars: out)
        }
    }

    private struct Samples {
        var times: [UTCms] = []
        var xs: [Float] = []
        var ys: [Float] = []

        mutating func add(_ t: UTCms, _ x: Float, _ y: Float) {
            if let last = times.last, t <= last { return }
            times.append(t)
            xs.append(x)
            ys.append(y)
        }
    }
}

import Foundation
#if canImport(CoreGraphics)
// On Apple platforms CGPoint and CGSize live in CoreGraphics; on Linux Foundation defines them.
import CoreGraphics
#endif

/// Archive coordinates onto a box: turned, scaled to fit, centred, with y flipped (the archive's
/// y points up, the screen's down). Made by `TrackGeometry.fit`.
public struct MapTransform: Sendable {
    private let cosA: Double
    private let sinA: Double
    private let scale: Double
    private let left: Double
    private let top: Double
    private let minX: Double
    private let maxY: Double

    fileprivate init(cosA: Double, sinA: Double, scale: Double, left: Double, top: Double, minX: Double, maxY: Double) {
        self.cosA = cosA
        self.sinA = sinA
        self.scale = scale
        self.left = left
        self.top = top
        self.minX = minX
        self.maxY = maxY
    }

    public func point(_ p: TrackPoint) -> CGPoint {
        let rx = p.x * cosA - p.y * sinA
        let ry = p.x * sinA + p.y * cosA
        return CGPoint(x: left + (rx - minX) * scale, y: top + (maxY - ry) * scale)
    }
}

/// The circuit as a closed loop, with distance along it.
public struct TrackGeometry: Sendable {
    public let outline: [TrackPoint]
    /// Distance from the first point to each point; `length` closes the loop back to it.
    private let along: [Double]
    public let length: Double

    /// True when the lap runs counter-clockwise as the track map draws it (Android's meaning). The
    /// map keeps the archive's y-up orientation (`MapTransform` turns it and flips y into screen
    /// coordinates, so up stays up), so the sign of the outline's area decides.
    public let counterClockwise: Bool

    public init(outline: [TrackPoint]) {
        self.outline = outline
        let n = outline.count
        var along = [Double](repeating: 0, count: n)
        for i in 1..<max(n, 1) { along[i] = along[i - 1] + Self.dist(outline[i - 1], outline[i]) }
        self.along = along
        length = n > 1 ? along[n - 1] + Self.dist(outline[n - 1], outline[0]) : 0
        var area = 0.0
        for i in 0..<n {
            let a = outline[i], b = outline[(i + 1) % n]
            area += a.x * b.y - b.x * a.y
        }
        counterClockwise = area > 0
    }

    private static func dist(_ a: TrackPoint, _ b: TrackPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    /// Index of the outline point nearest `p`.
    public func nearestIndex(to p: TrackPoint) -> Int {
        var best = 0
        var bestD = Double.infinity
        for (i, q) in outline.enumerated() {
            let d = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// How far round the lap `p` is, 0..<1 from the outline's first point: projected onto the
    /// nearest segment, so it moves smoothly between outline points.
    public func progress(of p: TrackPoint) -> Double {
        let n = outline.count
        guard n >= 2, length > 0 else { return 0 }
        let i = nearestIndex(to: p)
        var best = along[i]
        var bestD = Double.infinity
        // The segments either side of the nearest point: into it, then out of it. (No array:
        // this runs for every car on every frame.)
        for side in 0..<2 {
            let j = side == 0 ? (i - 1 + n) % n : i
            let k = (j + 1) % n
            let a = outline[j], b = outline[k]
            let vx = b.x - a.x, vy = b.y - a.y
            let len2 = vx * vx + vy * vy
            let t = len2 == 0 ? 0 : min(max(((p.x - a.x) * vx + (p.y - a.y) * vy) / len2, 0), 1)
            let px = a.x + vx * t, py = a.y + vy * t
            let d = (px - p.x) * (px - p.x) + (py - p.y) * (py - p.y)
            if d < bestD {
                bestD = d
                best = along[j] + hypot(vx, vy) * t
            }
        }
        let f = (best / length).truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }

    /// The transform for a `size` box with `inset` kept clear all round. The outline is turned to
    /// whichever whole degree (0..<180) lets it fill the box most, then, if `userTurnDegrees` is
    /// not 0, turned that much further and fitted again. y is flipped.
    public func fit(in size: CGSize, inset: CGFloat, userTurnDegrees: Double) -> MapTransform {
        let w = max(Double(size.width) - 2 * Double(inset), 0)
        let h = max(Double(size.height) - 2 * Double(inset), 0)
        var best = fitted(degrees: 0, w: w, h: h, inset: Double(inset))
        var bestDegrees = 0.0
        for d in 1..<180 {
            let candidate = fitted(degrees: Double(d), w: w, h: h, inset: Double(inset))
            if candidate.scale > best.scale { best = candidate; bestDegrees = Double(d) }
        }
        return userTurnDegrees == 0 ? best.transform
            : fitted(degrees: bestDegrees + userTurnDegrees, w: w, h: h, inset: Double(inset)).transform
    }

    private func fitted(degrees: Double, w: Double, h: Double, inset: Double) -> (transform: MapTransform, scale: Double) {
        let a = degrees * .pi / 180
        let c = cos(a), s = sin(a)
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for p in outline {
            let rx = p.x * c - p.y * s, ry = p.x * s + p.y * c
            minX = min(minX, rx); maxX = max(maxX, rx)
            minY = min(minY, ry); maxY = max(maxY, ry)
        }
        if outline.isEmpty { minX = 0; maxX = 0; minY = 0; maxY = 0 }
        var scale = min(w / (maxX - minX), h / (maxY - minY))
        if !scale.isFinite { scale = 1 }
        let t = MapTransform(
            cosA: c, sinA: s, scale: scale,
            left: inset + (w - (maxX - minX) * scale) / 2,
            top: inset + (h - (maxY - minY) * scale) / 2,
            minX: minX, maxY: maxY)
        return (t, scale)
    }
}

/// Finds the circuit's shape from cars' own positions, for when MultiViewer has none.
public enum OutlineTracer {
    /// A lap is under this far in all (1/10 m) ...
    static let maxLapUnits = 120_000.0
    /// ... and over this far before it may close,
    static let minLapUnits = 20_000.0
    /// close when back this near its start,
    static let closeUnits = 300.0
    /// with no gap in the samples longer than this.
    static let maxGapMs: Int64 = 2_000

    /// One lap of `track` between `from` and `to` (inclusive), or nil if no clean lap fits. From
    /// points a tenth, two tenths ... nine tenths of the way through the samples, follows the car
    /// until it comes back to its start, and keeps the quickest such loop (a racing line, not a
    /// pit-lane trip). (0,0) samples (every car's first few) are skipped.
    public static func trace(_ track: CarTrack, from: UTCms, to: UTCms) -> [TrackPoint]? {
        timed(track, from: from, to: to)?.points
    }

    /// As `trace`, over the 4 cars with the most samples; the quickest loop of them wins.
    public static func trace(_ series: PositionSeries, from: UTCms, to: UTCms) -> [TrackPoint]? {
        let cars = series.cars.values.sorted { ($0.times.count, $1.number) > ($1.times.count, $0.number) }.prefix(4)
        var best: (points: [TrackPoint], ms: Int64)?
        for car in cars {
            if let lap = timed(car, from: from, to: to), lap.ms < (best?.ms ?? .max) { best = lap }
        }
        return best?.points
    }

    private static func timed(_ track: CarTrack, from: UTCms, to: UTCms) -> (points: [TrackPoint], ms: Int64)? {
        var times: [UTCms] = []
        var points: [TrackPoint] = []
        for (i, t) in track.times.enumerated() where t >= from && t <= to {
            let p = track.point(i)
            if p.x == 0 && p.y == 0 { continue }
            times.append(t)
            points.append(p)
        }
        var best: (points: [TrackPoint], ms: Int64)?
        for k in 1...9 {
            if let lap = loop(times, points, from: points.count * k / 10), lap.ms < (best?.ms ?? .max) { best = lap }
        }
        return best
    }

    private static func loop(_ t: [UTCms], _ p: [TrackPoint], from start: Int) -> (points: [TrackPoint], ms: Int64)? {
        guard start < p.count else { return nil }
        var travelled = 0.0
        var i = start + 1
        while i < p.count {
            if t[i] - t[i - 1] > maxGapMs { return nil }
            travelled += hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y)
            if travelled > maxLapUnits { return nil }
            if travelled > minLapUnits, hypot(p[i].x - p[start].x, p[i].y - p[start].y) < closeUnits {
                return (Array(p[start...i]), t[i] - t[start])
            }
            i += 1
        }
        return nil
    }

    /// Where cars were when their lap count ticked over, pinned to the outline: the index of the
    /// outline point at the busiest stretch of 7 points (then its busiest point). Nil with fewer
    /// than 5 crossings that have a position, or an outline under 4 points.
    public static func startFinish(outline: [TrackPoint], crossings: [(car: String, at: UTCms)],
                                   tracks: [String: CarTrack]) -> Int? {
        guard outline.count >= 4 else { return nil }
        let geometry = TrackGeometry(outline: outline)
        let n = outline.count
        var counts = [Int](repeating: 0, count: n)
        var found = 0
        for crossing in crossings {
            guard let p = tracks[crossing.car]?.at(crossing.at) else { continue }
            counts[geometry.nearestIndex(to: p)] += 1
            found += 1
        }
        guard found >= 5 else { return nil }
        var best = 0
        var bestScore = -1
        for i in 0..<n {
            var c = 0
            for k in -3...3 { c += counts[(i + k + n) % n] }
            let score = c * 100_000 + counts[i]
            if score > bestScore { bestScore = score; best = i }
        }
        return best
    }

    /// The same loop, starting at point `index`.
    public static func outline(_ outline: [TrackPoint], startingAt index: Int) -> [TrackPoint] {
        guard !outline.isEmpty else { return outline }
        let n = outline.count
        let s = ((index % n) + n) % n
        return Array(outline[s...] + outline[..<s])
    }
}

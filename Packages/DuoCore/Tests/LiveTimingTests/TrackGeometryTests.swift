import Foundation
import Testing
import F1TV
@testable import LiveTiming

@Suite struct TrackGeometryTests {
    static let square = [TrackPoint(x: 0, y: 0), TrackPoint(x: 1000, y: 0), TrackPoint(x: 1000, y: 1000), TrackPoint(x: 0, y: 1000)]
    /// A wide strip, 1000 by 100.
    static let strip = [TrackPoint(x: 0, y: 0), TrackPoint(x: 1000, y: 0), TrackPoint(x: 1000, y: 100), TrackPoint(x: 0, y: 100)]

    /// A car lapping a square of side `side` from (`ox`, `oy`) counter-clockwise, `step` units per
    /// sample, `periodMs` apart, for `laps` laps. `cut` drops samples whose index is in it.
    static func car(laps: Int, side: Double = 6000, step: Double = 250, periodMs: Int64 = 250,
                    origin: TrackPoint = TrackPoint(x: 1000, y: 1000), zeros: Int = 0, cut: Range<Int> = 0..<0) -> CarTrack {
        var times: [UTCms] = [], xs: [Float] = [], ys: [Float] = []
        let t0: UTCms = 1_000_000
        for z in 0..<zeros {
            times.append(t0 + Int64(z) * periodMs); xs.append(0); ys.append(0)
        }
        let perLap = Int(4 * side / step)
        for i in 0...(laps * perLap) {
            let d = Double(i % perLap) * step
            let (dx, dy): (Double, Double)
            switch Int(d / side) {
            case 0: (dx, dy) = (d, 0)
            case 1: (dx, dy) = (side, d - side)
            case 2: (dx, dy) = (side - (d - 2 * side), side)
            default: (dx, dy) = (0, side - (d - 3 * side))
            }
            let index = zeros + i
            if cut.contains(index) { continue }
            times.append(t0 + Int64(index) * periodMs)
            xs.append(Float(origin.x + dx)); ys.append(Float(origin.y + dy))
        }
        return CarTrack(number: "1", times: times, xs: xs, ys: ys)
    }

    // MARK: progress

    @Test func progressAtCornersIsQuarters() {
        let g = TrackGeometry(outline: Self.square)
        #expect(g.progress(of: TrackPoint(x: 0, y: 0)) == 0)
        #expect(g.progress(of: TrackPoint(x: 1000, y: 0)) == 0.25)
        #expect(g.progress(of: TrackPoint(x: 1000, y: 1000)) == 0.5)
        #expect(g.progress(of: TrackPoint(x: 0, y: 1000)) == 0.75)
        // Between points, and off the line (projected on).
        #expect(g.progress(of: TrackPoint(x: 500, y: 0)) == 0.125)
        #expect(g.progress(of: TrackPoint(x: 500, y: -40)) == 0.125)
        // Along the closing segment, back to the start.
        #expect(g.progress(of: TrackPoint(x: 0, y: 500)) == 0.875)
        #expect(g.progress(of: TrackPoint(x: 0, y: 1000)) < 1)
    }

    @Test func progressOfDegenerateOutlinesIsZero() {
        #expect(TrackGeometry(outline: []).progress(of: TrackPoint(x: 1, y: 1)) == 0)
        #expect(TrackGeometry(outline: [TrackPoint(x: 5, y: 5)]).progress(of: TrackPoint(x: 1, y: 1)) == 0)
    }

    @Test func directionFollowsTheArea() {
        #expect(TrackGeometry(outline: Self.square).counterClockwise)
        #expect(!TrackGeometry(outline: Self.square.reversed()).counterClockwise)
    }

    // MARK: fit

    @Test func fitKeepsInsideBox() throws {
        let outline = try #require(Circuit.parse(try Fixture.json("circuit-14-2026.json"))).outline
        let g = TrackGeometry(outline: outline)
        let size = CGSize(width: 400, height: 300)
        for turn in [0.0, 15, 37, 90, -45] {
            let t = g.fit(in: size, inset: 20, userTurnDegrees: turn)
            let pts = outline.map(t.point)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            #expect(xs.min()! >= 20 - 1e-6 && xs.max()! <= 380 + 1e-6)
            #expect(ys.min()! >= 20 - 1e-6 && ys.max()! <= 280 + 1e-6)
            // It fills the box in at least one direction.
            #expect(xs.max()! - xs.min()! > 360 - 1e-6 || ys.max()! - ys.min()! > 260 - 1e-6)
        }
    }

    @Test func fitTurnsToFillTheBox() {
        // A 1000 x 100 strip in a 200 x 1000 box: turned upright it fills the height.
        let t = TrackGeometry(outline: Self.strip).fit(in: CGSize(width: 200, height: 1000), inset: 0, userTurnDegrees: 0)
        let ys = Self.strip.map { t.point($0).y }
        #expect(abs((ys.max()! - ys.min()!) - 1000) < 1e-6)
    }

    @Test func yIsFlipped() {
        let t = TrackGeometry(outline: Self.strip).fit(in: CGSize(width: 1000, height: 200), inset: 0, userTurnDegrees: 0)
        let low = t.point(TrackPoint(x: 0, y: 0)), high = t.point(TrackPoint(x: 0, y: 100))
        #expect(abs(low.x) < 1e-9 && abs(low.y - 150) < 1e-9)
        #expect(abs(high.x) < 1e-9 && abs(high.y - 50) < 1e-9)
    }

    @Test func userTurnRotates90() {
        let t = TrackGeometry(outline: Self.strip).fit(in: CGSize(width: 1000, height: 200), inset: 0, userTurnDegrees: 90)
        // Turned a quarter anticlockwise on the map: the strip stands up, its right end on top,
        // scaled by 0.2 to fit the height and centred.
        let origin = t.point(TrackPoint(x: 0, y: 0)), right = t.point(TrackPoint(x: 1000, y: 0))
        #expect(abs(origin.x - 510) < 1e-9 && abs(origin.y - 200) < 1e-9)
        #expect(abs(right.x - 510) < 1e-9 && abs(right.y - 0) < 1e-9)
    }

    @Test func fitSurvivesEmptyAndFlatOutlines() {
        let box = CGSize(width: 100, height: 100)
        let empty = TrackGeometry(outline: []).fit(in: box, inset: 10, userTurnDegrees: 0)
        #expect(empty.point(TrackPoint(x: 0, y: 0)).x.isFinite)
        let flat = TrackGeometry(outline: [TrackPoint(x: 0, y: 0), TrackPoint(x: 50, y: 0)]).fit(in: box, inset: 10, userTurnDegrees: 0)
        #expect(flat.point(TrackPoint(x: 50, y: 0)).x.isFinite)
        let tiny = TrackGeometry(outline: Self.square).fit(in: CGSize(width: 10, height: 10), inset: 20, userTurnDegrees: 0)
        #expect(tiny.point(TrackPoint(x: 1000, y: 1000)).x.isFinite)
    }

    // MARK: trace

    @Test func traceClosesOneLap() throws {
        // Two laps at 4 Hz, 100 units a sample, after three (0,0) samples.
        let car = Self.car(laps: 2, step: 100, zeros: 3)
        let lap = try #require(OutlineTracer.trace(car, from: 0, to: .max))
        // It closes as soon as it is back within 300 units of its start: 24 000 units round, so
        // 2 or 3 samples (200 units) short of the full 240 steps, never more.
        #expect((238...241).contains(lap.count))
        #expect(!lap.contains(TrackPoint(x: 0, y: 0)))
        #expect(hypot(lap[0].x - lap[lap.count - 1].x, lap[0].y - lap[lap.count - 1].y) < 300)
        // Every point is on the square's edge.
        for p in lap {
            let x = p.x - 1000, y = p.y - 1000
            #expect((x == 0 || x == 6000 || y == 0 || y == 6000) && x >= 0 && x <= 6000 && y >= 0 && y <= 6000)
        }
        // And the geometry sees one lap of it.
        #expect(abs(TrackGeometry(outline: lap).length - 24_000) < 400)
    }

    @Test func traceHonoursTheWindow() {
        let car = Self.car(laps: 2)
        // Not a whole lap in 10 s.
        #expect(OutlineTracer.trace(car, from: 1_000_000, to: 1_010_000) == nil)
    }

    @Test func traceRejectsGappyLap() {
        // A 3 s hole at 1.0 laps leaves no lap in the 2 without a gap.
        #expect(OutlineTracer.trace(Self.car(laps: 2, cut: 96..<108), from: 0, to: .max) == nil)
    }

    @Test func traceRejectsTooLongALap() {
        // 160 000 units round: more than 120 000 travelled before it closes.
        #expect(OutlineTracer.trace(Self.car(laps: 2, side: 40_000, step: 1000, periodMs: 250), from: 0, to: .max) == nil)
    }

    /// The race slice's cars (12 minutes, 2 minutes before lights out) hold full laps; the traced
    /// loop is checked against MultiViewer's own outline (an independent source), not a number.
    @Test func traceFindsARealLap() throws {
        let series = PositionSeries.parse(lines: try Fixture.lines("sp26-race/Position.z.jsonStream"))
        let circuit = try #require(Circuit.parse(try Fixture.json("circuit-14-2026.json")))
        let lap = try #require(OutlineTracer.trace(series, from: 0, to: .max))
        let g = TrackGeometry(outline: lap)
        #expect(g.length > 20_000 && g.length < 120_000)
        #expect(abs(g.length - 42_315) < 3_000)
        let reference = TrackGeometry(outline: circuit.outline)
        for p in lap {
            let q = circuit.outline[reference.nearestIndex(to: p)]
            #expect(hypot(p.x - q.x, p.y - q.y) < 500)
        }
    }

    // MARK: start/finish

    @Test func startFinishIsTheBusiestSpot() throws {
        let car = Self.car(laps: 2)
        let lap = try #require(OutlineTracer.trace(car, from: 0, to: .max))
        // Five cars crossing the line (the lap's start) a lap in, one a little late.
        var crossings: [(car: String, at: UTCms)] = []
        for i in 0..<5 { crossings.append((car: "1", at: UTCms(1_024_000 + (i % 2) * 10))) }
        crossings.append((car: "1", at: UTCms(1_012_000)))
        let index = try #require(OutlineTracer.startFinish(outline: lap, crossings: crossings, tracks: ["1": car]))
        // The busy spot is where the car was at the five crossings (the origin corner).
        #expect(TrackGeometry(outline: lap).nearestIndex(to: TrackPoint(x: 1000, y: 1000)) == index)
        let line = OutlineTracer.outline(lap, startingAt: 10)
        #expect(line.count == lap.count && line[0] == lap[10] && line.last == lap[9])
        #expect(OutlineTracer.startFinish(outline: lap, crossings: Array(crossings.prefix(4)), tracks: ["1": car]) == nil)
        #expect(OutlineTracer.startFinish(outline: lap, crossings: crossings, tracks: [:]) == nil)
    }
}

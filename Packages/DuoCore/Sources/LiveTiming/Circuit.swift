import Foundation
import F1TV

/// A numbered corner (`letter` is "" unless MultiViewer gives one, as for 6A / 6B).
public struct Corner: Sendable, Equatable {
    public var number: Int
    public var letter: String
    public var at: TrackPoint

    public init(number: Int, letter: String = "", at: TrackPoint) {
        self.number = number
        self.letter = letter
        self.at = at
    }
}

/// A circuit from MultiViewer: its outline, numbered corners, where each marshal sector starts, and
/// the angle MultiViewer draws it at. MultiViewer's coordinates are the Position feed's (1/10 m).
/// The outline does not start at the line; `OutlineTracer.startFinish` finds that.
public struct Circuit: Sendable, Equatable {
    public var outline: [TrackPoint]
    public var corners: [Corner]
    public var marshalSectors: [TrackPoint]
    public var rotationDegrees: Double

    public init(outline: [TrackPoint], corners: [Corner], marshalSectors: [TrackPoint], rotationDegrees: Double) {
        self.outline = outline
        self.corners = corners
        self.marshalSectors = marshalSectors
        self.rotationDegrees = rotationDegrees
    }

    /// MultiViewer's circuit data. Sent without the F1 token: it is a third party.
    public static func url(circuitKey: Int, year: Int) -> URL {
        URL(string: "https://api.multiviewer.app/api/v1/circuits/\(circuitKey)/\(year)")!
    }

    /// Nil unless `x` and `y` are equal-length arrays of numbers with at least 2 points. A corner
    /// or sector without a numeric `trackPosition` is skipped; a missing `rotation` is 0.
    public static func parse(_ json: JSONValue) -> Circuit? {
        let xs = json["x"].array, ys = json["y"].array
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        var outline: [TrackPoint] = []
        outline.reserveCapacity(xs.count)
        for (x, y) in zip(xs, ys) {
            guard let px = finite(x), let py = finite(y) else { return nil }
            outline.append(TrackPoint(x: px, y: py))
        }
        let corners: [Corner] = json["corners"].array.compactMap { c in
            guard let at = position(c["trackPosition"]), let number = c["number"].int else { return nil }
            return Corner(number: number, letter: c["letter"].string, at: at)
        }
        let sectors = json["marshalSectors"].array.compactMap { position($0["trackPosition"]) }
        return Circuit(outline: outline, corners: corners, marshalSectors: sectors,
                       rotationDegrees: finite(json["rotation"]) ?? 0)
    }

    private static func finite(_ v: JSONValue) -> Double? {
        if case .number(let d) = v, d.isFinite { return d }
        return nil
    }

    private static func position(_ v: JSONValue) -> TrackPoint? {
        guard let x = finite(v["x"]), let y = finite(v["y"]) else { return nil }
        return TrackPoint(x: x, y: y)
    }
}

import Foundation

/// One driver's line on the Scrub Deck's lap chart.
public struct LapChartRow: Sendable, Equatable {
    public var number: String
    /// The car's position as it finished each lap: index = lap − 1. Nil for a lap it hadn't
    /// finished (a lapped car not there yet, a retired car); every row has one entry per lap the
    /// leader has finished.
    public var positions: [Int?]

    public init(number: String, positions: [Int?]) {
        self.number = number
        self.positions = positions
    }
}

/// The Scrub Deck's lap chart: position by lap, for races and sprints.
public enum LapChart {
    /// The rows up to `t` (picture time): a car's position at each line crossing at or before
    /// `t`, as its timing stood after that crossing's update (F1 sends the new position with the
    /// lap count). No lap beyond the leader's at `t`, so nothing ahead of the picture shows.
    ///
    /// `t` nil is the whole race: the opt-in "Show the whole race on the Scrub Deck", off by
    /// default. Empty outside races (qualifying and practice show only the event strip).
    ///
    /// Rows are in running order at `t` (cars without a position last, by number); every car with
    /// timing has a row.
    public static func rows(until t: UTCms?, session: LoadedSession) -> [LapChartRow] {
        guard session.info.isRace else { return [] }
        let cut = t ?? .max
        var found: [(number: String, position: Int?, laps: [Int: Int?])] = []
        var columns = 0
        for (number, history) in session.timing.cars {
            guard let last = F1Values.lastIndex(in: history.times, atOrBefore: cut) else { continue }
            var laps: [Int: Int?] = [:]
            var crossed: UTCms?
            for state in history.states[...last] {
                guard let at = state.lineCrossedAt, at != crossed else { continue }
                crossed = at
                guard let lap = state.numberOfLaps, lap >= 1 else { continue }
                laps[lap] = state.position
                columns = max(columns, lap)
            }
            found.append((number, history.states[last].position, laps))
        }
        found.sort { a, b in
            switch (a.position, b.position) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return Tower.numberOrder(a.number, b.number)
            }
        }
        return found.map { car in
            LapChartRow(number: car.number, positions: (0..<columns).map { car.laps[$0 + 1] ?? nil })
        }
    }
}

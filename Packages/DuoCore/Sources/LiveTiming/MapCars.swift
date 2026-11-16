import Foundation

/// The cars the track map draws at a moment.
public enum MapCars {
    public struct Car: Sendable, Equatable {
        public var number: String
        /// The three-letter code; the number for a car DriverList doesn't name.
        public var tla: String
        /// "RRGGBB", or "" when unknown.
        public var teamColour: String
        public var point: TrackPoint
        public var position: Int?
        /// In the pits, knocked out or stopped: drawn dimmed and smaller.
        public var dimmed: Bool
        /// On a flying lap in qualifying: the yellow ring.
        public var flying: Bool

        public init(number: String, tla: String, teamColour: String, point: TrackPoint, position: Int?, dimmed: Bool, flying: Bool) {
            self.number = number
            self.tla = tla
            self.teamColour = teamColour
            self.point = point
            self.position = position
            self.dimmed = dimmed
            self.flying = flying
        }
    }

    /// Each car where its own samples put it at `t` (`CarTrack.mapPoint`: no (0,0) samples, none
    /// after `t`, hidden across a gap over 5 s), with its timing at `t`. Retired cars are left out.
    /// Dimmed cars come first, then from the back up, so the leader is drawn last (on top).
    ///
    /// The flying ring reads `lapStates`: the session's `LapStates`, built once from its timing
    /// (and rebuilt by a live caller as the timeline grows), never per call.
    public static func visible(at t: UTCms, session: LoadedSession, lapStates: LapStates) -> [Car] {
        let timing = session.timing.at(t)
        let states = session.info.isQualifying ? lapStates : nil
        var cars: [Car] = []
        cars.reserveCapacity(session.positions.cars.count)
        for (number, track) in session.positions.cars {
            let s = timing[number]
            if s?.retired == true { continue }
            guard let point = track.mapPoint(at: t) else { continue }
            let driver = session.drivers[number]
            cars.append(Car(
                number: number,
                tla: driver?.tla ?? number,
                teamColour: driver?.teamColour ?? "",
                point: point,
                position: s?.position,
                dimmed: s.map { $0.inPit || $0.knockedOut || $0.stopped } ?? false,
                flying: states?.state(of: number, at: t) == .push
            ))
        }
        cars.sort { a, b in
            if a.dimmed != b.dimmed { return a.dimmed }
            let pa = a.position ?? .max, pb = b.position ?? .max
            return pa != pb ? pa > pb : Tower.numberOrder(a.number, b.number)
        }
        return cars
    }
}

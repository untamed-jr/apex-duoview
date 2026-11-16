import F1TV
import Foundation
import LiveTiming

/// Finds the outline the map draws: MultiViewer's circuit (kept in the app's Caches as
/// `circuits/{key}-{year}.json`), else one traced from the cars' own positions (kept as
/// `circuits/traced-{key}.json`). Plain values in and out, no actor: `TimingController` runs it
/// off the main actor. MultiViewer is asked without the F1 token (it is a third party).
enum CircuitLoader {
    enum Outcome: Sendable {
        /// MultiViewer's circuit, or a traced one when MultiViewer has none: nothing more to try.
        case final(TrackMap)
        /// Traced from the cars while MultiViewer couldn't be reached: worth asking it again.
        case interim(TrackMap)
        /// No map yet: try again later.
        case none
    }

    static func load(circuitKey: Int?, year: Int, session: LoadedSession, http: any HTTPClient) async -> Outcome {
        var refused = false
        if let key = circuitKey {
            let name = "\(key)-\(year).json"
            if let data = read(name), let circuit = parse(data), let map = makeMap(circuit, session: session, traced: false) {
                return .final(map)
            }
            do {
                let response = try await http.send(HTTPRequest(method: "GET", url: Circuit.url(circuitKey: key, year: year)))
                if response.status == 200, let circuit = parse(response.body),
                   let map = makeMap(circuit, session: session, traced: false) {
                    write(response.body, name)
                    return .final(map)
                }
                // MultiViewer has no such circuit (or nothing usable): tracing is the answer.
                refused = (400..<500).contains(response.status) || response.status == 200
            } catch {
                // Not reached: the traced outline stands in until MultiViewer answers.
            }
        } else {
            refused = true
        }
        guard let map = traced(circuitKey: circuitKey, session: session) else { return .none }
        return refused ? .final(map) : .interim(map)
    }

    /// The outline from one clean lap of the cars' positions (Android's rules), kept per circuit.
    /// Geometry only: it reads the whole session, and nothing about it is shown as data.
    static func traced(circuitKey: Int?, session: LoadedSession) -> TrackMap? {
        let name = circuitKey.map { "traced-\($0).json" }
        if let name, let data = read(name), let circuit = parse(data), let map = makeMap(circuit, session: session, traced: true) {
            return map
        }
        let firsts = session.positions.cars.values.compactMap(\.first)
        let lasts = session.positions.cars.values.compactMap(\.last)
        guard let from = firsts.min(), let to = lasts.max(),
              let outline = OutlineTracer.trace(session.positions, from: from, to: to) else { return nil }
        let circuit = Circuit(outline: outline, corners: [], marshalSectors: [], rotationDegrees: 0)
        guard let map = makeMap(circuit, session: session, traced: true) else { return nil }
        if let name, let data = try? JSONSerialization.data(withJSONObject: ["x": outline.map(\.x), "y": outline.map(\.y)]) {
            write(data, name)
        }
        return map
    }

    /// The map for an outline: its start/finish line from where the cars' lap counts ticked over
    /// (the whole session's crossings, for geometry only), and the marshal sectors along it.
    static func makeMap(_ circuit: Circuit, session: LoadedSession, traced: Bool) -> TrackMap? {
        guard circuit.outline.count >= 4 else { return nil }
        let geometry = TrackGeometry(outline: circuit.outline)
        let start = OutlineTracer.startFinish(
            outline: circuit.outline, crossings: session.timing.lineCrossings(upTo: .max), tracks: session.positions.cars)
        let starts = circuit.marshalSectors.map { geometry.nearestIndex(to: $0) }
        return TrackMap(
            geometry: geometry,
            corners: circuit.corners,
            sectorRuns: TrackMap.sectorRuns(outlineCount: circuit.outline.count, starts: starts),
            startIndex: start,
            forward: TrackMap.drivesForward(geometry, positions: session.positions),
            traced: traced)
    }

    static func parse(_ data: Data) -> Circuit? {
        guard let json = try? JSONValue.parse(data) else { return nil }
        return Circuit.parse(json)
    }

    // MARK: Caches

    /// `Caches/circuits/`: the system may clear it; everything in it can be fetched again.
    static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("circuits", isDirectory: true)
    }

    static func read(_ name: String) -> Data? {
        guard let url = directory?.appendingPathComponent(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func write(_ data: Data, _ name: String) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

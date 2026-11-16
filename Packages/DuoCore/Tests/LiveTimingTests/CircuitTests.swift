import Foundation
import Testing
import F1TV
@testable import LiveTiming

@Suite struct CircuitTests {
    @Test func parsesSquare() throws {
        let circuit = try #require(Circuit.parse(try Fixture.json("circuit-square.json")))
        #expect(circuit.outline == [TrackPoint(x: 0, y: 0), TrackPoint(x: 1000, y: 0), TrackPoint(x: 1000, y: 1000), TrackPoint(x: 0, y: 1000)])
        #expect(circuit.corners.map(\.number) == [1, 2, 3, 4])
        #expect(circuit.corners[0].at == TrackPoint(x: 1000, y: 0))
        #expect(circuit.corners[0].letter == "")
        #expect(circuit.corners[3].letter == "A")
        #expect(circuit.marshalSectors == [TrackPoint(x: 500, y: 0), TrackPoint(x: 1000, y: 500)])
        #expect(circuit.rotationDegrees == 90)
    }

    @Test func rejectsOutlinesThatDoNotPair() {
        #expect(Circuit.parse(.object(["x": .array([.number(1), .number(2)]), "y": .array([.number(1)])])) == nil)
        #expect(Circuit.parse(.object([:])) == nil)
        #expect(Circuit.parse(.null) == nil)
    }

    @Test func urlIsMultiViewers() {
        #expect(Circuit.url(circuitKey: 14, year: 2026).absoluteString == "https://api.multiviewer.app/api/v1/circuits/14/2026")
    }

    /// check: the counts, rotation, area sign (> 0), length and progress values below were computed
    /// independently in Python (json + math) from circuit-14-2026.json.
    @Test func parsesInterlagos() throws {
        let circuit = try #require(Circuit.parse(try Fixture.json("circuit-14-2026.json")))
        #expect(circuit.outline.count == 283)
        #expect(circuit.corners.count == 15)
        #expect(circuit.corners.map(\.number) == Array(1...15))
        #expect(circuit.marshalSectors.count == 16)
        #expect(circuit.rotationDegrees == 258)
        #expect(circuit.outline[0] == TrackPoint(x: -3636, y: -5424))
        #expect(circuit.corners[0].at.x == -2393.436279296875)
        #expect(circuit.corners[0].at.y == -8518.955078125)

        let geometry = TrackGeometry(outline: circuit.outline)
        #expect(abs(geometry.length - 42315.230497342076) < 1e-6)
        #expect(geometry.counterClockwise)
        #expect(abs(geometry.progress(of: circuit.outline[100]) - 0.398285511535276) < 1e-9)
        let a = circuit.outline[100], b = circuit.outline[101]
        let mid = TrackPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        #expect(abs(geometry.progress(of: mid) - 0.4012718247112572) < 1e-9)
    }
}

import Foundation
import Testing
@testable import F1TV
@testable import LiveTiming

/// `JSONValue.parse` (JSONSerialization) against the decoder it replaced, on real F1 data:
/// every line of every committed stream, the archive's .json files, and a sample of the
/// inflated Position payloads.
@Suite struct JSONFastPathTests {
    static let streams = [
        "DriverList.json", "SessionInfo.json", "WeatherData.json",
        "ExtrapolatedClock.jsonStream", "Heartbeat.jsonStream", "LapCount.jsonStream",
        "RaceControlMessages.jsonStream", "SessionStatus.jsonStream", "TeamRadio.jsonStream",
        "TimingAppData.jsonStream", "TimingData.jsonStream", "TrackStatus.jsonStream",
        "WeatherData.jsonStream", "Position.z.jsonStream", "CarData.z.slice.jsonStream",
    ]

    /// Each line's JSON text, after its time prefix. A .json file is one payload.
    static func payloads(_ data: Data, stream: Bool) -> [Data] {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
        guard stream else { return [Data(body)] }
        return body.split(separator: 0x0A).compactMap { line in
            let bytes = line.last == 0x0D ? line.dropLast() : line
            guard let start = bytes.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "\"") }) else { return nil }
            return Data(bytes[start...])
        }
    }

    @Test(arguments: ["sp26-race", "sp26-quali"])
    func everyFixtureLineParsesTheSameBothWays(session: String) throws {
        var compared = 0, booleans = 0
        for name in Self.streams {
            guard let data = try? Fixture.data("\(session)/\(name)") else { continue }
            for (i, payload) in Self.payloads(data, stream: name.hasSuffix(".jsonStream")).enumerated() {
                let decoded = try? JSONValue.parseByDecoding(payload)
                let fast = try? JSONValue.parse(payload)
                #expect(fast == decoded, "\(session)/\(name) line \(i)")
                if let fast { booleans += Self.countBools(fast) }
                compared += 1
                // A .z line's payload, inflated: every 25th, as the decoder is slow on them.
                if name.contains(".z."), i % 25 == 0, case .string(let base64)? = fast,
                   let packed = Data(base64Encoded: base64), let json = try? Inflate.raw(packed) {
                    #expect(try JSONValue.parse(json) == (try JSONValue.parseByDecoding(json)), "\(session)/\(name) inflated line \(i)")
                    compared += 1
                }
            }
        }
        #expect(compared > 1_000)
        #expect(booleans > 100)  // the fixtures exercise booleans, not just numbers
    }

    @Test func indexParsesTheSameBothWays() throws {
        let payload = Self.payloads(try Fixture.data("Index-2026.json"), stream: false)[0]
        #expect(try JSONValue.parse(payload) == (try JSONValue.parseByDecoding(payload)))
    }

    static func countBools(_ v: JSONValue) -> Int {
        switch v {
        case .bool: return 1
        case .array(let a): return a.reduce(0) { $0 + countBools($1) }
        case .object(let o): return o.values.reduce(0) { $0 + countBools($1) }
        default: return 0
        }
    }
}

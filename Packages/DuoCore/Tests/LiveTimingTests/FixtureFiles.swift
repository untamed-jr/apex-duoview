import Foundation
import F1TV
@testable import LiveTiming

struct FixtureMissing: Error { let path: String }

/// The committed São Paulo 2026 fixtures (see Fixtures/README.md) and the values
/// `spike/trim_fixtures.py` decodes from them independently, named by its "check:" lines.
enum Fixture {
    static func url(_ path: String) throws -> URL {
        guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else { throw FixtureMissing(path: "Fixtures") }
        let url = dir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw FixtureMissing(path: path) }
        return url
    }

    static func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }

    /// The archive's .json files start with a UTF-8 BOM.
    static func json(_ path: String) throws -> JSONValue {
        var body = try data(path)
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
        return try JSONValue.parse(body)
    }

    static func lines(_ path: String) throws -> [StreamLine] { StreamLine.parseFile(try data(path)) }

    // check:raceHeartbeatStart
    static let raceStart: UTCms = 1_794_154_179_389
    // check:raceLightsOutUtc (SessionStatus "Started" at 00:53:44.576)
    static let raceLightsOut: UTCms = 1_794_157_403_965
    // check:qualiHeartbeatStart
    static let qualiStart: UTCms = 1_794_073_601_573
    // check:qualiQ1StartOffset
    static let qualiQ1: UTCms = qualiStart + 800_736
}

/// A `.z` stream line built in the test: the JSON packed with fixed-Huffman literals.
func zLine(_ offsetMs: Int64, _ json: String) -> StreamLine {
    StreamLine(offsetMs: offsetMs, json: .string(InflateTests.fixedLiteralStream(Array(json.utf8)).base64EncodedString()))
}

func line(_ text: String) -> StreamLine {
    guard let parsed = StreamLine.parse(text[...]) else { fatalError("bad test line: \(text)") }
    return parsed
}

func lines(_ texts: String...) -> [StreamLine] { texts.map(line) }

/// `yyyy-MM-ddTHH:mm:ss.fffZ` for a test's synthetic timestamps.
func iso(_ t: UTCms) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date(timeIntervalSince1970: Double(t) / 1000))
}

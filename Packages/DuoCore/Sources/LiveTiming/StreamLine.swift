import Foundation
import F1TV

/// One line of a `.jsonStream` file: `HH:MM:SS.mmm` followed by a JSON value.
/// A `.z` stream carries its JSON as a string; it stays `.string` here and callers decode it
/// with `ZPayload`.
public struct StreamLine: Sendable, Equatable {
    public let offsetMs: Int64
    public let json: JSONValue

    public init(offsetMs: Int64, json: JSONValue) {
        self.offsetMs = offsetMs
        self.json = json
    }

    public static func parse(_ line: Substring) -> StreamLine? {
        let bytes = Array(line.utf8)
        guard bytes.count > 12 else { return nil }
        func digit(_ i: Int) -> Int64? {
            let b = bytes[i]
            return b >= 48 && b <= 57 ? Int64(b - 48) : nil
        }
        guard bytes[2] == 58, bytes[5] == 58, bytes[8] == 46,
              let h1 = digit(0), let h2 = digit(1), let m1 = digit(3), let m2 = digit(4),
              let s1 = digit(6), let s2 = digit(7),
              let f1 = digit(9), let f2 = digit(10), let f3 = digit(11)
        else { return nil }
        let seconds = (h1 * 10 + h2) * 3600 + (m1 * 10 + m2) * 60 + (s1 * 10 + s2)
        let offset = seconds * 1000 + f1 * 100 + f2 * 10 + f3
        guard let json = try? JSONValue.parse(Data(bytes[12...])) else { return nil }
        return StreamLine(offsetMs: offset, json: json)
    }

    /// Strips a UTF-8 BOM and skips blank or unparseable lines. Only "\n" ends a line (a "\r"
    /// before it is dropped): U+2028 and friends may sit inside a JSON string.
    public static func parseFile(_ data: Data) -> [StreamLine] {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
        let text = String(decoding: body, as: UTF8.self)
        return text.utf8.split(separator: 0x0A).compactMap { bytes in
            let line = bytes.last == 0x0D ? bytes.dropLast() : bytes
            return parse(Substring(line))
        }
    }
}

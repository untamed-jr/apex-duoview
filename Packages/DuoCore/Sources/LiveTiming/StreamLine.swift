import Foundation
import F1TV

/// One line of a `.jsonStream` file: `HH:MM:SS.mmm` followed by a JSON value. Once F1's recorder
/// has run past a day the prefix is `d.HH:MM:SS.mmm` (the 2026 Mexico race's radio was all
/// "1.02:32:50.914"), as Android reads it.
/// A `.z` stream carries its JSON as a string; it stays `.string` here and callers decode it
/// with `ZPayload`.
public struct StreamLine: Sendable, Equatable {
    public let offsetMs: Int64
    public let json: JSONValue

    public init(offsetMs: Int64, json: JSONValue) {
        self.offsetMs = offsetMs
        self.json = json
    }

    /// Day counts past this many digits are not a recording (and could overflow).
    static let maxDayDigits = 4

    public static func parse(_ line: Substring) -> StreamLine? {
        let bytes = Array(line.utf8)
        func digit(_ i: Int) -> Int64? {
            let b = bytes[i]
            return b >= 48 && b <= 57 ? Int64(b - 48) : nil
        }
        // An optional "d." in front: 1 to 4 digits, then a dot.
        var days: Int64 = 0
        var p = 0
        while p < bytes.count, p <= maxDayDigits, let d = digit(p) {
            days = days * 10 + d
            p += 1
        }
        if p > 0, p < bytes.count, bytes[p] == 46, p <= maxDayDigits { p += 1 } else { p = 0; days = 0 }
        guard bytes.count > p + 12 else { return nil }
        guard bytes[p + 2] == 58, bytes[p + 5] == 58, bytes[p + 8] == 46,
              let h1 = digit(p), let h2 = digit(p + 1), let m1 = digit(p + 3), let m2 = digit(p + 4),
              let s1 = digit(p + 6), let s2 = digit(p + 7),
              let f1 = digit(p + 9), let f2 = digit(p + 10), let f3 = digit(p + 11)
        else { return nil }
        let seconds = days * 86_400 + (h1 * 10 + h2) * 3600 + (m1 * 10 + m2) * 60 + (s1 * 10 + s2)
        let offset = seconds * 1000 + f1 * 100 + f2 * 10 + f3
        guard let json = try? JSONValue.parse(Data(bytes[(p + 12)...])) else { return nil }
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

import Foundation
import F1TV

/// Small readers for the text forms F1's timing topics use, shared by the topic parsers.
enum F1Values {
    /// An F1 timestamp, with or without its trailing "Z" (race control leaves it off; it's UTC).
    static func utc(_ text: String) -> UTCms? {
        text.hasSuffix("Z") ? SignalR.utc(text) : SignalR.utc(text + "Z")
    }

    /// "-03:00:00", "02:00:00" or "+05:30" as seconds east of GMT.
    static func offsetSeconds(_ text: String) -> Int? {
        var body = Substring(text.trimmingCharacters(in: .whitespaces))
        var sign = 1
        if body.hasPrefix("-") { sign = -1; body = body.dropFirst() } else if body.hasPrefix("+") { body = body.dropFirst() }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let h = parts[0]!, m = parts.count > 1 ? parts[1]! : 0, s = parts.count > 2 ? parts[2]! : 0
        return sign * (h * 3600 + m * 60 + s)
    }

    /// A duration as F1 writes it: "1:21.024", "21.024", "02:00:00" or "1:02:03.5", in ms.
    /// Digits past the millisecond truncate. Nil for "" and anything else.
    static func durationMs(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), let last = parts.last else { return nil }
        var total = 0
        for part in parts.dropLast() {
            guard !part.isEmpty, let n = Int(part), n >= 0 else { return nil }
            total = total * 60 + n
        }
        let secParts = last.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(secParts.count), !secParts[0].isEmpty, let s = Int(secParts[0]), s >= 0 else { return nil }
        var ms = 0
        if secParts.count == 2 {
            let frac = secParts[1]
            guard !frac.isEmpty, frac.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            let three = String((frac + "000").prefix(3))
            ms = Int(three) ?? 0
        }
        return (total * 60 + s) * 1000 + ms
    }

    /// A number from `JSONSerialization`, which may give NSNumber or a native number.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String: return Double(s)
        default: return nil
        }
    }

    /// A whole number (truncated toward zero) from `JSONSerialization`; nil when out of range.
    static func int(_ value: Any?) -> Int? {
        guard let d = number(value), abs(d) < 1e15 else { return nil }
        return Int(d)
    }

    /// A `.z` line's payload decoded with `JSONSerialization`: much faster than `JSONValue` for
    /// Position and CarData, which inflate to tens of megabytes per session.
    static func zObject(_ line: StreamLine) -> [String: Any]? {
        guard case .string(let base64) = line.json,
              let packed = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let json = try? Inflate.raw(packed),
              let object = try? JSONSerialization.jsonObject(with: json) else { return nil }
        return object as? [String: Any]
    }

    /// Index-keyed objects ({"0": …, "1": …}) or arrays, in index order, nulls skipped.
    static func ordered(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let items):
            return items.filter { !$0.isNull }
        case .object(let members):
            return members.compactMap { key, v in Int(key).map { ($0, v) } }
                .sorted { $0.0 < $1.0 }
                .map(\.1)
                .filter { !$0.isNull }
        default:
            return []
        }
    }

    /// The last index whose time is ≤ `t`, or nil.
    static func lastIndex(in times: [UTCms], atOrBefore t: UTCms) -> Int? {
        var lo = 0, hi = times.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : lo - 1
    }
}

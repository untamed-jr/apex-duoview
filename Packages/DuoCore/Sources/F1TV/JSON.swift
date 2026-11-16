import Foundation

/// A parsed JSON value with lenient accessors: F1 TV's JSON has nulls, missing keys and
/// unexpected types, and none of that should make a whole row fail to parse.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parses with `JSONSerialization`, which reads a 70 000-line timing file many times faster
    /// than the decoder below (that one tries each type in turn and catches the failures).
    /// Top-level strings, numbers and nulls parse too. On F1's data the result is the decoder's
    /// (`JSONFastPathTests` compares every committed fixture line), booleans included: JSON's
    /// `true` is `.bool`, its `1` is `.number`. It differs only
    /// - on numbers written with 17 or more significant digits, which can come out a few ulps
    ///   off the decoder's correctly rounded value (up to about 16 measured on Linux);
    /// - on duplicate keys, where the last wins;
    /// - on literals that underflow, such as 1e-400, which read as 0 instead of throwing.
    /// `JSONValueTests.knownDifferencesFromTheDecoder` pins these.
    public static func parse(_ data: Data) throws -> JSONValue {
        value(try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
    }

    /// The `JSONDecoder` path `parse` replaced; kept to prove they agree.
    package static func parseByDecoding(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// The class of JSONSerialization's booleans (`__NSCFBoolean`, on Apple and Linux alike).
    /// Checked by class because a boolean NSNumber and the number 1 both cast to Bool.
    private static let booleanClass = ObjectIdentifier(type(of: NSNumber(value: true)))

    private static func value(_ any: Any) -> JSONValue {
        switch any {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            if ObjectIdentifier(type(of: n)) == booleanClass { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let a as [Any]:
            return .array(a.map(value))
        case let o as [String: Any]:
            return .object(o.mapValues(value))
        default:
            return .null
        }
    }

    /// The member for `key`, or `.null` when this isn't an object or the key is missing.
    public subscript(key: String) -> JSONValue {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    /// The element at `index`, or `.null` when this isn't an array or the index is out of range.
    public subscript(index: Int) -> JSONValue {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    /// Strings as they are, numbers as their text, anything else (null included) as "".
    public var string: String {
        switch self {
        case .string(let s): return s
        case .number(let d): return Self.text(d)
        default: return ""
        }
    }

    /// Whole numbers, and strings holding one.
    public var int: Int? {
        switch self {
        case .number(let d):
            guard d.isFinite, d == d.rounded(), abs(d) < 9.0e18 else { return nil }
            return Int(d)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var array: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }

    /// Booleans, and the strings "true" and "false".
    public var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s):
            switch s.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    public var isNull: Bool { self == .null }

    private static func text(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 9.0e18 { return String(Int(d)) }
        return String(d)
    }
}

extension JSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
}

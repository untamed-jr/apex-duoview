import Foundation
import F1TV

/// F1's delta format. Objects deep-merge; an object whose keys are all decimal strings is an
/// array update by index; scalars and arrays replace. `_kf` (keyframe marker) is dropped and
/// `_deleted` lists keys to remove from the object it sits in.
public enum TopicMerge {
    /// Indices past this are ignored, so a bad delta can't allocate an enormous array.
    static let maxIndex = 10_000

    public static func merge(_ base: JSONValue, _ delta: JSONValue) -> JSONValue {
        switch delta {
        case .object(var members):
            members["_kf"] = nil
            let deleted = members.removeValue(forKey: "_deleted")
            if case .array(var items) = base {
                guard isIndexed(members) else { return base }
                for (key, value) in members {
                    guard let index = Int(key), index <= maxIndex else { continue }
                    while items.count <= index { items.append(.null) }
                    items[index] = merge(items[index], value)
                }
                return .array(items)
            }
            var out: [String: JSONValue] = [:]
            if case .object(let existing) = base { out = existing }
            for key in deleted.map(keys) ?? [] { out[key] = nil }
            for (key, value) in members { out[key] = merge(out[key] ?? .null, value) }
            return .object(out)
        case .array(let items):
            return .array(items.map { merge(.null, $0) })
        default:
            return delta
        }
    }

    private static func keys(_ deleted: JSONValue) -> [String] {
        switch deleted {
        case .array(let a): return a.map(\.string)
        case .string(let s): return [s]
        case .object(let o): return Array(o.keys)
        default: return []
        }
    }

    /// Non-empty, and every key is ASCII digits.
    private static func isIndexed(_ members: [String: JSONValue]) -> Bool {
        !members.isEmpty && members.keys.allSatisfy { key in
            !key.isEmpty && key.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        }
    }
}

/// The merged state of every subscribed topic.
public struct TopicState: Sendable {
    public private(set) var topics: [String: JSONValue] = [:]

    public init() {}

    /// A snapshot (the subscribe result) replaces each topic it names; others are kept.
    public mutating func apply(snapshot: JSONValue) {
        guard case .object(let named) = snapshot else { return }
        for (topic, state) in named { topics[topic] = TopicMerge.merge(.null, state) }
    }

    public mutating func apply(topic: String, delta: JSONValue) {
        topics[topic] = TopicMerge.merge(topics[topic] ?? .null, delta)
    }
}

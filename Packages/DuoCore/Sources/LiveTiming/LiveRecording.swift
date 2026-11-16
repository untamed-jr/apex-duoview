import Foundation
import F1TV

/// One live timing message as received and recorded: a topic's change, or its whole state on
/// subscribing (`opening`).
public struct RecordedMessage: Equatable, Sendable {
    public var topic: String
    public var utc: UTCms
    public var opening: Bool
    public var json: JSONValue

    public init(topic: String, utc: UTCms, opening: Bool, json: JSONValue) {
        self.topic = topic
        self.utc = utc
        self.opening = opening
        self.json = json
    }

    /// What a SignalR message records: a feed message is one change at its own time; a
    /// subscribe result (`.snapshot`) is every topic it names, each `opening`, stamped
    /// `receivedAt`, in topic order. Every subscribe result is opening, the first and those
    /// after a reconnect alike (`LiveFeed` tells them apart). Anything else records nothing.
    public static func messages(from message: SignalR.Message, receivedAt: UTCms) -> [RecordedMessage] {
        switch message {
        case .feed(let topic, let data, let utc):
            return [RecordedMessage(topic: topic, utc: utc, opening: false, json: data)]
        case .snapshot(_, .object(let topics)):
            return topics.keys.sorted().map { RecordedMessage(topic: $0, utc: receivedAt, opening: true, json: topics[$0] ?? .null) }
        default:
            return []
        }
    }
}

/// The live recording's file format, Android's: a header naming the session, then one line per
/// message, `topic \t utc-ms \t 0|1 (opening) \t JSON \n`. One file per session, appended to
/// while the same session is reopened, started afresh for a new one. CarData.z and Heartbeat
/// are never recorded: car data is most of what F1 sends, and the live feed needs no heartbeat.
public enum LiveRecording {
    public static let excluded: Set<String> = ["CarData.z", "Heartbeat"]

    static let headerPrefix = "#session\t"

    /// Whether a topic's messages are written: not excluded, and a name the format can hold.
    public static func records(_ topic: String) -> Bool {
        !topic.isEmpty && !excluded.contains(topic) && !topic.utf8.contains(where: { $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
    }

    /// The message's line, ending in "\n"; empty for a topic that is not recorded. The JSON
    /// is compact, with sorted keys and every control character escaped, so it never holds a
    /// tab or a newline.
    public static func line(_ m: RecordedMessage) -> String {
        guard records(m.topic) else { return "" }
        var out = m.topic + "\t" + String(m.utc) + "\t" + (m.opening ? "1" : "0") + "\t"
        JSONText.write(m.json, to: &out)
        out += "\n"
        return out
    }

    /// The lines of every recorded message among `messages`, in order.
    public static func lines(_ messages: [RecordedMessage]) -> String {
        messages.map(line).joined()
    }

    /// `#session \t <path> \n`; tabs and line breaks in the path are dropped.
    public static func header(sessionPath: String) -> String {
        headerPrefix + String(sessionPath.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }) + "\n"
    }

    /// How to open the recording for a session.
    public enum Start: Equatable, Sendable {
        /// The file is this session's: append to it, with no second header.
        case append
        /// Start the file afresh (replacing whatever it held) with this header.
        case fresh(header: String)
    }

    /// From the start of the file as it is (its first line at least; nil or empty when there
    /// is no file): append when it is `sessionPath`'s recording, else start afresh.
    public static func start(existingHead: Data?, sessionPath: String) -> Start {
        let header = header(sessionPath: sessionPath)
        if let head = existingHead, head.starts(with: Data(header.utf8)) { return .append }
        return .fresh(header: header)
    }

    /// The session the recording holds (its first header) and its messages. Lines that can't
    /// be read are skipped, as is a last line with no "\n" (the file may be read mid-write).
    public static func read(_ data: Data) -> (sessionPath: String?, messages: [RecordedMessage]) {
        var sessionPath: String?
        var messages: [RecordedMessage] = []
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        _ = lines.popLast()  // after the last "\n": empty, or a line not yet finished
        let prefix = Array(headerPrefix.utf8)
        for raw in lines {
            let line = raw.last == 0x0D ? raw.dropLast() : raw
            if line.starts(with: prefix) {
                if sessionPath == nil { sessionPath = String(decoding: line.dropFirst(prefix.count), as: UTF8.self) }
                continue
            }
            let fields = line.split(separator: 0x09, maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, !fields[0].isEmpty,
                  let utc = Int64(String(decoding: fields[1], as: UTF8.self)),
                  fields[2].count == 1, let flag = fields[2].first, flag == 0x30 || flag == 0x31,
                  let json = try? JSONValue.parse(Data(fields[3]))
            else { continue }
            messages.append(RecordedMessage(topic: String(decoding: fields[0], as: UTF8.self), utc: utc,
                                            opening: flag == 0x31, json: json))
        }
        return (sessionPath, messages)
    }
}

/// JSONValue back to compact JSON text.
enum JSONText {
    static func string(_ value: JSONValue) -> String {
        var out = ""
        write(value, to: &out)
        return out
    }

    static func write(_ value: JSONValue, to out: inout String) {
        switch value {
        case .null:
            out += "null"
        case .bool(let b):
            out += b ? "true" : "false"
        case .number(let d):
            out += number(d)
        case .string(let s):
            quote(s, to: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                write(item, to: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, key) in members.keys.sorted().enumerated() {
                if i > 0 { out += "," }
                quote(key, to: &out)
                out += ":"
                write(members[key] ?? .null, to: &out)
            }
            out += "}"
        }
    }

    /// Whole numbers as integers; others as Swift's shortest text that reads back the same
    /// Double ("0.1", "1e-05"). JSON has no NaN or infinity: they are written as null.
    static func number(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        if d == d.rounded(), abs(d) < 9.0e18 { return String(Int64(d)) }
        return String(d)
    }

    static func quote(_ s: String, to out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}

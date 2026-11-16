import Foundation
import F1TV

/// The SignalR JSON protocol as F1's live timing uses it: frames end in 0x1E.
public enum SignalR {
    public static let topics: [String] = [
        "Heartbeat", "Position.z", "CarData.z", "TimingData", "DriverList", "SessionInfo",
        "SessionStatus", "RaceControlMessages", "TeamRadio", "TimingAppData", "TrackStatus",
        "LapCount", "ExtrapolatedClock", "WeatherData",
    ]

    private static let separator: UInt8 = 0x1E

    public enum Message: Sendable, Equatable {
        case feed(topic: String, data: JSONValue, utc: UTCms)
        case snapshot(invocationId: String, state: JSONValue)
        case ping
        case close(String?)
        case other
    }

    public static func negotiateToken(_ json: JSONValue) -> String? {
        for key in ["connectionToken", "connectionId"] {
            let value = json[key].string
            if !value.isEmpty { return value }
        }
        return nil
    }

    public static func handshake() -> Data { frame(#"{"protocol":"json","version":1}"#) }

    public static func subscribe(invocationId: String) -> Data {
        let id = (try? JSONEncoder().encode(invocationId)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        let list = topics.map { "\"\($0)\"" }.joined(separator: ",")
        return frame(#"{"type":1,"invocationId":\#(id),"target":"Subscribe","arguments":[[\#(list)]]}"#)
    }

    public static func ping() -> Data { frame(#"{"type":6}"#) }

    private static func frame(_ text: String) -> Data { Data(text.utf8) + [separator] }

    /// The complete frames in `data`. A trailing frame with no terminator is ignored, and
    /// frames that aren't JSON are dropped.
    public static func frames(_ data: Data) -> [JSONValue] {
        var parts = data.split(separator: separator, omittingEmptySubsequences: false)
        _ = parts.popLast()
        return parts.compactMap { try? JSONValue.parse(Data($0)) }
    }

    public static func message(_ json: JSONValue) -> Message {
        switch json["type"].int {
        case 1:
            let args = json["arguments"]
            guard json["target"].string == "feed", case .string(let topic) = args[0],
                  let utc = utc(args[2].string) else { return .other }
            return .feed(topic: topic, data: args[1], utc: utc)
        case 3:
            return .snapshot(invocationId: json["invocationId"].string, state: json["result"])
        case 6:
            return .ping
        case 7:
            if case .string(let error) = json["error"] { return .close(error) }
            return .close(nil)
        default:
            return .other
        }
    }

    /// `yyyy-MM-ddTHH:mm:ss[.f…]Z` with up to 7 fractional digits; sub-millisecond digits truncate.
    public static func utc(_ iso: String) -> UTCms? {
        let b = Array(iso.utf8)
        guard b.count >= 20, b.last == 90 else { return nil }
        func num(_ range: Range<Int>) -> Int64? {
            var n: Int64 = 0
            for i in range {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                n = n * 10 + Int64(b[i] - 48)
            }
            return n
        }
        guard b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58,
              let y = num(0..<4), let mo = num(5..<7), let d = num(8..<10),
              let h = num(11..<13), let mi = num(14..<16), let s = num(17..<19),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61
        else { return nil }
        var ms: Int64 = 0
        if b.count > 20 {
            guard b[19] == 46, b.count - 21 <= 7, b.count > 21 else { return nil }
            var scale: Int64 = 100
            for i in 20..<(b.count - 1) {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                ms += Int64(b[i] - 48) * scale
                scale /= 10
            }
        } else if b[19] != 90 { return nil }
        // Days from civil (Howard Hinnant).
        let yy = mo <= 2 ? y - 1 : y
        let era = yy / 400
        let yoe = yy - era * 400
        let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return ((days * 24 + h) * 60 + mi) * 60_000 + s * 1000 + ms
    }
}

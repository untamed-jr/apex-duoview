import Foundation
import F1TV

/// One car from the archive's DriverList.json.
public struct DriverInfo: Sendable, Equatable {
    public var number: String
    public var tla: String
    public var firstName: String
    public var lastName: String
    public var teamName: String
    /// "RRGGBB", or "" when F1 leaves it out.
    public var teamColour: String

    public init(number: String, tla: String, firstName: String, lastName: String, teamName: String, teamColour: String) {
        self.number = number
        self.tla = tla
        self.firstName = firstName
        self.lastName = lastName
        self.teamName = teamName
        self.teamColour = teamColour
    }
}

public enum Drivers {
    /// Keyed by racing number. Entries that aren't objects (such as `_kf`) are skipped; a
    /// missing three-letter code falls back to the number, as Android does.
    public static func parse(_ json: JSONValue) -> [String: DriverInfo] {
        guard case .object(let members) = json else { return [:] }
        var out: [String: DriverInfo] = [:]
        for (number, d) in members {
            guard case .object = d, !number.hasPrefix("_") else { continue }
            let tla = d["Tla"].string
            let colour = d["TeamColour"].string.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            out[number] = DriverInfo(
                number: number,
                tla: tla.isEmpty ? number : tla,
                firstName: d["FirstName"].string,
                lastName: d["LastName"].string,
                teamName: d["TeamName"].string,
                teamColour: colour.count == 6 && colour.allSatisfy(\.isHexDigit) ? colour.uppercased() : ""
            )
        }
        return out
    }
}

/// The archive's SessionInfo.json.
public struct TimingSessionInfo: Sendable, Equatable {
    public var key: Int?
    public var name: String
    public var type: String
    public var path: String
    /// The scheduled start, from the local StartDate and GmtOffset.
    public var start: UTCms?
    public var gmtOffsetSeconds: Int
    public var circuitKey: Int?
    public var meetingName: String
    public var year: Int?

    public init(key: Int?, name: String, type: String, path: String, start: UTCms?, gmtOffsetSeconds: Int,
                circuitKey: Int?, meetingName: String, year: Int?) {
        self.key = key
        self.name = name
        self.type = type
        self.path = path
        self.start = start
        self.gmtOffsetSeconds = gmtOffsetSeconds
        self.circuitKey = circuitKey
        self.meetingName = meetingName
        self.year = year
    }

    /// Nil unless it's an object naming the session by key or path.
    public static func parse(_ json: JSONValue) -> TimingSessionInfo? {
        guard case .object = json else { return nil }
        let key = json["Key"].int
        let path = json["Path"].string
        guard key != nil || !path.isEmpty else { return nil }
        let offset = F1Values.offsetSeconds(json["GmtOffset"].string) ?? 0
        let startDate = json["StartDate"].string
        let start = F1Values.utc(startDate).map { $0 - Int64(offset) * 1000 }
        let year = Int(startDate.prefix(4)) ?? path.split(separator: "/").first.flatMap { Int($0) }
        return TimingSessionInfo(
            key: key,
            name: json["Name"].string,
            type: json["Type"].string,
            path: path,
            start: start,
            gmtOffsetSeconds: offset,
            circuitKey: json["Meeting"]["Circuit"]["Key"].int,
            meetingName: json["Meeting"]["Name"].string,
            year: year
        )
    }
}

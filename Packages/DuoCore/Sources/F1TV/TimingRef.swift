import Foundation

/// Where F1's timing archive files a video's session, from F1 TV's event metadata
/// (`emfAttributes`): the season, the meeting and session keys, the circuit and the names
/// that identify the session when the keys don't.
public struct TimingRef: Sendable, Hashable {
    public var year: Int
    /// F1's meeting key, as text ("1299").
    public var meetingKey: String
    /// F1's session key ("11412"); nil for videos that belong to the weekend, not a session.
    public var sessionKey: String?
    public var circuitKey: Int?
    public var meetingName: String
    /// F1 TV's full title, such as "2026 São Paulo GP - Practice 2": it names the session.
    public var title: String
    /// When the session starts or ran.
    public var start: Date?

    public init(year: Int, meetingKey: String, sessionKey: String? = nil, circuitKey: Int? = nil,
                meetingName: String, title: String, start: Date? = nil) {
        self.year = year
        self.meetingKey = meetingKey
        self.sessionKey = sessionKey
        self.circuitKey = circuitKey
        self.meetingName = meetingName
        self.title = title
        self.start = start
    }
}

extension TimingRef {
    /// What F1 TV titles a session after its last " - " ("2026 São Paulo GP - Practice 2").
    static let sessionTitles = ["Practice 1", "Practice 2", "Practice 3", "Qualifying", "Sprint", "Sprint Race",
                                "Sprint Qualifying", "Sprint Shootout", "Race"]

    /// Whether this video is a timed session itself (a race, sprint, qualifying, sprint
    /// qualifying or shootout, or practice) rather than something about one, so the timing views
    /// apply. F1 TV gives highlights, "Race in 30", radio and press conferences the session's
    /// own key, and the shows keys of their own ("Pre-Race Show" is 11412001), so the key alone
    /// doesn't decide. A session has a numeric session key and a session's title:
    /// - "2026 São Paulo Grand Prix", the race replay: ends in "Grand Prix", with no " - ";
    /// - "2026 São Paulo GP - Qualifying": one of `sessionTitles` after the last " - ".
    /// A title with ":" ("1998 in Review: Australian Grand Prix") is never one.
    public var isSession: Bool {
        guard let key = sessionKey?.trimmingCharacters(in: .whitespaces), !key.isEmpty,
              key.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else { return false }
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(":") else { return false }
        if let dash = text.range(of: " - ", options: .backwards) {
            let tail = text[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            return Self.sessionTitles.contains { tail.caseInsensitiveCompare($0) == .orderedSame }
        }
        return text.lowercased().hasSuffix(" grand prix")
    }
}

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

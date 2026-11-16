import Foundation
import F1TV

/// The session's status through time, from SessionStatus: "Inactive", "Started", "Aborted",
/// "Finished", "Finalised", "Ends" (F1's words, kept as they are).
public struct SessionStatusTimeline: Sendable, Equatable {
    public struct Change: Sendable, Equatable {
        public var at: UTCms
        public var status: String

        public init(at: UTCms, status: String) {
            self.at = at
            self.status = status
        }
    }

    /// Oldest first; changes at the same moment keep the order sent.
    public let changes: [Change]

    public init(changes: [Change] = []) {
        self.changes = changes
    }

    /// Lines are timed at `streamStart + offset`; a line without a Status is skipped.
    public static func build(lines: [StreamLine], streamStart: UTCms) -> SessionStatusTimeline {
        let changes = lines.compactMap { line -> Change? in
            let status = line.json["Status"].string
            guard !status.isEmpty else { return nil }
            return Change(at: F1Values.add(streamStart, line.offsetMs), status: status)
        }
        return SessionStatusTimeline(changes: changes.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element))
    }

    /// The status at `t`: the latest change at or before it; nil before the first.
    public func status(at t: UTCms) -> String? {
        changes.last { $0.at <= t }?.status
    }

    /// When the status first became `status`.
    public func first(_ status: String) -> UTCms? {
        changes.first { $0.status == status }?.at
    }

    /// When the session first went to "Started", Android's session start (on the 2026 São Paulo
    /// race, lights out); nil when it never did.
    public var started: UTCms? { first("Started") }
}

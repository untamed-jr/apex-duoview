import Foundation
import F1TV

/// The session's status through time, from SessionStatus: "Inactive", "Started", "Aborted",
/// "Finished", "Finalised", "Ends" (F1's words, kept as they are).
public struct SessionStatusTimeline: Sendable, Equatable {
    public struct Change: Sendable, Equatable {
        public var at: UTCms
        public var status: String
        /// Only the state on joining, not a change at `at`: a live feed's opening snapshot (at
        /// the stream's start), or what an archive top-up lacked of it. `status(at:)` reads it;
        /// `started`, `first`, the timeline's marks and the Scrub Deck's events don't.
        public var isSnapshot: Bool

        public init(at: UTCms, status: String, isSnapshot: Bool = false) {
            self.at = at
            self.status = status
            self.isSnapshot = isSnapshot
        }
    }

    /// Oldest first; changes at the same moment keep the order sent. Whole session: anything
    /// shown as data must read it at or before picture time (`status(at:)`), never later.
    public let changes: [Change]

    public init(changes: [Change] = []) {
        self.changes = changes
    }

    /// Lines are timed at `streamStart + offset`; a line without a Status is skipped. The lines
    /// at the indices in `snapshotLines` are states on joining (`Change.isSnapshot`).
    public static func build(lines: [StreamLine], streamStart: UTCms, snapshotLines: Set<Int> = []) -> SessionStatusTimeline {
        let changes = lines.enumerated().compactMap { i, line -> Change? in
            let status = line.json["Status"].string
            guard !status.isEmpty else { return nil }
            return Change(at: F1Values.add(streamStart, line.offsetMs), status: status, isSnapshot: snapshotLines.contains(i))
        }
        return SessionStatusTimeline(changes: changes.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element))
    }

    /// The status at `t`: the latest change at or before it; nil before the first.
    public func status(at t: UTCms) -> String? {
        changes.last { $0.at <= t }?.status
    }

    /// When the status first became `status`, leaving out states on joining. Whole session:
    /// for the session's shape (marks), not for data shown at picture time.
    public func first(_ status: String) -> UTCms? {
        changes.first { $0.status == status && !$0.isSnapshot }?.at
    }

    /// When the session first went to "Started", Android's session start (on the 2026 São Paulo
    /// race, lights out); nil when it never did, or when a state on joining already had it under
    /// way (anything but "Inactive"): the lights went out before the feed joined, and a later
    /// "Started" (after a red flag) is a restart. Whole session, as `first`.
    public var started: UTCms? {
        for change in changes {
            if change.isSnapshot {
                if change.status != "Inactive" { return nil }
                continue
            }
            if change.status == "Started" { return change.at }
        }
        return nil
    }
}

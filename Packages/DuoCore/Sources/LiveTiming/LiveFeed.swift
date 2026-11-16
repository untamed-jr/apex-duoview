import Foundation
import F1TV

/// A live session's timing, assembled from live timing's messages (or the recording of them)
/// into each topic's `.jsonStream` lines, so the archive's parsers build the same timelines as
/// for a replay (Android's `LiveTimingFeed`).
///
/// - Stream start: `headStartMs` (12 h) before the first snapshot, Android's head start: the
///   picture runs behind the timing, and the archive's session so far fits in front.
/// - The first snapshot (the subscribe result, one `opening` message per topic) is each topic's
///   first line, at offset 0, so a picture from before joining shows the state on joining.
///   Changes before it are dropped: the snapshot already holds them.
/// - Changes follow at their own times.
/// - A later snapshot (after a reconnect, or the app reopened on the same recording) starts a
///   fresh `TopicState`: a topic it doesn't name is gone. Its topics are not appended again:
///   only the difference from what the lines already hold is, at its time, so no lap,
///   pit stop or race control message is counted twice and the history stays.
/// - `topUp` puts the archive's session before joining in place of the opening lines.
///
/// CarData.z and Heartbeat (`LiveRecording.excluded`) are ignored, so a feed built live equals
/// one rebuilt from the recording.
public struct LiveFeed: Sendable {
    public static let headStartMs: Int64 = 12 * 3_600_000

    /// The live state of every topic named since the last snapshot.
    public private(set) var state = TopicState()
    /// `headStartMs` before the first snapshot; nil until there is one.
    public private(set) var streamStart: UTCms?

    /// Each topic's first snapshot, as received, at offset 0.
    private var opening: [String: StreamLine] = [:]
    /// The archive's lines before joining (`topUp`), in place of the opening line.
    private var past: [String: [StreamLine]] = [:]
    /// After `past`: what turns the archive's last state into the opening snapshot, at the join.
    private var joinPatch: [String: StreamLine] = [:]
    /// Changes, and the differences later snapshots brought, oldest first.
    private var deltas: [String: [StreamLine]] = [:]
    /// What each topic's lines merge to (opening, changes and differences): the base each
    /// later snapshot is compared with. Unlike `state`, a snapshot never clears it.
    private var merged: [String: JSONValue] = [:]
    /// The topics of the snapshot being received; nil once a change has followed it.
    private var snapshotTopics: Set<String>?

    public init() {}

    /// A feed rebuilt from recorded messages (`LiveRecording.read`).
    public init(_ messages: [RecordedMessage]) {
        for m in messages { apply(m) }
    }

    /// When the feed joined: its first snapshot's time.
    public var joinedAt: UTCms? { streamStart.map { F1Values.add($0, Self.headStartMs) } }

    public mutating func apply(_ m: RecordedMessage) {
        guard LiveRecording.records(m.topic) else { return }
        if m.opening {
            // A snapshot is a run of opening messages; one following a change, or naming a
            // topic this run already gave, is the next snapshot.
            if snapshotTopics.map({ $0.contains(m.topic) }) ?? true { beginSnapshot(at: m.utc) }
            snapshotTopics?.insert(m.topic)
            receiveSnapshot(m)
        } else {
            snapshotTopics = nil
            guard let start = streamStart else { return }  // before the first snapshot
            state.apply(topic: m.topic, delta: m.json)
            merged[m.topic] = TopicMerge.merge(merged[m.topic] ?? .null, m.json)
            deltas[m.topic, default: []].append(StreamLine(offsetMs: max(F1Values.sub(m.utc, start), 0), json: m.json))
        }
    }

    private mutating func beginSnapshot(at utc: UTCms) {
        snapshotTopics = []
        if streamStart == nil { streamStart = F1Values.sub(utc, Self.headStartMs) }
        state = TopicState()
    }

    private mutating func receiveSnapshot(_ m: RecordedMessage) {
        guard let start = streamStart else { return }
        let value = TopicMerge.merge(.null, m.json)
        state.apply(topic: m.topic, delta: m.json)
        if let before = merged[m.topic] {
            if let patch = TopicPatch.delta(from: before, to: value) {
                deltas[m.topic, default: []].append(StreamLine(offsetMs: max(F1Values.sub(m.utc, start), 0), json: patch))
            }
        } else if opening[m.topic] == nil {
            // The topic's first line: before any change, at the stream's start.
            opening[m.topic] = StreamLine(offsetMs: 0, json: m.json)
        }
        merged[m.topic] = value
    }

    /// A topic's lines, as the archive parsers read them: the opening state (or the archive's
    /// session before joining), then the changes. Offsets never go back: one before the line
    /// ahead of it (F1's clock against the phone's, at a snapshot) takes that line's.
    public func lines(_ topic: String) -> [StreamLine] {
        var out: [StreamLine]
        if let archive = past[topic] {
            out = archive + (joinPatch[topic].map { [$0] } ?? [])
        } else {
            out = opening[topic].map { [$0] } ?? []
        }
        out += deltas[topic] ?? []
        var latest: Int64 = 0
        for i in out.indices {
            if out[i].offsetMs < latest {
                out[i] = StreamLine(offsetMs: latest, json: out[i].json)
            } else {
                latest = out[i].offsetMs
            }
        }
        return out
    }

    /// The topics a live session reads besides DriverList, SessionInfo and Position, listed in
    /// `LoadedSession.missing` until they arrive (LapCount for races only), as the archive's.
    static func optionalTopics(type: String) -> [String] {
        ["TimingData", "TimingAppData", "RaceControlMessages", "TrackStatus", "SessionStatus"]
            + (type == "Race" ? ["LapCount"] : []) + ["ExtrapolatedClock", "WeatherData"]
    }

    /// The session so far, built by the archive's parsers. `drivers` and `info`, when given,
    /// stand in for the feed's own DriverList and SessionInfo. Nil before the first snapshot
    /// or without session info. Unlike the archive, a session without car positions is still
    /// returned (empty `positions`): the timing works, and the app says F1 isn't sending them.
    /// Every timeline is rebuilt on each call, so the caller decides how often (Android: 10 s).
    public func session(drivers: [String: DriverInfo]? = nil, info: TimingSessionInfo? = nil) -> LoadedSession? {
        guard let start = streamStart,
              let info = info ?? TimingSessionInfo.parse(state.topics["SessionInfo"] ?? .null)
        else { return nil }
        let optional = Self.optionalTopics(type: info.type)
        return LoadedSession(
            info: info,
            drivers: drivers ?? Drivers.parse(state.topics["DriverList"] ?? .null),
            streamStart: start,
            positions: PositionSeries.parse(lines: lines("Position.z")),
            timing: TimingTimeline.build(lines: lines("TimingData"), streamStart: start),
            stints: StintTimeline.build(lines: lines("TimingAppData"), streamStart: start),
            header: HeaderTimeline.build(lapCount: lines("LapCount"), clock: lines("ExtrapolatedClock"),
                                         weather: lines("WeatherData"), streamStart: start),
            flags: TrackFlags.build(trackStatus: lines("TrackStatus"), raceControl: lines("RaceControlMessages"),
                                    streamStart: start, gmtOffsetSeconds: info.gmtOffsetSeconds),
            sessionStatus: SessionStatusTimeline.build(lines: lines("SessionStatus"), streamStart: start),
            missing: optional.filter { lines($0).isEmpty }
        )
    }

    /// Tops the feed up from F1's archive (Android's backfill): each topic's archive lines
    /// (`.jsonStream`, offsets from `archiveStart`) replace its opening line, up to the join or
    /// the topic's first live line, whichever is earlier. The snapshot is stamped when it
    /// arrives but holds the state from a little before, so changes between the two come live
    /// too: cutting the archive at the first of them keeps each from counting twice.
    ///
    /// When the topic's archive stops `Backfill.completeGapMs` or more before the join (it
    /// lags), the difference from its last state to the opening snapshot follows at the join,
    /// so the state on joining is right. Closer than that, as Android, there is none: the
    /// snapshot's state may be older than the archive's last lines, and a difference back to
    /// it would undo laps the live changes then count again.
    ///
    /// A topic with no archive lines before the cut keeps its opening line. Called again with
    /// a fuller archive, the newer lines replace the older.
    public mutating func topUp(archive: [String: [StreamLine]], archiveStart: UTCms) {
        guard let start = streamStart, let joined = joinedAt else { return }
        for (topic, archived) in archive where LiveRecording.records(topic) {
            let firstLive = deltas[topic]?.first.map { F1Values.add(start, $0.offsetMs) } ?? joined
            let before = Backfill.rebase(archived, archiveStart: archiveStart, newStart: start, until: min(joined, firstLive))
            guard let last = before.last else { continue }
            past[topic] = before
            joinPatch[topic] = nil
            guard let open = opening[topic],
                  F1Values.sub(joined, F1Values.add(start, last.offsetMs)) >= Backfill.completeGapMs
            else { continue }
            let reached = before.reduce(JSONValue.null) { TopicMerge.merge($0, $1.json) }
            if let patch = TopicPatch.delta(from: reached, to: TopicMerge.merge(.null, open.json)) {
                joinPatch[topic] = StreamLine(offsetMs: F1Values.sub(joined, start), json: patch)
            }
        }
    }
}

/// The smallest F1-style delta that `TopicMerge.merge` turns one state into another with:
/// `merge(old, delta(from: old, to: new)!) == new` for any `new` that `merge(.null, _)` leaves
/// as it is (a merged state), and nil when they are equal. One exception: a list held in its
/// index-keyed form ({"0": …, "1": …}) stays in that form, with the new list's entries.
enum TopicPatch {
    private enum Patch {
        case same
        case delta(JSONValue)
        /// An array becoming an object: merge can't do it in place.
        case replace
    }

    static func delta(from old: JSONValue, to new: JSONValue) -> JSONValue? {
        switch patch(old, new) {
        case .same: return nil
        case .delta(let d): return d
        // At the top there's no parent to delete the key from; the whole state is the best
        // there is (every topic's state is an object in practice).
        case .replace: return new
        }
    }

    private static func patch(_ old: JSONValue, _ new: JSONValue) -> Patch {
        if old == new { return .same }
        switch (old, new) {
        case (.object(let o), .object(let n)):
            var members: [String: JSONValue] = [:]
            var deleted = o.keys.filter { n[$0] == nil }
            for (key, value) in n {
                guard let was = o[key] else {
                    members[key] = value  // a missing key isn't a null one: always given
                    continue
                }
                switch patch(was, value) {
                case .same: continue
                case .delta(let d): members[key] = d
                case .replace:
                    deleted.append(key)
                    members[key] = value
                }
            }
            if !deleted.isEmpty { members["_deleted"] = .array(deleted.sorted().map { .string($0) }) }
            return members.isEmpty ? .same : .delta(.object(members))
        case (.array(let a), .array(let n)):
            // A shorter list, or one past what an indexed delta may reach, is given whole.
            guard n.count >= a.count, n.count - 1 <= TopicMerge.maxIndex else { return .delta(new) }
            var members: [String: JSONValue] = [:]
            for (i, value) in n.enumerated() {
                guard i < a.count else {
                    members[String(i)] = value
                    continue
                }
                switch patch(a[i], value) {
                case .same: continue
                case .delta(let d): members[String(i)] = d
                case .replace: return .delta(new)
                }
            }
            return members.isEmpty ? .same : .delta(.object(members))
        case (.object(let o), .array(let n)) where !o.isEmpty && o.keys.allSatisfy({ Int($0).map { $0 >= 0 } ?? false }):
            // A list whose first entries came as changes ({"0": …}) and now comes whole: compared
            // entry by entry, so entries already there aren't sent again. The result keeps the
            // index-keyed form, which the parsers read as the same list.
            var members: [String: JSONValue] = [:]
            for (i, value) in n.enumerated() {
                guard let was = o[String(i)] else {
                    members[String(i)] = value
                    continue
                }
                switch patch(was, value) {
                case .same: continue
                case .delta(let d): members[String(i)] = d
                case .replace: return .delta(new)
                }
            }
            let gone = o.keys.filter { Int($0).map { $0 >= n.count } ?? true }
            if !gone.isEmpty { members["_deleted"] = .array(gone.sorted().map { .string($0) }) }
            return members.isEmpty ? .same : .delta(.object(members))
        case (.array, .object):
            return .replace
        default:
            return .delta(new)
        }
    }
}

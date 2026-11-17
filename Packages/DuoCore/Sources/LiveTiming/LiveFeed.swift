import Foundation
import F1TV

/// A live session's timing, assembled from live timing's messages (or the recording of them)
/// into each topic's `.jsonStream` lines, so the archive's parsers build the same timelines as
/// for a replay (Android's `LiveTimingFeed`).
///
/// - Stream start: `headStartMs` (12 h) before the first snapshot, Android's head start: the
///   picture runs behind the timing, and the archive's session so far fits in front.
/// - The first snapshot (the subscribe result, one `opening` message per topic) is each topic's
///   first line, at offset 0, so a picture from before joining shows the state on joining
///   (the app labels picture times before `joinedAt` as catching up).
///   Changes before it are dropped: the snapshot already holds them.
/// - Changes follow at their own times.
/// - A later snapshot (after a reconnect, or the app reopened on the same recording) starts a
///   fresh `TopicState`: a topic it doesn't name is gone. Its topics are not appended again:
///   only the difference from what the lines already hold is, at its time, so no lap,
///   pit stop or race control message is counted twice and the history stays. A topic it
///   names for the first time starts at its time, not before.
/// - One session per feed: SessionInfo with another `Path` starts the feed afresh, from the
///   snapshot naming it (or, when the new path comes as a change, from the next snapshot: the
///   app reconnects, as Android does when live timing moves on).
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
    /// The session the feed holds: the latest SessionInfo `Path` it was given.
    public private(set) var sessionPath: String?

    /// Each topic's first snapshot, as received, at offset 0.
    private var opening: [String: StreamLine] = [:]
    /// Changes, and the lines later snapshots brought, oldest first.
    private var deltas: [String: [StreamLine]] = [:]
    /// Where in `deltas` each topic's first change is (lines before it came from snapshots).
    private var firstChange: [String: Int] = [:]
    /// Topics first named by a later snapshot: their `deltas` start with that snapshot whole.
    private var lateStart: Set<String> = []
    /// What each topic's lines merge to (opening, changes and differences): the base each
    /// later snapshot is compared with. Unlike `state`, a snapshot never clears it.
    private var merged: [String: JSONValue] = [:]
    /// The topics of the snapshot being received; nil once a change has followed it.
    private var snapshotTopics: Set<String>?
    /// That snapshot's messages, to start afresh from when it names another session.
    private var snapshotRun: [RecordedMessage] = []
    /// Whether the snapshot being received is the first (no change or snapshot since).
    private var inFirstSnapshot = false
    /// After `topUp`: each topic's archive lines and seam, and where its live lines resume.
    private var topped: [String: Topped] = [:]
    /// What `session()` keeps between calls; nil starts it again (a top-up or a later snapshot,
    /// which can change lines already read).
    private var folds: Folds?

    struct Topped: Sendable {
        var lines: [StreamLine]
        /// The first of `deltas` that follows them.
        var from: Int
        /// Where in `lines` the difference from the archive's state to the snapshot's is, if any.
        var patchIndex: Int?
    }

    public init() {}

    /// A feed rebuilt from recorded messages (`LiveRecording.read`).
    public init(_ messages: [RecordedMessage]) {
        for m in messages { apply(m) }
    }

    /// When the feed joined live timing: its first snapshot's time. The timelines before it
    /// hold the state on joining (until `topUp` puts the archive there), so the app shows a
    /// picture time before it as catching up.
    public var joinedAt: UTCms? { streamStart.map { F1Values.add($0, Self.headStartMs) } }

    public mutating func apply(_ m: RecordedMessage) {
        guard LiveRecording.records(m.topic) else { return }
        if m.topic == "SessionInfo" {
            let path = m.json["Path"].string
            if !path.isEmpty, let current = sessionPath, current != path {
                startAfresh(with: m, path: path)
                return
            }
            if !path.isEmpty { sessionPath = path }
        }
        if m.opening {
            // A snapshot is a run of opening messages; one following a change, or naming a
            // topic this run already gave, is the next snapshot.
            if snapshotTopics.map({ $0.contains(m.topic) }) ?? true { beginSnapshot(at: m.utc) }
            snapshotTopics?.insert(m.topic)
            snapshotRun.append(m)
            receiveSnapshot(m)
        } else {
            snapshotTopics = nil
            snapshotRun = []
            inFirstSnapshot = false
            guard let start = streamStart else { return }  // before the first snapshot
            state.apply(topic: m.topic, delta: m.json)
            merged[m.topic] = TopicMerge.merge(merged[m.topic] ?? .null, m.json)
            if firstChange[m.topic] == nil { firstChange[m.topic] = deltas[m.topic]?.count ?? 0 }
            deltas[m.topic, default: []].append(StreamLine(offsetMs: max(F1Values.sub(m.utc, start), 0), json: m.json))
        }
    }

    /// SessionInfo named another session: nothing so far belongs to it. A snapshot naming it
    /// becomes the new feed's first, with the topics it already gave; a change waits for the
    /// next snapshot.
    private mutating func startAfresh(with m: RecordedMessage, path: String) {
        let run = m.opening && snapshotTopics.map({ !$0.contains(m.topic) }) == true ? snapshotRun : []
        self = LiveFeed()
        guard m.opening else {
            sessionPath = path
            return
        }
        for r in run + [m] { apply(r) }
    }

    private mutating func beginSnapshot(at utc: UTCms) {
        snapshotTopics = []
        snapshotRun = []
        inFirstSnapshot = streamStart == nil
        if streamStart == nil { streamStart = F1Values.sub(utc, Self.headStartMs) }
        state = TopicState()
        folds = nil
    }

    private mutating func receiveSnapshot(_ m: RecordedMessage) {
        guard let start = streamStart else { return }
        let value = TopicMerge.merge(.null, m.json)
        let offset = max(F1Values.sub(m.utc, start), 0)
        state.apply(topic: m.topic, delta: m.json)
        if let before = merged[m.topic] {
            if let patch = TopicPatch.delta(from: before, to: value) {
                deltas[m.topic, default: []].append(StreamLine(offsetMs: offset, json: patch))
            }
        } else if inFirstSnapshot {
            // The topic's first line, before any change: at the stream's start.
            opening[m.topic] = StreamLine(offsetMs: 0, json: m.json)
        } else {
            // First named by a later snapshot: from then on, not before.
            lateStart.insert(m.topic)
            deltas[m.topic, default: []].append(StreamLine(offsetMs: offset, json: m.json))
        }
        merged[m.topic] = value
    }

    /// A topic's lines, as the archive parsers read them: the opening state (or the archive's
    /// session before joining), then the changes. Offsets never go back: one before the line
    /// ahead of it (F1's clock against the phone's, at a snapshot) takes that line's.
    public func lines(_ topic: String) -> [StreamLine] {
        let live = deltas[topic] ?? []
        var out: [StreamLine]
        if let t = topped[topic] {
            out = t.lines + live[min(t.from, live.count)...]
        } else {
            out = (opening[topic].map { [$0] } ?? []) + live
        }
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
            + (TimingSessionInfo.isRace(type: type) ? ["LapCount"] : []) + ["ExtrapolatedClock", "WeatherData"]
    }

    /// The topics `session()` reads.
    static let sessionTopics = ["Position.z", "TimingData", "TimingAppData", "LapCount", "ExtrapolatedClock",
                                "WeatherData", "TrackStatus", "RaceControlMessages", "SessionStatus"]
    /// The topics whose timelines `session()` keeps between calls (the costly ones: the rest are
    /// a few hundred lines a race and are built afresh).
    static let foldedTopics = ["Position.z", "TimingData", "TimingAppData"]

    /// The session so far, built by the archive's parsers. `drivers` and `info`, when given,
    /// stand in for the feed's own DriverList and SessionInfo. Nil before the first snapshot
    /// or without session info. Unlike the archive, a session without car positions is still
    /// returned (empty `positions`): the timing works, and the app says F1 isn't sending them.
    ///
    /// Car positions, timing and stints are kept between calls, and each call adds only the
    /// lines that came since the last (lines only ever add up, except at a top-up, a later
    /// snapshot or a new session, which start them again): the session is the one a fresh
    /// feed would build, at a cost that doesn't grow with the race. The caller still decides
    /// how often (Android: 10 s).
    public mutating func session(drivers: [String: DriverInfo]? = nil, info: TimingSessionInfo? = nil) -> LoadedSession? {
        guard let start = streamStart,
              let info = info ?? TimingSessionInfo.parse(state.topics["SessionInfo"] ?? .null)
        else { return nil }
        var topics: [String: [StreamLine]] = [:]
        for topic in Self.sessionTopics { topics[topic] = lines(topic) }
        func of(_ topic: String) -> [StreamLine] { topics[topic] ?? [] }
        // Taken out while it is added to, so its histories are changed in place.
        var kept = folds ?? Folds(streamStart: start)
        folds = nil
        kept.positions.take(of("Position.z"))
        kept.timing.take(of("TimingData"))
        kept.stints.take(of("TimingAppData"))
        folds = kept
        let optional = Self.optionalTopics(type: info.type)
        return LoadedSession(
            info: info,
            drivers: drivers ?? Drivers.parse(state.topics["DriverList"] ?? .null),
            streamStart: start,
            positions: kept.positions.builder.series,
            timing: kept.timing.builder.timeline,
            stints: kept.stints.builder.timeline,
            header: HeaderTimeline.build(lapCount: of("LapCount"), clock: of("ExtrapolatedClock"),
                                         weather: of("WeatherData"), streamStart: start),
            flags: TrackFlags.build(trackStatus: of("TrackStatus"), raceControl: of("RaceControlMessages"),
                                    streamStart: start, gmtOffsetSeconds: info.gmtOffsetSeconds),
            sessionStatus: SessionStatusTimeline.build(lines: of("SessionStatus"), streamStart: start,
                                                       snapshotLines: snapshotLines("SessionStatus")),
            missing: optional.filter { of($0).isEmpty }
        )
    }

    /// Which of `topic`'s lines (`lines(topic)`) are only the state on joining, not a change at
    /// their time: the opening snapshot (at the stream's start), the snapshot that first named
    /// the topic after joining, or, after a top-up that didn't meet the live lines, what the
    /// archive lacked of the snapshot.
    func snapshotLines(_ topic: String) -> Set<Int> {
        if let t = topped[topic] { return t.patchIndex.map { [$0] } ?? [] }
        return opening[topic] != nil || lateStart.contains(topic) ? [0] : []
    }

    /// How many of `topic`'s lines `session()` has read since it last started that topic again
    /// (for checks: each line once).
    func folded(_ topic: String) -> Int {
        switch topic {
        case "Position.z": return folds?.positions.added ?? 0
        case "TimingData": return folds?.timing.added ?? 0
        case "TimingAppData": return folds?.stints.added ?? 0
        default: return 0
        }
    }

    /// The timelines `session()` keeps, each with the lines it has read.
    struct Folds: Sendable {
        var positions: LineFold<PositionSeries.Builder>
        var timing: LineFold<TimingTimeline.Builder>
        var stints: LineFold<StintTimeline.Builder>

        init(streamStart: UTCms) {
            positions = LineFold(streamStart: streamStart)
            timing = LineFold(streamStart: streamStart)
            stints = LineFold(streamStart: streamStart)
        }
    }

    /// How far apart in time a live change and its archive line may be found (the archive's
    /// start is a heartbeat estimate; the snapshot is stamped by the phone).
    static let seamWindowMs = Backfill.completeGapMs
    /// How far before a live change the archive's copy of it may be timed. A live change
    /// carries F1's own time (the feed message's third argument); the archive times a line at
    /// its start (the upper median of the first 50 heartbeats' `Utc − offset`) plus the line's
    /// offset. So a line's archive time less its true UTC is minus the departure of the beats
    /// around it from that median, and only a positive departure (the archive's times running
    /// behind, earlier) can make an archive look short of a change it holds.
    ///
    /// Measured over the São Paulo race's and qualifying's Heartbeat files (leaving out the
    /// beats written as the archive closes, minutes off), departures run from −2.1 s (the
    /// archive up to 2.1 s ahead, later) to these, behind:
    /// - race, while it ran: up to +208 ms (the beat at 02:00:35.011), 11 % of beats behind
    ///   at all;
    /// - qualifying, from Q1's start to Q3's end: up to +160 ms, 15 % of beats behind;
    /// - before the sessions, when users often join: up to +282 ms (race) and +414 ms
    ///   (qualifying, the beat at 00:12:44.600, 36 s before Q1 started).
    ///
    /// 1 s covers the worst of them 2.4 times over, and stays well under the 3.7 s at which
    /// F1 soonest repeats an identical line. An archive is taken to reach a live change only
    /// when its last line is no more than this before the change, and to hold it only in a
    /// line no more than this before it.
    static let seamToleranceMs: Int64 = 1_000

    /// Tops the feed up from F1's archive (Android's backfill), so nothing before the seam is
    /// lost and nothing across it counts twice. For each topic (archive lines are offsets from
    /// `archiveStart`):
    ///
    /// - When the archive reaches the topic's first live change (its last line is at most
    ///   `seamToleranceMs` before it) and holds it (the same message, within `seamWindowMs`,
    ///   nearest), and the match checks out, the archive's lines before it come first, then
    ///   the live lines from that change on. The archive and live timing are then one stream,
    ///   whatever the snapshot's stamp says. F1 repeats some lines within seconds, so the match
    ///   may be an earlier copy; it checks out when
    ///   - it is itself at most `seamToleranceMs` before the change, and so is the archive's
    ///     next line, if any (an earlier copy is further back, or has the archive's next
    ///     lines before the change), and
    ///   - the archive merged up to it is the state the live lines hold just before the change
    ///     (an earlier copy leaves out what came after it). There is nothing to compare at
    ///     the archive's first line (the archive has nothing before the change, and the live
    ///     lines stand as they are) or for a topic first seen as a change.
    /// - Otherwise (the archive lags, the match doesn't check out, or the topic hasn't changed
    ///   since joining), the archive's
    ///   lines before the snapshot (or the first live change, if earlier) come first, then the
    ///   difference from their state to the snapshot's, then the live lines. The difference is
    ///   empty when they agree.
    ///
    /// Race control's archive messages also given live (same Utc and Message) are left out of
    /// the archive's lines. A topic with no archive lines before the seam keeps its live lines.
    /// Called again with a fuller archive, the newer lines replace the older.
    public mutating func topUp(archive: [String: [StreamLine]], archiveStart: UTCms) {
        guard let start = streamStart, let joined = joinedAt else { return }
        // The lines before the join change: `session()` reads every topic afresh.
        folds = nil
        for (topic, archived) in archive where LiveRecording.records(topic) {
            let archiveLines = Backfill.rebase(archived, archiveStart: archiveStart, newStart: start, until: .max)
            let live = deltas[topic] ?? []
            var archivePart: [StreamLine] = []
            var patch: StreamLine?
            var from = 0
            if let k = firstChange[topic], let j = seamMatch(topic, live: live, change: k, archive: archiveLines) {
                archivePart = Array(archiveLines[..<j])
                from = k
            } else {
                var anchor: (state: JSONValue, offset: Int64)?
                if let open = opening[topic] {
                    anchor = (TopicMerge.merge(.null, open.json), F1Values.sub(joined, start))
                } else if lateStart.contains(topic), let first = live.first {
                    anchor = (TopicMerge.merge(.null, first.json), first.offsetMs)
                    from = 1
                }
                let cut = min(anchor?.offset ?? .max, from < live.count ? live[from].offsetMs : .max)
                archivePart = Array(archiveLines.prefix { $0.offsetMs < cut })
                if let anchor, !archivePart.isEmpty {
                    let reached = archivePart.reduce(JSONValue.null) { TopicMerge.merge($0, $1.json) }
                    patch = TopicPatch.delta(from: reached, to: anchor.state).map { StreamLine(offsetMs: cut, json: $0) }
                }
            }
            guard !archivePart.isEmpty else {
                topped[topic] = nil
                continue
            }
            if topic == "RaceControlMessages" {
                let given = Set(((patch.map { [$0] } ?? []) + live[from...]).flatMap(Self.messageKeys))
                if !given.isEmpty { archivePart = archivePart.map { Self.dropping(given, from: $0) } }
            }
            topped[topic] = Topped(lines: archivePart + (patch.map { [$0] } ?? []), from: from,
                                   patchIndex: patch == nil ? nil : archivePart.count)
        }
    }

    /// The archive line that is the topic's first live change (`live[k]`), when the archive
    /// reaches it, holds it, and the match checks out (see `topUp`); nil otherwise.
    private func seamMatch(_ topic: String, live: [StreamLine], change k: Int, archive: [StreamLine]) -> Int? {
        let change = live[k]
        // The archive's times run at most the tolerance behind: nothing earlier is the change
        // or follows it.
        let earliest = F1Values.sub(change.offsetMs, Self.seamToleranceMs)
        guard let last = archive.last, last.offsetMs >= earliest,
              let j = Self.match(change, in: archive),
              // An earlier copy is further back,
              archive[j].offsetMs >= earliest,
              // or has the archive's next lines before the change (whatever they merge to).
              j + 1 == archive.count || archive[j + 1].offsetMs >= earliest
        else { return nil }
        // At the archive's first line there is nothing before it to compare, and neither is
        // there for a topic first seen as a change (no live state before it).
        guard j > 0, let expected = expectedState(topic, before: k) else { return j }
        let reached = archive[..<j].reduce(JSONValue.null) { TopicMerge.merge($0, $1.json) }
        return TopicPatch.delta(from: reached, to: expected) == nil ? j : nil
    }

    /// What a topic's live lines merge to before its `k`th delta: its opening (or the later
    /// snapshot that first named it) and any snapshot differences since. Nil when nothing came
    /// before.
    private func expectedState(_ topic: String, before k: Int) -> JSONValue? {
        let earlier = (opening[topic].map { [$0] } ?? []) + (deltas[topic] ?? []).prefix(k)
        guard !earlier.isEmpty else { return nil }
        return earlier.reduce(JSONValue.null) { TopicMerge.merge($0, $1.json) }
    }

    /// The archive line that is `line` (the same message), nearest in time within
    /// `seamWindowMs`.
    static func match(_ line: StreamLine, in archive: [StreamLine]) -> Int? {
        var best: (index: Int, distance: Int64)?
        var normalized: JSONValue?
        for (i, a) in archive.enumerated() {
            let distance = abs(F1Values.sub(a.offsetMs, line.offsetMs))
            guard distance <= seamWindowMs, distance < best?.distance ?? .max else { continue }
            if a.json != line.json {
                if normalized == nil { normalized = TopicMerge.merge(.null, line.json) }
                guard TopicMerge.merge(.null, a.json) == normalized else { continue }
            }
            best = (i, distance)
        }
        return best?.index
    }

    /// A race control line's messages, each as its Utc and text.
    static func messageKeys(_ line: StreamLine) -> [String] {
        F1Values.ordered(line.json["Messages"]).map { $0["Utc"].string + "\u{1F}" + $0["Message"].string }
    }

    /// The line without the messages whose keys are in `keys`.
    static func dropping(_ keys: Set<String>, from line: StreamLine) -> StreamLine {
        func kept(_ m: JSONValue) -> Bool { !keys.contains(m["Utc"].string + "\u{1F}" + m["Message"].string) }
        guard case .object(var members) = line.json else { return line }
        switch members["Messages"] {
        case .array(let items)?:
            let left = items.filter(kept)
            guard left.count != items.count else { return line }
            members["Messages"] = .array(left)
        case .object(let entries)?:
            let left = entries.filter { kept($0.value) }
            guard left.count != entries.count else { return line }
            members["Messages"] = .object(left)
        default:
            return line
        }
        return StreamLine(offsetMs: line.offsetMs, json: .object(members))
    }
}

/// A parser that takes a topic's lines one at a time (`PositionSeries.Builder`,
/// `TimingTimeline.Builder`, `StintTimeline.Builder`).
protocol LineFolder: Sendable {
    init(streamStart: UTCms)
    mutating func add(_ line: StreamLine)
}

/// A `LineFolder` and how far into a topic's lines it has read. Given the lines again, it reads
/// only those past the ones it has; if those aren't the lines it read (fewer, or the last one
/// differs), it starts again from the first.
struct LineFold<Builder: LineFolder>: Sendable {
    let streamStart: UTCms
    private(set) var builder: Builder
    /// Lines read: the first `consumed` of the lines last given.
    private(set) var consumed = 0
    /// Lines read since it last started (for checks).
    private(set) var added = 0
    private var last: StreamLine?

    init(streamStart: UTCms) {
        self.streamStart = streamStart
        builder = Builder(streamStart: streamStart)
    }

    mutating func take(_ lines: [StreamLine]) {
        if lines.count < consumed || (consumed > 0 && lines[consumed - 1] != last) {
            self = LineFold(streamStart: streamStart)
        }
        for line in lines[consumed...] { builder.add(line) }
        added += lines.count - consumed
        consumed = lines.count
        last = lines.last
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

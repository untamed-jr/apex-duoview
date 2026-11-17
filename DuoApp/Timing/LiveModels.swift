import F1TV
import Foundation
import Library
import LiveTiming

// Live timing's plain values and pure rules (build 15): no SwiftUI, no UIKit, no networking, so
// all of it can be read and checked on its own. The connection (`LiveConnection`), the recorder
// (`LiveRecorder`) and `TimingController`'s live mode use them.

// MARK: - SignalR frames across WebSocket messages

/// Joins SignalR frames that F1 splits across WebSocket messages. `SignalR.frames` reads only
/// frames ending in 0x1E within the data it is given; whatever follows the last 0x1E waits here
/// for the next message. A subscribe result mid-race runs to hundreds of kilobytes and can come
/// in several messages.
struct SignalRFrameBuffer: Sendable {
    /// More than this waiting with no frame end is no SignalR the app can read: it is dropped
    /// rather than grown without limit.
    static let maxPending = 32 << 20

    private(set) var pending = Data()

    /// The complete frames once `data` is added, in order.
    mutating func append(_ data: Data) -> [JSONValue] {
        pending.append(data)
        guard let end = pending.lastIndex(of: 0x1E) else {
            if pending.count > Self.maxPending { pending = Data() }
            return []
        }
        let next = pending.index(after: end)
        let complete = pending.subdata(in: pending.startIndex..<next)
        pending = pending.subdata(in: next..<pending.endIndex)
        return SignalR.frames(complete)
    }

    /// A new connection starts with nothing waiting.
    mutating func reset() {
        pending = Data()
    }
}

// MARK: - The link's state

/// Where the live connection stands.
enum LiveLinkPhase: Equatable, Sendable {
    /// Nobody is listening.
    case idle
    /// Negotiating, opening the socket or waiting for the subscribe result.
    case connecting
    /// The subscribe result arrived: changes are flowing.
    case subscribed
    /// The socket closed or failed; the next try comes after `LiveLink.reconnectDelay`.
    case dropped
}

/// The connection's state machine, kept apart from the socket so it can be checked: which try is
/// current (a socket from an earlier try never feeds after a reconnect), the status line, how
/// long to wait before the next try, and when a silent socket counts as dead.
struct LiveLink: Equatable, Sendable {
    /// SignalR's keep-alive: a ping this often.
    static let pingInterval: Duration = .seconds(15)
    /// The wait before trying again after a drop.
    static let reconnectDelay: Duration = .seconds(5)
    /// After this many refusals (401/403) in a row the tries slow to `refusedDelay`: a refusal
    /// rarely clears in 5 s, and F1 shouldn't be asked every 5 s for hours. Never a sign-out.
    static let refusalsBeforeSlowing = 3
    static let refusedDelay: Duration = .seconds(60)
    /// Nothing at all from F1 for this long (no change, no ping) means the socket is dead even
    /// if it hasn't said so: SignalR's own server timeout, twice the keep-alive.
    static let silenceLimitMs: Int64 = 30_000

    private(set) var phase: LiveLinkPhase = .idle
    /// Bumped by every try: messages are taken only from the current one.
    private(set) var attempt = 0
    /// A subscribe result has arrived in this run (since the first listener).
    private(set) var everSubscribed = false
    /// Refusals in a row, reset by a subscribe result.
    private(set) var refusals = 0
    /// A planned new try after a subscribe result (the car data choice changed, or a new session
    /// came as a change): listeners keep hearing subscribed until it subscribes or drops, so the
    /// map never flashes "dropped" for it.
    private(set) var restarting = false

    /// What listeners hear: the phase, except subscribed through a planned restart.
    var reported: LiveLinkPhase {
        restarting ? .subscribed : phase
    }

    /// A new try starts (`restart`: a planned one, straight after the last); returns its number.
    mutating func connecting(restart: Bool = false) -> Int {
        let quiet = phase == .subscribed || restarting
        attempt += 1
        phase = .connecting
        restarting = restart && quiet
        return attempt
    }

    /// The subscribe result of try `attempt` arrived. False (and nothing changes) for an old try.
    @discardableResult
    mutating func subscribed(attempt: Int) -> Bool {
        guard attempt == self.attempt, phase != .idle else { return false }
        phase = .subscribed
        everSubscribed = true
        refusals = 0
        restarting = false
        return true
    }

    /// Try `attempt` ended (`refused`: F1 answered 401/403). Returns the wait before the next try,
    /// or nil for an old try or once stopped.
    mutating func dropped(attempt: Int, refused: Bool = false) -> Duration? {
        guard attempt == self.attempt, phase != .idle else { return nil }
        phase = .dropped
        restarting = false
        if refused { refusals += 1 }
        return refusals >= Self.refusalsBeforeSlowing ? Self.refusedDelay : Self.reconnectDelay
    }

    /// The last listener left: everything stops and the next listener starts afresh.
    mutating func stopped() {
        attempt += 1
        phase = .idle
        everSubscribed = false
        refusals = 0
        restarting = false
    }

    /// Whether a socket last heard from at `lastHeard` is dead at `now` (both UTC ms).
    static func silent(lastHeard: UTCms, now: UTCms) -> Bool {
        LiveMath.sub(now, lastHeard) > silenceLimitMs
    }
}

// MARK: - Status lines

/// The live status lines (Global Constraints) and the catching-up label, for the map's note.
enum LiveNote {
    static let connecting = "Connecting to live timing\u{2026}"
    static let dropped = "Live timing dropped \u{2014} reconnecting\u{2026}"
    static let noPositions = "Live timing is connected, but F1 isn't sending car positions"
    /// A picture before the feed joined, while the archive hasn't filled it in yet (the state on
    /// joining stands in): shown like "Timing estimated".
    static let catchingUp = "Timing catching up"

    /// The line for the link: connecting until the first subscribe result, then "dropped" while a
    /// later try is under way; nil while subscribed or idle.
    static func link(_ phase: LiveLinkPhase, everSubscribed: Bool) -> String? {
        switch phase {
        case .idle, .subscribed: return nil
        case .connecting: return everSubscribed ? dropped : connecting
        case .dropped: return everSubscribed ? dropped : connecting
        }
    }

    /// Picture time `t` shows timing the feed never received:
    /// - before the feed joined (`joinedAt`, where the state on joining stands in), until the
    ///   archive top-up reaches it (`archiveReach`, the archive's last car position; nil before
    ///   any top-up);
    /// - inside a recording gap (`gaps`: a reconnect, or the same session reopened, where the
    ///   last state before it stands in). `LiveFeed.topUp` puts the archive only before the
    ///   join (each topic up to its first live line), so a gap after the join is never filled
    ///   and stays labelled, whatever the archive's reach.
    static func catchingUp(at t: UTCms, joinedAt: UTCms?, archiveReach: UTCms?, gaps: [LiveGap] = []) -> Bool {
        if let joinedAt, t < joinedAt { return archiveReach.map { t > $0 } ?? true }
        return gaps.contains { $0.contains(t) }
    }

    /// The note over the live map, most important first: the link, then (`hasSession` false: no
    /// session built yet, even after the subscribe result) connecting, then no car positions,
    /// then catching up. Nil when all is well.
    static func note(phase: LiveLinkPhase, everSubscribed: Bool, hasSession: Bool = true, hasPositions: Bool,
                     pictureTime: UTCms?, joinedAt: UTCms?, archiveReach: UTCms?, gaps: [LiveGap] = []) -> String? {
        if let line = link(phase, everSubscribed: everSubscribed) { return line }
        if !hasSession { return connecting }
        if phase == .subscribed, !hasPositions { return noPositions }
        if let t = pictureTime, catchingUp(at: t, joinedAt: joinedAt, archiveReach: archiveReach, gaps: gaps) {
            return catchingUp
        }
        return nil
    }
}

/// A stretch the live feed holds no messages for: from the last message before a later
/// snapshot (a reconnect, or the same session reopened) to that snapshot. The state from before
/// it stands in until the archive fills it in.
struct LiveGap: Equatable, Sendable {
    /// Shorter than this is no gap (the snapshot is stamped by the phone, changes by F1).
    static let minimumMs: Int64 = 3_000

    var from: UTCms
    var to: UTCms

    func contains(_ t: UTCms) -> Bool {
        t > from && t < to
    }
}

/// Finds the recording gaps in the messages as a `LiveFeed` takes them: a snapshot (a run of
/// opening messages) after the first starts a gap from the last message before it. A new
/// session (another SessionInfo `Path`) forgets them: its feed starts afresh.
struct LiveGapFinder: Equatable, Sendable {
    private(set) var gaps: [LiveGap] = []
    /// The newest message's time.
    private var last: UTCms?
    /// The topics of the opening run being received; nil once a change follows it.
    private var run: Set<String>?
    private var sawSnapshot = false

    /// Notes a message (recorded topics only) before the feed applies it.
    mutating func note(_ m: RecordedMessage) {
        if m.opening {
            let newRun = run.map { $0.contains(m.topic) } ?? true
            if newRun {
                if sawSnapshot, let last, LiveMath.sub(m.utc, last) > LiveGap.minimumMs {
                    gaps.append(LiveGap(from: last, to: m.utc))
                }
                run = []
                sawSnapshot = true
            }
            run?.insert(m.topic)
        } else {
            run = nil
        }
        last = max(last ?? m.utc, m.utc)
    }

    /// The feed moved on to another session, or emptied: no gaps from the one before.
    mutating func newSession() {
        gaps = []
        if run == nil { sawSnapshot = false }
    }
}

// MARK: - Rebuilding the live session

/// How often the live session is rebuilt (`LiveFeed.session()` parses every line again on each
/// call). Chosen: at most every 2 s, stretched to 4 times as long as the last rebuild took, up to
/// 5 s. The 2 Hz tick reads the cached `LoadedSession` meanwhile. Picture time runs at least the
/// 7 s offset (plus the stream's own delay) behind the newest timing, so a session up to 5 s old
/// still reaches it. Android reparsed every 10 s. Only when something changed, and never two at
/// once; the first snapshot, a session change and a top-up rebuild at once.
struct LiveRebuildClock: Equatable, Sendable {
    static let minIntervalMs: Int64 = 2_000
    static let maxIntervalMs: Int64 = 5_000
    static let costFactor: Int64 = 4

    private(set) var lastStart: Int64?
    private(set) var lastDuration: Int64 = 0

    /// The wait after a rebuild that took `lastDuration`.
    var interval: Int64 {
        min(max(lastDuration * Self.costFactor, Self.minIntervalMs), Self.maxIntervalMs)
    }

    /// Whether to rebuild at `now` (a monotonic ms clock): something `changed`, and either it is
    /// `urgent` or the interval has passed since the last rebuild began.
    func due(now: Int64, changed: Bool, urgent: Bool) -> Bool {
        guard changed else { return false }
        if urgent { return true }
        guard let lastStart else { return true }
        return now - lastStart >= interval
    }

    /// A rebuild ran from `start` to `end`.
    mutating func rebuilt(start: Int64, end: Int64) {
        lastStart = start
        lastDuration = max(end - start, 0)
    }
}

// MARK: - Live car data

/// The live CarData.z samples behind the speed readouts and the console. `LiveFeed` leaves car
/// data out (and the recording never holds it), so it is decoded here as it arrives and kept for
/// the last 15 minutes: a rewind further back shows the readouts greyed, as a gap does.
struct LiveCarData: Sendable {
    static let keepMs: Int64 = 15 * 60_000
    /// The window handed to the 2 Hz tick reaches this far either side of picture time.
    static let windowMs: Int64 = 60_000

    private(set) var cars: [String: [CarSample]] = [:]
    /// The newest sample's time.
    private(set) var newest: UTCms?

    /// One live CarData.z message (base64 deflate, as the archive's lines).
    mutating func add(_ message: RecordedMessage) {
        let parsed = CarDataWindow.parse(lines: [StreamLine(offsetMs: 0, json: message.json)])
        add(parsed)
    }

    /// Samples by car, oldest first; one not later than the car's last is dropped.
    mutating func add(_ parsed: [String: [CarSample]]) {
        for (number, samples) in parsed {
            var list = cars[number] ?? []
            for sample in samples where list.last.map({ sample.t > $0.t }) ?? true {
                list.append(sample)
                if newest.map({ sample.t > $0 }) ?? true { newest = sample.t }
            }
            cars[number] = list
        }
        trim()
    }

    /// Each car's samples within `windowMs` of `t`, oldest first; cars with none are left out.
    func window(around t: UTCms) -> [String: [CarSample]] {
        let from = LiveMath.sub(t, Self.windowMs)
        let to = LiveMath.add(t, Self.windowMs)
        var out: [String: [CarSample]] = [:]
        for (number, list) in cars {
            let lo = Self.firstIndex(in: list, atOrAfter: from)
            let hi = Self.firstIndex(in: list, atOrAfter: LiveMath.add(to, 1))
            if lo < hi { out[number] = Array(list[lo..<hi]) }
        }
        return out
    }

    /// Forgets what is older than `keepMs` before the newest sample, once a minute's worth has
    /// piled up past it (so it isn't done on every message).
    private mutating func trim() {
        guard let newest else { return }
        let cut = LiveMath.sub(newest, Self.keepMs)
        for (number, list) in cars {
            guard let first = list.first, LiveMath.sub(cut, first.t) > 60_000 else { continue }
            let keep = Self.firstIndex(in: list, atOrAfter: cut)
            cars[number] = Array(list[keep...])
        }
    }

    static func firstIndex(in list: [CarSample], atOrAfter t: UTCms) -> Int {
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid].t < t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

// MARK: - The live session, off the main actor

/// What a live connection hands its listeners: messages (the session's recording first, then
/// live), and the link's state whenever it changes.
enum LiveEvent: Sendable, Equatable {
    case message(RecordedMessage)
    case link(LiveLinkPhase, everSubscribed: Bool)
}

/// The live session as of a refresh.
enum LiveSessionUpdate: Sendable {
    /// No rebuild this time: keep the session in hand.
    case unchanged
    case rebuilt(LoadedSession, LapStates)
    /// The feed holds nothing (before the first snapshot, or emptied by a session change that
    /// came as a change): no session.
    case cleared
}

/// One refresh's result, plain values for the main actor.
struct LiveRefresh: Sendable {
    var session: LiveSessionUpdate
    var phase: LiveLinkPhase
    var everSubscribed: Bool
    var joinedAt: UTCms?
    /// The SessionInfo `Path` the feed holds (the archive folder for the top-up).
    var sessionPath: String?
    /// SessionInfo's `Key`, to check the feed is the watched session.
    var sessionKey: Int?
    /// How far the archive top-up reaches (its last car position); nil before one.
    var archiveReach: UTCms?
    /// The car data within a minute of picture time.
    var cars: [String: [CarSample]]
    /// The recording's gaps (reconnects, the session reopened), oldest first.
    var gaps: [LiveGap] = []
}

/// Owns one attach's `LiveFeed` off the main actor: every message is applied here, in order,
/// and the session is rebuilt here (throttled by `LiveRebuildClock`), so a rebuild never runs
/// on a copy that misses messages applied meanwhile, and the main actor never parses.
actor LiveSessionBuilder {
    private var feed = LiveFeed()
    private var carData = LiveCarData()
    private var clock = LiveRebuildClock()
    private var changed = false
    private var urgent = false
    private var phase: LiveLinkPhase = .connecting
    private var everSubscribed = false
    private var archiveReach: UTCms?
    private var lastPath: String?
    private var gapFinder = LiveGapFinder()
    /// The feed had a session at the last rebuild (so emptying it is reported once).
    private var hadSession = false
    private let now: @Sendable () -> Int64

    /// `now`: a monotonic clock in ms, for the throttle.
    init(now: @escaping @Sendable () -> Int64 = LiveSessionBuilder.monotonicMs) {
        self.now = now
    }

    static let monotonicMs: @Sendable () -> Int64 = {
        let elapsed = ContinuousClock.now - LiveSessionBuilder.origin
        return elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
    }

    private static let origin = ContinuousClock.now

    func receive(_ event: LiveEvent) {
        switch event {
        case .link(let phase, let ever):
            self.phase = phase
            everSubscribed = ever
        case .message(let m):
            if m.topic == "CarData.z" {
                carData.add(m)
                return
            }
            guard LiveRecording.records(m.topic) else { return }
            let started = feed.streamStart != nil
            gapFinder.note(m)
            feed.apply(m)
            changed = true
            if !started, feed.streamStart != nil { urgent = true }
            if feed.sessionPath != lastPath {
                // Another session: the top-up starts again for it.
                lastPath = feed.sessionPath
                archiveReach = nil
                gapFinder.newSession()
                urgent = true
            }
        }
    }

    /// Several events in order (the recording's replay comes in one go).
    func receive(_ events: [LiveEvent]) {
        for event in events { receive(event) }
    }

    /// Puts the archive's session before the join (`LiveFeed.topUp`); `reach` is the archive's
    /// last car position. Ignored when the feed has moved on to another session meanwhile.
    func topUp(archive: [String: [StreamLine]], archiveStart: UTCms, reach: UTCms?, sessionPath: String) {
        guard feed.sessionPath == sessionPath, feed.streamStart != nil else { return }
        feed.topUp(archive: archive, archiveStart: archiveStart)
        if let reach { archiveReach = max(archiveReach ?? reach, reach) }
        changed = true
        urgent = true
    }

    /// The session (rebuilt when due and `wanted`, or when there is none yet), the link and the
    /// car data around `pictureTime`.
    func refresh(pictureTime: UTCms?, wanted: Bool) -> LiveRefresh {
        var update = LiveSessionUpdate.unchanged
        let start = now()
        if feed.streamStart == nil {
            if hadSession { update = .cleared }
            hadSession = false
            changed = false
            urgent = false
        } else if (wanted || !hadSession), clock.due(now: start, changed: changed, urgent: urgent || !hadSession) {
            changed = false
            urgent = false
            if let session = feed.session() {
                update = .rebuilt(session, LapStates(session: session))
                hadSession = true
            }
            clock.rebuilt(start: start, end: now())
        }
        let info = feed.state.topics["SessionInfo"].flatMap { TimingSessionInfo.parse($0) }
        return LiveRefresh(
            session: update, phase: phase, everSubscribed: everSubscribed, joinedAt: feed.joinedAt,
            sessionPath: feed.sessionPath, sessionKey: info?.key, archiveReach: archiveReach,
            cars: pictureTime.map { carData.window(around: $0) } ?? [:], gaps: gapFinder.gaps)
    }
}

// MARK: - Which session

enum LiveSessionMatch {
    /// Whether the live feed's session (SessionInfo `Key`) is the watched video's: live timing
    /// serves whatever F1 session is current, which needn't be the one on screen. When either
    /// key is unknown it is taken as the same (the item passed `TimingRef.isSession`).
    static func matches(feedKey: Int?, ref: TimingRef) -> Bool {
        guard let feedKey, let text = ref.sessionKey?.trimmingCharacters(in: .whitespaces), let key = Int(text)
        else { return true }
        return feedKey == key
    }
}

// MARK: - The recording's files

/// Where live recordings go and when they are old: `Caches/live/{sessionKey}.txt`, deleted after
/// 7 days.
enum LiveRecordingFiles {
    static let keepFor: TimeInterval = 7 * 24 * 3600
    /// Flushed this often.
    static let flushInterval: Duration = .seconds(2)
    /// How much of the file's start `LiveRecording.start` reads.
    static let headBytes = 4096

    /// The file's name for a session: its key, else its folder with anything but letters and
    /// digits made "-".
    static func fileName(sessionKey: Int?, path: String) -> String {
        if let sessionKey { return "\(sessionKey).txt" }
        let name = String(path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
        return (name.isEmpty ? "session" : name) + ".txt"
    }

    static func isOld(written: Date, now: Date) -> Bool {
        now.timeIntervalSince(written) > keepFor
    }
}

// MARK: - The next live programme

/// The next-live offer while a live programme is watched (spec 0.95): the 60 s checks' state.
/// - The first successful "live now" fetch after opening only notes what was live then
///   (`liveAtStart`): nothing is offered from a failed or missing first fetch.
/// - The watched broadcast counts as ended only when a successful fetch no longer lists it,
///   having listed it before.
/// - "Not now" is remembered for that programme while the app runs.
/// A resumed bookmark's item. `WatchBookmark.live` says only that the programme was live when
/// the bookmark was saved: the item is live (live timing, the next-live check) only when F1 TV's
/// live-now list has it now. Yesterday's race resumed from Recents is a replay, with archive
/// timing. The video's details carry no live flag, so the list is the live-now signal.
enum LiveResume {
    /// Whether to ask F1 TV's live-now list at all: only a bookmark saved live can be live now.
    static func needsCheck(_ bookmark: WatchBookmark) -> Bool {
        bookmark.live
    }

    /// Live now: saved live and in F1 TV's live-now list (`liveNow`; nil when it couldn't be
    /// read, which counts as not live).
    static func isLive(_ bookmark: WatchBookmark, liveNow: [CatalogItem]?) -> Bool {
        bookmark.live && (liveNow?.contains { $0.contentId == bookmark.contentId } ?? false)
    }

    /// The item to play. A bookmark keeps no metadata: the video's details say where its timing is.
    static func item(_ bookmark: WatchBookmark, detail: VideoDetail, isLive: Bool) -> CatalogItem {
        CatalogItem(
            contentId: bookmark.contentId,
            title: detail.title.isEmpty ? bookmark.title : detail.title,
            subtype: isLive ? "LIVE" : "",
            picturePath: bookmark.picturePath,
            timingRef: detail.timingRef)
    }
}

struct NextLiveState: Equatable, Sendable {
    static let checkInterval: Duration = .seconds(60)

    /// The live programme watched, and whether in multiview.
    private(set) var watching: Int?
    private(set) var multiview = false
    private(set) var liveAtStart: Set<Int>?
    private(set) var seenWatched = false
    private(set) var declined: Set<Int> = []
    /// What the prompt offers now.
    private(set) var offer: CatalogItem?

    /// A live programme started showing (or the mode changed). Watching the same one in another
    /// mode keeps what was learnt.
    mutating func watch(contentId: Int, multiview: Bool) {
        self.multiview = multiview
        guard watching != contentId else { return }
        watching = contentId
        liveAtStart = nil
        seenWatched = false
        offer = nil
    }

    /// Nothing live is watched: no checks, no prompt.
    mutating func stop() {
        watching = nil
        liveAtStart = nil
        seenWatched = false
        offer = nil
    }

    /// A successful fetch of F1 TV's "live now" list, in its order.
    mutating func checked(live: [CatalogItem]) {
        guard let watching else { return }
        let ids = Set(live.map(\.contentId))
        if ids.contains(watching) { seenWatched = true }
        guard let start = liveAtStart else {
            liveAtStart = ids
            return
        }
        let ended = seenWatched && !ids.contains(watching)
        let next = NextLive.pick(live: live, onScreen: watching, liveAtStart: start, declined: declined,
                                 watchedEnded: ended)
        if offer != next { offer = next }
    }

    /// "Not now": that programme isn't offered again.
    mutating func decline() {
        guard let offer else { return }
        declined.insert(offer.contentId)
        self.offer = nil
    }

    /// "Switch": the programme to open and whether in multiview; the prompt goes.
    mutating func accept() -> (item: CatalogItem, multiview: Bool)? {
        guard let offer else { return nil }
        self.offer = nil
        return (offer, multiview)
    }

    /// "Switch" couldn't open `item` (its details didn't load): the prompt comes back, unless
    /// the programme watched is no longer `watched`, a newer offer came meanwhile, or it was
    /// declined.
    mutating func restore(_ item: CatalogItem, watched: Int?) {
        guard let watching, watching == watched, offer == nil, !declined.contains(item.contentId) else { return }
        offer = item
    }
}

// MARK: - The pit circle's view

/// The map panel's two views.
enum MapPanelMode: String, Sendable {
    case map
    case pitCircle
}

/// What a pit circle build was made from: a build is kept while none of it changes.
struct PitCircleKey: Equatable, Sendable {
    /// `TimingController`'s loaded-session revision.
    var session: Int
    var t: UTCms
    var storedPitLossMs: Int?
    var selected: String?
    var toLeader: Bool
}

/// What the pit circle view draws at picture time, built off the main actor at the 2 Hz tick.
struct PitCircleViewState: Equatable, Sendable {
    /// The circle; nil with `message` saying why.
    var circle: PitCircleState?
    var message: String?
    /// The car tapped or held: every gap is measured to it, and its pit window shows.
    var selected: String?
    /// "If HAM stops now, out 2.1 s behind NOR".
    var pitWindow: String?
    /// "Pit loss 21.4 s · 6 stops", "Pit loss 23.1 s · kept for this circuit", "Pit loss 22.0 s".
    var lossText: String?
    /// Labels show the gap to the leader (the toggle), not to the car ahead.
    var toLeader: Bool

    /// Not a race: the circle needs time gaps.
    static let racesOnly = "The pit circle is for races."

    /// The circle at `t`. `storedPitLossMs`: this circuit's stored value. `selected`: the car
    /// tapped or held (ignored when the circle doesn't place it).
    static func make(at t: UTCms, session: LoadedSession, storedPitLossMs: Int?, selected: String?,
                     toLeader: Bool) -> PitCircleViewState {
        guard session.info.isRace else {
            return PitCircleViewState(circle: nil, message: racesOnly, selected: nil, pitWindow: nil, lossText: nil,
                                      toLeader: toLeader)
        }
        guard let circle = PitCircle.layout(at: t, session: session, storedPitLossMs: storedPitLossMs) else {
            let finished = session.timing.at(t).values.contains { ($0.numberOfLaps ?? 0) >= 1 }
            return PitCircleViewState(circle: nil, message: finished ? ConsoleText.circleNextLine : ConsoleText.circleStarts,
                                      selected: nil, pitWindow: nil, lossText: nil, toLeader: toLeader)
        }
        let chosen = selected.flatMap { number in circle.cars.contains { $0.number == number } ? number : nil }
        var window: String?
        if let chosen {
            window = PitCircle.rejoin(car: chosen, at: t, session: session, pitLossMs: circle.pitLossMs)?
                .text(car: chosen, session: session)
                ?? PitCircleText.noWindow(tla: session.drivers[chosen]?.tla ?? chosen)
        }
        return PitCircleViewState(circle: circle, message: nil, selected: chosen, pitWindow: window,
                                  lossText: PitCircleText.loss(circle, stored: storedPitLossMs != nil), toLeader: toLeader)
    }

    /// A car's label: with a car selected, its gap to that car ("+1.2", "-0.8"; the selected car
    /// shows its code); otherwise the toggle's gap, as DuoCore gives it.
    func label(_ car: PitCircleCar) -> String {
        if let selected, let mine = circle?.cars.first(where: { $0.number == selected }) {
            if car.number == selected { return car.tla }
            return PitCircleText.signed(car.gapToLeaderMs - mine.gapToLeaderMs)
        }
        return toLeader ? car.gapToLeader : car.gapToAhead
    }
}

/// The pit circle's texts.
enum PitCircleText {
    /// "Pit loss 21.4 s · 6 stops"; the stored value or the typical 22 s before any stop here.
    static func loss(_ circle: PitCircleState, stored: Bool) -> String {
        let value = "Pit loss \(seconds(circle.pitLossMs))"
        if circle.measuredStops > 0 {
            return value + " \u{00B7} \(circle.measuredStops) \(circle.measuredStops == 1 ? "stop" : "stops")"
        }
        return stored ? value + " \u{00B7} kept for this circuit" : value
    }

    /// A held car with no pit window now (in the pits, its gap unknown).
    static func noWindow(tla: String) -> String {
        "No pit window for \(tla) right now"
    }

    /// "21.4 s", to the nearest tenth.
    static func seconds(_ ms: Int) -> String {
        let tenths = (max(ms, 0) + 50) / 100
        return "\(tenths / 10).\(tenths % 10) s"
    }

    /// "+1.2" / "-0.8", to the nearest tenth.
    static func signed(_ ms: Int) -> String {
        let tenths = (abs(ms) + 50) / 100
        return "\(ms < 0 ? "-" : "+")\(tenths / 10).\(tenths % 10)"
    }
}

/// Where things sit on the circle: the finish at the top, clockwise in the direction of travel.
enum PitCircleGeometry {
    /// Room kept outside the ring for the cars' codes and gaps.
    static let labelRoom = 40.0
    /// The pit lane's inner arc, as a share of the ring's radius.
    static let laneShare = 0.72

    /// The ring's radius in a `width` × `height` box: as large as fits with the labels outside.
    static func radius(width: Double, height: Double) -> Double {
        max(min(width, height) / 2 - labelRoom, 12)
    }

    /// Each car's dot on the ring (the lane's arc for a car in the pits), in the box's space.
    static func dots(_ circle: PitCircleState, width: Double, height: Double) -> [(number: String, x: Double, y: Double)] {
        let r = radius(width: width, height: height)
        return circle.cars.map { car in
            let p = point(angle: car.angle, radius: car.inPit ? r * laneShare : r, cx: width / 2, cy: height / 2)
            return (car.number, p.x, p.y)
        }
    }

    /// The point at `angle` degrees (0 at the top, clockwise) on a circle of `radius` round
    /// (`cx`, `cy`), in a y-down space.
    static func point(angle: Double, radius: Double, cx: Double, cy: Double) -> (x: Double, y: Double) {
        let radians = angle * Double.pi / 180
        return (cx + radius * sin(radians), cy - radius * cos(radians))
    }

    /// The car whose dot is nearest (`x`, `y`) within `reach` points; nil when none is.
    static func car(at x: Double, _ y: Double, among dots: [(number: String, x: Double, y: Double)],
                    reach: Double = 22) -> String? {
        var best: (number: String, d: Double)?
        for dot in dots {
            let d = ((dot.x - x) * (dot.x - x) + (dot.y - y) * (dot.y - y)).squareRoot()
            if d <= reach, best.map({ d < $0.d }) ?? true { best = (dot.number, d) }
        }
        return best?.number
    }
}

/// Saturating UTC ms arithmetic (DuoCore's own is internal to it).
enum LiveMath {
    static func sub(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = a.subtractingReportingOverflow(b)
        return overflow ? (b < 0 ? .max : .min) : value
    }

    static func add(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? (b < 0 ? .min : .max) : value
    }
}

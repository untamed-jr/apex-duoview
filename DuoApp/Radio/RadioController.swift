import F1TV
import Foundation
import LiveTiming
import Multiview
import Observation

/// The player the radio plays over: the multiview or the single-feed player, whichever plays.
/// It mutes its feeds while a clip plays, gives the speed clips follow, and counts its seeks.
@MainActor
protocol PlaybackHost: AnyObject {
    /// The feeds' own level (0 while a clip plays, else 1). Never the viewer's mute, nor the
    /// multiview's rule that only one feed is heard.
    func setFeedVolume(_ volume: Float)
    /// The speed the viewer chose.
    var playbackRate: Double { get }
    /// Goes up on every seek, scrub or jump (the controls' own, the system's): a change between two
    /// ticks is a seek, never normal play.
    var seekGeneration: Int { get }
}

/// What plays a clip's file (`RadioAudio` in the app).
@MainActor
protocol RadioPlayback: AnyObject {
    /// Plays the file from its start at `rate`, panned (−1 left … 1 right). `onEnd` comes once,
    /// when the clip has played to its end or the audio stopped by itself (a configuration
    /// change), never after `stop()`.
    func play(fileURL: URL, pan: Float, rate: Float, onEnd: @escaping @MainActor () -> Void) throws
    /// The speed of the clip playing (the feeds' speed).
    func setRate(_ rate: Float)
    /// Stops at once; no `onEnd`.
    func stop()
}

/// A driver for the Radio panel's chips.
struct RadioDriver: Equatable, Sendable, Identifiable {
    var number: String
    var tla: String
    var teamColour: String
    var id: String { number }
}

/// Team radio for the session being watched, shared by the multiview and the single-feed player
/// (whichever is attached as the host). One controller for the app; it starts afresh with each
/// session the timing loads.
///
/// - 2 Hz, at picture time: the rows (`rows`, filtered; every visible clip for Race Engineer's
///   spot through `clips(for:limit:)`), built from DuoCore at the cut (`showWholeRace ? nil :
///   pictureTime`); nothing while there is no picture time, unless the whole race is on.
/// - Its own `EventDetector`, listening to every car: a clip crossed in normal play flashes once
///   (3 s, `isNew`); one reached by a seek, a scrub or a jump (`PlaybackHost.seekGeneration`, and
///   the detector's own jump and rewind rules) never does. Clips of the cars in `listen(_:)`
///   crossed in normal play go to `crossed`, for auto-play (never rows appearing).
/// - Playing: the clip downloads off the main actor the first time (`RadioFetch`, without the
///   sign-in first), is kept in `Caches/radio/{sessionKey}/`, and plays through `RadioAudio` at
///   the feeds' speed while the feeds' volume is 0. Every way a clip ends (its end, `stop()`, a
///   failure, a rewind past it, a new session, another host, `detach()`) goes through `finish`,
///   which puts the volume back to 1.
/// - Never logs; the token only goes to `RadioFetch`.
@MainActor
@Observable
final class RadioController {
    static let tickInterval: Duration = .milliseconds(500)
    /// How long a new clip's row flashes.
    static let flashDuration: Duration = .seconds(3)
    /// Ticks after a changed seek generation that still count as a seek: the clock may read the
    /// old time until the seek lands.
    static let seekTicks = 2

    /// The Radio panel's rows: the visible clips the filter keeps, oldest first.
    private(set) var rows: [RadioRowModel] = []
    /// Every visible clip's row, oldest first (Race Engineer's spot reads it through `clips`).
    private(set) var allRows: [RadioRowModel] = []
    /// The Radio panel's chips: All · My driver · a driver. Remembered.
    var filter: RadioFilter {
        didSet {
            guard filter != oldValue else { return }
            settings.radioFilter = filter
            tick()
        }
    }
    /// The clip playing (or loading to play), by path.
    private(set) var playing: String?
    /// "Couldn't load this clip" or "Couldn't play that radio clip"; cleared by the next play.
    private(set) var notice: String?
    /// The floating Radio panel is on (the "Radio" button).
    private(set) var panelShown = false
    /// Your driver's racing number in this session, if any.
    private(set) var favourite: String?
    /// The session's drivers, by code, for the chips.
    private(set) var drivers: [RadioDriver] = []

    @ObservationIgnored let settings: CompanionSettings
    @ObservationIgnored private let timing: TimingController
    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private let token: @Sendable () async -> String?
    @ObservationIgnored private let audio: any RadioPlayback
    /// `Caches/radio`; nil leaves every clip unplayable ("Couldn't load this clip").
    @ObservationIgnored private let cacheBase: URL?
    @ObservationIgnored private weak var host: (any PlaybackHost)?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var detector = EventDetector()
    @ObservationIgnored private var lastSeekGeneration: Int?
    @ObservationIgnored private var seekTicksLeft = 0
    /// Paths flashing, until when.
    @ObservationIgnored private var flashes: [String: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var listening: Set<String> = []
    @ObservationIgnored private var listeners: [UUID: AsyncStream<RadioClip>.Continuation] = [:]
    /// The session the rows are for (its key and folder).
    @ObservationIgnored private var sessionID: String?
    /// Transcripts arrive with build 18; until then the queue is empty and rows read it only at
    /// the cut.
    @ObservationIgnored private var queue = TranscriptionQueue()
    @ObservationIgnored private var playTask: Task<Void, Never>?
    /// Bumped by every play and finish: a late download or a late end for an older clip is dropped.
    @ObservationIgnored private var playToken = 0

    init(settings: CompanionSettings, timing: TimingController, http: any HTTPClient,
         token: @escaping @Sendable () async -> String?,
         audio: (any RadioPlayback)? = nil, cacheBase: URL? = RadioFetch.defaultBase) {
        self.settings = settings
        self.timing = timing
        self.http = http
        self.token = token
        self.audio = audio ?? Self.defaultAudio()
        self.cacheBase = cacheBase
        filter = settings.radioFilter
    }

    isolated deinit {
        tickTask?.cancel()
        playTask?.cancel()
        for continuation in listeners.values { continuation.finish() }
    }

    // MARK: Hosts

    /// The player now playing. Another host's clip stops first (its feeds get their volume back).
    func attach(host newHost: any PlaybackHost) {
        if let host, host !== newHost { finish() }
        host = newHost
        lastSeekGeneration = nil
        seekTicksLeft = 0
        startTicking()
        tick()
    }

    /// The host closed: the clip stops (its feeds get their volume back), and the session, the
    /// rows and the panel go.
    func detach() {
        finish()
        host = nil
        tickTask?.cancel()
        tickTask = nil
        forgetSession()
        if panelShown { panelShown = false }
    }

    /// Detaches only when `candidate` is the attached host (the two players share this controller).
    func detach(host candidate: any PlaybackHost) {
        guard let host, host === candidate else { return }
        detach()
    }

    // MARK: The panel

    func togglePanel() {
        panelShown.toggle()
        if !panelShown, notice != nil { notice = nil }
    }

    func hidePanel() {
        if panelShown { panelShown = false }
        if notice != nil { notice = nil }
    }

    // MARK: Listening

    /// The cars whose clips go to `crossed` when normal play crosses them (Scanner, Rivals).
    func listen(_ cars: Set<String>) {
        listening = cars
    }

    /// Clips of the listened cars crossed in normal play, from now on (each call is its own
    /// stream; a slow reader gets only the newest).
    var crossed: AsyncStream<RadioClip> {
        let (stream, continuation) = AsyncStream.makeStream(of: RadioClip.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.listeners[id] = nil }
        }
        return stream
    }

    // MARK: Reading

    /// The car's last `limit` visible clips (all with nil), oldest first, with their own headers.
    func clips(for number: String, limit: Int?) -> [RadioRowModel] {
        guard let session = timing.loadedSession else { return [] }
        // Re-cut now: the rows are up to half a second old.
        let shown = Set(RadioModels.visible(session.radio, pictureTime: timing.pictureTime,
                                            wholeRace: timing.showWholeRace).map(\.path))
        let mine = allRows.filter { $0.number == number && shown.contains($0.path) }
        let kept = limit.map { Array(mine.suffix(max($0, 0))) } ?? mine
        var above: String?
        return kept.map { row in
            var row = row
            row.header = row.label != nil && row.label != above ? row.label : nil
            above = row.label
            return row
        }
    }

    // MARK: Playing

    /// Plays a visible clip: downloads it the first time, then plays it while the feeds are quiet.
    /// A clip not visible at the cut (after picture time) is ignored.
    func play(path: String, pan: Float = 0) {
        guard host != nil, let session = timing.loadedSession,
              let clip = session.radio.all.first(where: { $0.path == path }),
              !RadioModels.shouldStop(playing: clip, pictureTime: timing.pictureTime, wholeRace: timing.showWholeRace)
        else { return }
        finish()
        let mine = playToken
        playing = path
        let key = session.info.key.map { String($0) } ?? session.info.path
        guard let base = cacheBase, !key.isEmpty,
              let url = RadioClips.audioURL(sessionPath: session.info.path, clipPath: path)
        else {
            finish(notice: RadioModels.couldNotLoad)
            return
        }
        let file = RadioFetch.cacheURL(base: base, sessionKey: key, clipPath: path)
        let http = http, token = token
        playTask = Task { [weak self] in
            let problem = await RadioController.load(url, to: file, http: http, token: token)
            guard let self, !Task.isCancelled, self.playToken == mine else { return }
            self.playTask = nil
            if let problem {
                self.finish(notice: problem)
                return
            }
            self.start(file: file, path: path, pan: pan, token: mine)
        }
    }

    /// Stops the clip; the feeds get their volume back.
    func stop() {
        finish()
    }

    private func start(file: URL, path: String, pan: Float, token mine: Int) {
        // The picture may have gone back past it while it downloaded.
        guard let host, let session = timing.loadedSession,
              let clip = session.radio.all.first(where: { $0.path == path }),
              !RadioModels.shouldStop(playing: clip, pictureTime: timing.pictureTime, wholeRace: timing.showWholeRace)
        else {
            finish()
            return
        }
        do {
            try audio.play(fileURL: file, pan: pan, rate: Float(host.playbackRate)) { [weak self] in
                self?.ended(token: mine)
            }
            host.setFeedVolume(0)
        } catch {
            // A damaged file: gone, so the next try downloads it again.
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }
            finish(notice: RadioModels.couldNotPlay)
        }
    }

    private func ended(token mine: Int) {
        guard playToken == mine, playing != nil else { return }
        finish()
    }

    /// The one way a clip ends: the audio stops, nothing late from it counts, and the feeds' volume
    /// goes back to 1.
    private func finish(notice newNotice: String? = nil) {
        playTask?.cancel()
        playTask = nil
        playToken &+= 1
        audio.stop()
        if playing != nil { playing = nil }
        host?.setFeedVolume(1)
        if notice != newNotice { notice = newNotice }
    }

    /// The cached file, or the download written there; nil when the file is ready, else the line
    /// to show. Off the main actor.
    @concurrent
    nonisolated static func load(_ url: URL, to file: URL, http: any HTTPClient,
                                 token: @escaping @Sendable () async -> String?) async -> String? {
        let manager = FileManager.default
        if manager.fileExists(atPath: file.path) { return nil }
        let result = await RadioFetch.fetch(url, http: http, token: token)
        if let notice = RadioModels.loadNotice(result) { return notice }
        guard case .data(let data) = result, !data.isEmpty else { return RadioModels.couldNotLoad }
        do {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            return RadioModels.couldNotLoad
        }
        return nil
    }

    // MARK: The tick

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: RadioController.tickInterval)
                } catch {
                    return
                }
                self?.tick()
            }
        }
    }

    /// One look at picture time: crossings, the playing clip, the rows. `now` is the wall clock.
    func tick(now: ContinuousClock.Instant = .now) {
        guard let host, let session = timing.loadedSession else {
            forgetSession()
            return
        }
        let id = "\(session.info.key.map { String($0) } ?? "")|\(session.info.path)"
        if id != sessionID {
            finish()
            sessionID = id
            detector = EventDetector()
            flashes = [:]
            queue = TranscriptionQueue()
            let list = session.drivers.values
                .map { RadioDriver(number: $0.number, tla: $0.tla.isEmpty ? $0.number : $0.tla, teamColour: $0.teamColour) }
                .sorted { ($0.tla, $0.number) < ($1.tla, $1.number) }
            if drivers != list { drivers = list }
        }
        let generation = host.seekGeneration
        if let last = lastSeekGeneration, last != generation {
            seekTicksLeft = Self.seekTicks
            flashes = [:]
        }
        lastSeekGeneration = generation
        let motion: PictureMotion = seekTicksLeft > 0 ? .seek : .play
        if seekTicksLeft > 0 { seekTicksLeft -= 1 }

        let pictureTime = timing.pictureTime
        let whole = timing.showWholeRace
        if let t = pictureTime {
            let cars = Set(session.drivers.keys).union(session.radio.all.map(\.racingNumber))
            let events = detector.step(to: t, motion: motion, session: session, radio: session.radio,
                                       favourite: nil, listening: cars)
            for event in events {
                guard case .radio(let car, let path) = event.kind else { continue }
                flashes[path] = now + Self.flashDuration
                if listening.contains(car), let clip = session.radio.all.first(where: { $0.path == path }) {
                    for continuation in listeners.values { continuation.yield(clip) }
                }
            }
        }
        flashes = flashes.filter { $0.value > now }

        let mine = timing.favouriteDriverName.flatMap { Tower.carNumber(forDriver: $0, in: session) }
        if favourite != mine { favourite = mine }

        if let path = playing, let clip = session.radio.all.first(where: { $0.path == path }),
           RadioModels.shouldStop(playing: clip, pictureTime: pictureTime, wholeRace: whole) {
            finish()
        }
        if playing != nil { audio.setRate(Float(host.playbackRate)) }

        let visible = RadioModels.visible(session.radio, pictureTime: pictureTime, wholeRace: whole)
        let cut = RadioModels.cut(pictureTime: pictureTime, wholeRace: whole)
        let new = Set(flashes.keys)
        let every = RadioModels.rows(clips: visible, session: session, queue: queue, at: cut, new: new)
        if allRows != every { allRows = every }
        let kept = RadioModels.filtered(visible, filter: filter, favourite: mine)
        let shown = kept.count == visible.count
            ? every
            : RadioModels.rows(clips: kept, session: session, queue: queue, at: cut, new: new)
        if rows != shown { rows = shown }
    }

    /// No session (or a new host): nothing playing, nothing listed.
    private func forgetSession() {
        if playing != nil || playTask != nil { finish() }
        sessionID = nil
        detector = EventDetector()
        flashes = [:]
        queue = TranscriptionQueue()
        if !rows.isEmpty { rows = [] }
        if !allRows.isEmpty { allRows = [] }
        if favourite != nil { favourite = nil }
        if !drivers.isEmpty { drivers = [] }
    }
}

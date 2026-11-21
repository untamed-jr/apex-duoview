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
    /// A clip is playing now (false once it ended or the system stopped the audio).
    var isPlaying: Bool { get }
    /// The clip's own level, 0...1 (the hinge mixer's radio share; 1 otherwise). A new clip starts
    /// at 1 until set.
    func setVolume(_ volume: Float)
    /// Headphones are the output now (wired, AirPods or another Bluetooth headset), from the audio
    /// session's current route: a clip can then go to one ear.
    var headphones: Bool { get }
    /// Called on the main actor, with `headphones`, after each route change.
    var onRouteChange: (@MainActor (Bool) -> Void)? { get set }
}

/// How one clip's transcription ended, as the controller hears it.
enum TranscriptOutcome: Sendable, Equatable {
    case text(String)
    /// The download or the transcriber failed.
    case failed
    /// Not done in 45 s.
    case timedOut
    case cancelled
    case permissionDenied
    case unavailable
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
/// - Transcripts (build 18), on the phone only, while a radio view shows (the panel, or one
///   named in `setSurface`) and Settings' "Transcripts" is on:
///   - the session's kept transcripts (`TranscriptStore`) seed `TranscriptionQueue(results:)`
///     before the first clip is handed out, and each new one is saved (the saves in order);
///   - `prepare()` until it's `.ready`; its line ("Getting the speech model ready…" and the
///     like) is `transcriptNote`, shown whatever the clips, so it never hints that radio is
///     coming;
///   - then `next(from:at:now:)` at the cut, `now` the monotonic clock in ms: one clip at a time,
///     downloaded if needed, transcribed in a race with 45 s (`timedOut`, not `failed`); a
///     transcriber error is `failed(path:at:)`;
///   - a radio view closing, Transcripts switched off, a new session or the host going is
///     `cancelled(path:)`; when `next` replaces the running job, the old task is cancelled; a
///     cancelled task's late report is dropped (a token, as for playing);
///   - rows read transcripts only through the queue's gated accessors, so text shows only once
///     its clip does. With Transcripts off, rows show none.
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
    /// The Radio panel's line about transcripts ("Getting the speech model ready…", "Transcripts
    /// aren't available on this iPhone — clips still play", "Allow speech recognition in Settings
    /// to see transcripts"); nil while they work, or with no radio view or Transcripts off.
    private(set) var transcriptNote: String?
    /// Headphones are the output (Rivals pans clips only then; its hint shows without them).
    /// Followed on every route change.
    private(set) var headphones = false
    /// The hinge mixer's levels; nil while it is off. While on, a clip doesn't silence the feeds:
    /// they play at `commentary` under it and the clip at `radio`.
    private(set) var mixer: MixLevels?

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
    /// Who set `listening` (a view's name), so a view going away clears only its own cars.
    @ObservationIgnored private var listenOwner: String?
    @ObservationIgnored private var listeners: [UUID: AsyncStream<RadioClip>.Continuation] = [:]
    /// The session the rows are for (its key and folder).
    @ObservationIgnored private var sessionID: String?
    /// What to transcribe next and what came of it. Rows read it only at the cut.
    @ObservationIgnored private var queue = TranscriptionQueue()
    @ObservationIgnored private let transcriber: any RadioTranscribing
    /// The monotonic clock in ms (the queue's `now`; never picture time).
    @ObservationIgnored private let clock: @MainActor () -> Int64
    /// How long one clip may take (`TranscriptionQueue.timeoutMs`).
    @ObservationIgnored private let transcribeTimeout: Duration
    /// Radio views on screen besides the panel, by name.
    @ObservationIgnored private var surfaces: Set<String> = []
    /// The app isn't in the background.
    @ObservationIgnored private var appActive = true
    /// What the transcriber last said; nil until it's been asked.
    @ObservationIgnored private var readiness: TranscriberReadiness?
    @ObservationIgnored private var preparing = false
    @ObservationIgnored private var lastPrepare: Int64?
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?
    /// Bumped whenever a transcription starts or is dropped: a late report is ignored.
    @ObservationIgnored private var transcribeToken = 0
    /// The session's kept transcripts; nil with no cache folder.
    @ObservationIgnored private var store: TranscriptStore?
    /// The kept transcripts are in the queue: clips may be handed out.
    @ObservationIgnored private var storeLoaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    /// Bumped by every play and finish: a late download or a late end for an older clip is dropped.
    @ObservationIgnored private var playToken = 0
    /// The audio was started for `playing` (not just downloading).
    @ObservationIgnored private var audioStarted = false

    init(settings: CompanionSettings, timing: TimingController, http: any HTTPClient,
         token: @escaping @Sendable () async -> String?,
         audio: (any RadioPlayback)? = nil, cacheBase: URL? = RadioFetch.defaultBase,
         transcriber: (any RadioTranscribing)? = nil, clock: (@MainActor () -> Int64)? = nil,
         transcribeTimeout: Duration = .milliseconds(TranscriptionQueue.timeoutMs)) {
        self.settings = settings
        self.timing = timing
        self.http = http
        self.token = token
        self.audio = audio ?? Self.defaultAudio()
        self.cacheBase = cacheBase
        self.transcriber = transcriber ?? Self.defaultTranscriber()
        self.clock = clock ?? { RadioController.uptimeMs() }
        self.transcribeTimeout = transcribeTimeout
        filter = settings.radioFilter
        headphones = self.audio.headphones
        self.audio.onRouteChange = { [weak self] phones in
            guard let self, self.headphones != phones else { return }
            self.headphones = phones
        }
    }

    /// System uptime in ms: monotonic, and it runs while the picture is paused.
    static func uptimeMs() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }

    isolated deinit {
        tickTask?.cancel()
        playTask?.cancel()
        transcribeTask?.cancel()
        for continuation in listeners.values { continuation.finish() }
    }

    // MARK: Hosts

    /// The player now playing. Another host's clip stops first (its feeds get their volume back).
    func attach(host newHost: any PlaybackHost) {
        if let host, host !== newHost {
            finish()
            timing.setRadioReader(false, owner: host)
        }
        host = newHost
        // A live session keeps being rebuilt for the radio, even with no timing panel open.
        timing.setRadioReader(true, owner: newHost)
        lastSeekGeneration = nil
        seekTicksLeft = 0
        startTicking()
        tick()
    }

    /// The host closed: the clip stops (its feeds get their volume back), and the session, the
    /// rows and the panel go.
    func detach() {
        finish()
        if let host { timing.setRadioReader(false, owner: host) }
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
        driveTranscription()
    }

    func hidePanel() {
        if panelShown { panelShown = false }
        if notice != nil { notice = nil }
        driveTranscription()
    }

    /// A radio view besides the panel came on screen or went (the closed phone's pages and the
    /// book's Radio, as they arrive). Transcription runs only while one of them, or the panel,
    /// shows.
    func setSurface(_ name: String, shown: Bool) {
        if shown { surfaces.insert(name) } else { surfaces.remove(name) }
        driveTranscription()
    }

    /// The app went to the background (picture in picture, audio only) or came back: no radio
    /// view is on screen meanwhile, so nothing is transcribed.
    func setAppActive(_ active: Bool) {
        guard appActive != active else { return }
        appActive = active
        driveTranscription()
    }

    // MARK: Listening

    /// The cars whose clips go to `crossed` when normal play crosses them (Scanner, Rivals).
    func listen(_ cars: Set<String>) {
        listening = cars
        listenOwner = nil
    }

    /// The cars listened to now.
    var listeningNow: Set<String> { listening }

    /// `listen` for a view by name (the Radio Scanner, Rivals): `stopListening(by:)` from it later
    /// clears the cars only if no other view has set its own since.
    func listen(_ cars: Set<String>, by owner: String) {
        listening = cars
        listenOwner = owner
    }

    /// The view `owner` went away: its cars stop being listened to, unless another view's are in
    /// place by now (the Scanner's page leaving as Rivals comes up, in either order).
    func stopListening(by owner: String) {
        guard listenOwner == owner else { return }
        listening = []
        listenOwner = nil
    }

    // MARK: The hinge mixer

    /// The hinge mixer's levels, or nil for off (`HingeMixer`'s, in book and laptop with the
    /// setting on). Off, a clip silences the feeds (Android's `RADIO_DUCK = 0`). On, the feeds
    /// play at `levels.commentary` under a clip and the clip at `levels.radio`. Without a clip the
    /// feeds are at 1 either way. A clip playing takes the new levels at once.
    func setMixer(_ levels: MixLevels?) {
        guard mixer != levels else { return }
        mixer = levels
        applyLevels()
    }

    /// The clip's level and the feeds' under it, while a clip plays (not while it downloads: the
    /// feeds stay at 1 until it starts).
    private func applyLevels() {
        guard let host, playing != nil, audioStarted else { return }
        audio.setVolume(Self.clipLevel(mixer))
        host.setFeedVolume(Self.feedLevelUnderClip(mixer))
    }

    /// The clip's own level: the mixer's radio share, else 1.
    nonisolated static func clipLevel(_ mixer: MixLevels?) -> Float {
        mixer.map { min(max($0.radio, 0), 1) } ?? 1
    }

    /// The feeds' level while a clip plays: the mixer's commentary share, else 0 (silent).
    nonisolated static func feedLevelUnderClip(_ mixer: MixLevels?) -> Float {
        mixer.map { min(max($0.commentary, 0), 1) } ?? 0
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

    /// Plays a visible clip: downloads it the first time, then plays it while the feeds are quiet
    /// (or, with the hinge mixer on, at its levels). `pan` is −1 (left ear) … 1 (right ear); Rivals
    /// pans each driver to their screen's ear. A clip not visible at the cut (after picture time)
    /// is ignored.
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
            audioStarted = true
            applyLevels()
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
        audioStarted = false
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

    // MARK: Transcripts

    /// How often the transcriber is asked again while it isn't ready.
    static let prepareEveryMs: Int64 = 2_000

    /// One step: stops transcribing when no radio view shows (or Transcripts is off, or there is
    /// no session or host); else asks the transcriber until it's ready, then hands it the next
    /// clip. On every tick, and whenever a view, a result or the readiness changes.
    private func driveTranscription() {
        // The panel is drawn only while the timing shows data; nothing is on screen in the background.
        guard let session = timing.loadedSession, host != nil, sessionID != nil, settings.transcripts, appActive,
              (panelShown && timing.showsData) || !surfaces.isEmpty
        else {
            stopTranscribing()
            if transcriptNote != nil { transcriptNote = nil }
            return
        }
        let note = readiness.flatMap { TranscriptState.line(for: $0) }
        if transcriptNote != note { transcriptNote = note }
        guard readiness == .ready else {
            prepareIfDue()
            return
        }
        guard storeLoaded else { return }
        // The cut: picture time, or nil only for the whole race. No picture time: nothing is due.
        let cut: UTCms?
        if timing.showWholeRace {
            cut = nil
        } else if let pictureTime = timing.pictureTime {
            cut = pictureTime
        } else {
            return
        }
        let wasRunning = queue.transcribing
        let clip = queue.next(from: session.radio.all, at: cut, now: clock())
        // `next` skipped the running clip (its 45 s are up): that task goes, its report with it.
        if wasRunning != nil, queue.transcribing != wasRunning || clip != nil { dropTask() }
        if let clip { startTranscribing(clip, session: session) }
    }

    private func prepareIfDue() {
        let now = clock()
        guard !preparing, lastPrepare.map({ now - $0 >= Self.prepareEveryMs }) ?? true else { return }
        preparing = true
        lastPrepare = now
        let transcriber = transcriber
        Task { [weak self] in
            let state = await transcriber.prepare()
            guard let self else { return }
            self.preparing = false
            self.readiness = state
            self.driveTranscription()
        }
    }

    /// Downloads the clip if it isn't cached, then transcribes it against the 45 s.
    private func startTranscribing(_ clip: RadioClip, session: LoadedSession) {
        dropTask()
        let mine = transcribeToken
        let path = clip.path
        let key = session.info.key.map { String($0) } ?? session.info.path
        guard let base = cacheBase, !key.isEmpty,
              let url = RadioClips.audioURL(sessionPath: session.info.path, clipPath: path)
        else {
            queue.failed(path: path, at: clock())
            return
        }
        let file = RadioFetch.cacheURL(base: base, sessionKey: key, clipPath: path)
        let hints = TranscriptState.hints(drivers: session.drivers)
        let http = http, token = token, transcriber = transcriber, timeout = transcribeTimeout
        let report: @Sendable @MainActor (TranscriptOutcome) -> Void = { [weak self] outcome in
            self?.transcribed(path: path, outcome: outcome, token: mine)
        }
        transcribeTask = Task {
            await RadioController.transcribe(url, file: file, hints: hints, http: http, token: token,
                                             transcriber: transcriber, timeout: timeout, report: report)
        }
    }

    private func transcribed(path: String, outcome: TranscriptOutcome, token mine: Int) {
        // Cancelled, replaced or skipped meanwhile: dropped.
        guard transcribeToken == mine, queue.transcribing == path else { return }
        transcribeTask = nil
        transcribeToken &+= 1
        switch outcome {
        case .text(let words):
            queue.finished(path: path, result: words)
            saveTranscripts()
        case .failed, .unavailable:
            // An engine that went away mid-session counts as a failure (three wait 2 minutes),
            // so it can't spin.
            queue.failed(path: path, at: clock())
        case .timedOut:
            queue.timedOut(path: path)
        case .cancelled:
            queue.cancelled(path: path)
        case .permissionDenied:
            // Not the clip's fault: it comes back once speech recognition is allowed.
            queue.cancelled(path: path)
            readiness = .permissionDenied
        }
        if let session = timing.loadedSession { refreshRows(session) }
        driveTranscription()
    }

    /// The running clip stops without counting against it (`cancelled`), and its task goes.
    private func stopTranscribing() {
        if let path = queue.transcribing { queue.cancelled(path: path) }
        dropTask()
    }

    /// Cancels the transcription task; whatever it reports later is dropped.
    private func dropTask() {
        transcribeTask?.cancel()
        transcribeTask = nil
        transcribeToken &+= 1
    }

    /// The session's kept transcripts, read off the main actor; until they are in the queue, no
    /// clip is handed out.
    private func loadTranscripts(for session: LoadedSession, id: String) {
        let key = session.info.key.map { String($0) } ?? session.info.path
        queue = TranscriptionQueue()
        store = cacheBase.flatMap { key.isEmpty ? nil : TranscriptStore(base: $0, sessionKey: key) }
        storeLoaded = store == nil
        guard let store else { return }
        Task { [weak self] in
            let kept = await RadioController.readTranscripts(store)
            guard let self, self.sessionID == id, self.store == store, !self.storeLoaded else { return }
            // Nothing was handed out while loading, so the queue is still empty.
            self.queue = TranscriptionQueue(results: kept)
            self.storeLoaded = true
            if let session = self.timing.loadedSession { self.refreshRows(session) }
            self.driveTranscription()
        }
    }

    /// Saves every transcript so far, after the save before it (an older one never lands last).
    private func saveTranscripts() {
        guard let store else { return }
        let snapshot = queue.results
        let previous = saveTask
        saveTask = Task.detached(priority: .utility) {
            await previous?.value
            store.save(snapshot)
        }
    }

    @concurrent
    nonisolated static func readTranscripts(_ store: TranscriptStore) async -> [String: String] {
        store.load()
    }

    /// Downloads the clip if needed and transcribes it, racing `timeout`. `report` hears the first
    /// to finish at once, on the main actor, before the loser has wound down (a transcriber slow to
    /// stop can't hold up the skip). Off the main actor.
    @concurrent
    nonisolated static func transcribe(_ url: URL, file: URL, hints: [String], http: any HTTPClient,
                                       token: @escaping @Sendable () async -> String?,
                                       transcriber: any RadioTranscribing, timeout: Duration,
                                       report: @escaping @Sendable @MainActor (TranscriptOutcome) -> Void) async {
        await withTaskGroup(of: TranscriptOutcome.self) { group in
            group.addTask {
                if await RadioController.load(url, to: file, http: http, token: token) != nil { return .failed }
                do {
                    return .text(try await transcriber.transcribe(fileURL: file, hints: hints))
                } catch let error as TranscriberError {
                    return error == .permissionDenied ? .permissionDenied : .unavailable
                } catch {
                    return Task.isCancelled ? .cancelled : .failed
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }
            let first = await group.next() ?? .cancelled
            await report(first)
            group.cancelAll()
        }
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
            stopTranscribing()
            sessionID = id
            detector = EventDetector()
            flashes = [:]
            loadTranscripts(for: session, id: id)
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
        // The audio stopped by itself (an interruption, with no end reported): the clip is over.
        if playing != nil, audioStarted, !audio.isPlaying { finish() }
        if playing != nil { audio.setRate(Float(host.playbackRate)) }

        driveTranscription()
        refreshRows(session)
    }

    /// The rows at the cut, from the clips, the flashes and the queue (no transcripts with
    /// Transcripts off).
    private func refreshRows(_ session: LoadedSession) {
        let pictureTime = timing.pictureTime
        let whole = timing.showWholeRace
        let visible = RadioModels.visible(session.radio, pictureTime: pictureTime, wholeRace: whole)
        let cut = RadioModels.cut(pictureTime: pictureTime, wholeRace: whole)
        let new = Set(flashes.keys)
        let texts = settings.transcripts ? queue : TranscriptionQueue()
        let every = RadioModels.rows(clips: visible, session: session, queue: texts, at: cut, new: new)
        if allRows != every { allRows = every }
        let kept = RadioModels.filtered(visible, filter: filter, favourite: favourite)
        let shown = kept.count == visible.count
            ? every
            : RadioModels.rows(clips: kept, session: session, queue: texts, at: cut, new: new)
        if rows != shown { rows = shown }
    }

    /// No session (or a new host): nothing playing, nothing listed, nothing transcribed.
    private func forgetSession() {
        if playing != nil || playTask != nil { finish() }
        stopTranscribing()
        sessionID = nil
        detector = EventDetector()
        flashes = [:]
        queue = TranscriptionQueue()
        store = nil
        storeLoaded = false
        if transcriptNote != nil { transcriptNote = nil }
        if !rows.isEmpty { rows = [] }
        if !allRows.isEmpty { allRows = [] }
        if favourite != nil { favourite = nil }
        if !drivers.isEmpty { drivers = [] }
    }
}

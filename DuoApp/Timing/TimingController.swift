import F1TV
import Foundation
import LiveTiming
import Observation

/// The timing for the video being watched, shared by the multiview and the single-feed player
/// (only one of them plays at a time). The player that opens a session attaches it with a clock
/// that reads its main feed; closing detaches it.
///
/// - Loading: `SessionLookup` through the archive's index, then `TimingArchive.loadOutcome`, which
///   fetches and parses off the main actor; only the `LoadedSession` (plain values) comes back.
///   Content that isn't a session, or that F1's archive doesn't have, is "No timing for this
///   session" and the data views hide. A network failure is tried again after 3, 10, 30 and
///   60 s, then every 60 s, meanwhile "Map unavailable — trying again…".
/// - Picture time: the main feed's program date plus the offset (`PictureClock`); without a
///   program date the session start plus the player's position, flagged as estimated.
/// - Every value it hands out is read at or before picture time: the 2 Hz `snapshot`, and
///   `mapState(at:)`, which the map asks for at the display's frame rate. The timeline marks
///   (`TimelineMark.marks`) show lights out and the chequered flag always, and flag periods only
///   up to picture time unless "Show the whole race" is on.
/// - The 2 Hz tick runs only while something reads it: a floating panel showing, the multiview's
///   timeline marks, or a driver card over an onboard (`setCardFeeds`).
/// - The tower (`tower`), its header (`header`), the battle (`battleRival`) and the cards (`cards`)
///   are published at 2 Hz as separate values, each assigned only when it changed, so a view reads
///   only what it shows.
/// - Lap states (`LapStates`) are built once per loaded session, never per frame: the map's flying
///   ring and tap-a-car's ranking read them.
/// - The speed readouts come from `CarDataLoader`, started once a card shows.
/// - The circuit comes from MultiViewer (or is traced from the cars), kept in Caches.
///
/// Never logs; the token goes only to F1's archive, inside `TimingArchive`.
@MainActor
@Observable
final class TimingController {
    static let noTiming = "No timing for this session"
    static let retrying = "Map unavailable — trying again…"
    static let estimatedNote = "Timing estimated — nudge until the cars match"
    /// The waits between tries of a failed load (archive or circuit); the last repeats.
    static let retryDelays: [Duration] = [.seconds(3), .seconds(10), .seconds(30), .seconds(60)]
    static let snapshotInterval: Duration = .milliseconds(500)
    /// How far ahead of the leader the safety car's dot sits, as a share of the lap.
    static let safetyCarLead = 0.02
    /// The map turns in these steps.
    static let turnStep = 15.0

    private(set) var status: TimingStatus = .idle
    /// Picture-time values for the 2 Hz views (tower, header, captions); `.empty` until loaded.
    private(set) var snapshot: TimingSnapshot = .empty
    /// Lights out, chequered and flag bands, in the main feed's player seconds.
    private(set) var timelineMarks: [TimelineMark] = []
    /// The circuit, once found.
    private(set) var map: TrackMap?
    /// Why there is no map yet, while it is tried again.
    private(set) var mapMessage: String?
    /// The viewer's turn of this circuit's map, in degrees.
    private(set) var mapTurn: Double = 0
    /// The picture offset (mirrors `TimingSettings.offsetMs`, so frames don't read the store).
    private(set) var offsetMs: Int64
    /// The floating panels showing.
    private(set) var panels: Set<TimingPanel> = []
    /// Settings › Track map switches (mirrors of the store, which isn't observed).
    private(set) var showWholeRace: Bool
    private(set) var speedOnMobileData: Bool
    /// The timing tower at picture time, in running order; empty while the tower and the map are
    /// both hidden.
    private(set) var tower: [TowerRow] = []
    /// The tower's gap column title: "Leader" in a race, "Fastest" otherwise.
    private(set) var gapHeader = "Leader"
    /// The session header over the tower.
    private(set) var header: SessionHeaderState = .empty
    /// Your driver's rival in a battle (within 1.0 s for two updates, races only), for the map's
    /// Battle chip; nil otherwise.
    private(set) var battleRival: BattleRival?
    /// The driver cards at picture time, by racing number, for the onboards showing.
    private(set) var cards: [String: DriverCardState] = [:]
    /// Channel ids whose cards the viewer hid (mirrors `TimingSettings.hiddenCards`).
    private(set) var hiddenCards: Set<Int>

    @ObservationIgnored let settings: TimingSettings
    @ObservationIgnored private let archive: TimingArchive
    /// For MultiViewer's circuit data: no token is ever added to its requests.
    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private var loaded: LoadedSession?
    @ObservationIgnored private var clock: (@MainActor () -> (programDate: Date?, playerSeconds: Double))?
    @ObservationIgnored private var contentId: Int?
    /// The player that attached (`attach(owner:)`); only it can detach.
    @ObservationIgnored private var ownerID: ObjectIdentifier?
    /// The attached player shows timeline marks (the multiview's scrubber).
    @ObservationIgnored private var wantsMarks = false
    @ObservationIgnored private var circuitKey: Int?
    /// Bumped by every attach and detach, so a slow load for something superseded is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var mapTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// The loaded session's lap states, built once when it loads.
    @ObservationIgnored private var lapStates: LapStates?
    /// The archive folder and key of the loaded session, for its car data.
    @ObservationIgnored private var archiveSession: ArchiveSession?
    /// The onboards showing, channel id → racing number, from the attached player.
    @ObservationIgnored private var cardFeeds: [Int: String] = [:]
    /// The speed readouts' car data, once a card has shown.
    @ObservationIgnored private var carData: CarDataLoader?
    /// Your driver's last name (Settings › Multiview › My driver), for the battle highlight.
    @ObservationIgnored private var favouriteDriver: String?

    init(archive: TimingArchive, settings: TimingSettings, http: any HTTPClient) {
        self.archive = archive
        self.settings = settings
        self.http = http
        offsetMs = settings.offsetMs
        showWholeRace = settings.showWholeRace
        speedOnMobileData = settings.speedOnMobileData
        hiddenCards = settings.hiddenCards
    }

    isolated deinit {
        loadTask?.cancel()
        mapTask?.cancel()
        tickTask?.cancel()
        carData?.cancel()
    }

    /// Whether the data views (the Map button, the panels) show: while loading, when loaded, and
    /// while a failed load is tried again; not for content with no timing.
    var showsData: Bool {
        switch status {
        case .loading, .ready, .estimated: return true
        case .unavailable(let reason): return reason == Self.retrying
        case .idle: return false
        }
    }

    // MARK: Attaching

    /// Starts timing for `item` (its `timingRef` must be filled, from the video's details when the
    /// item has none), with `clock` reading the main feed's program date and position together.
    /// `owner` is the player attaching: only it can `detach(owner:)` later. `timelineMarks`: it
    /// shows the marks (the multiview's scrubber), so the 2 Hz tick runs for them. Attaching the
    /// content already attached keeps its timing and takes the new clock (a feed change in the
    /// single player).
    func attach(item: CatalogItem, owner: AnyObject? = nil, timelineMarks: Bool = false,
                clock: @escaping @MainActor () -> (programDate: Date?, playerSeconds: Double)) {
        if contentId == item.contentId, status != .idle {
            self.clock = clock
            let newOwner = owner.map(ObjectIdentifier.init)
            // Another player took over: its own cards come with its next `setCardFeeds`.
            if ownerID != newOwner, !cardFeeds.isEmpty {
                cardFeeds = [:]
                if !cards.isEmpty { cards = [:] }
            }
            ownerID = newOwner
            wantsMarks = timelineMarks
            // The new clock may change the status (estimated or not) even with no reader ticking.
            publish()
            updateTicking()
            return
        }
        detach()
        self.clock = clock
        ownerID = owner.map(ObjectIdentifier.init)
        wantsMarks = timelineMarks
        contentId = item.contentId
        guard let ref = item.timingRef, ref.isSession else {
            status = .unavailable(Self.noTiming)
            return
        }
        status = .loading
        let mine = generation
        loadTask = Task { [weak self] in
            await self?.load(ref: ref, generation: mine)
        }
    }

    /// Detaches only if `owner` is the player that attached: the single player and the multiview
    /// share this controller, and one closing must never drop the other's timing.
    func detach(owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner) else { return }
        detach()
    }

    /// Stops and forgets everything: the session, the map, the panels.
    func detach() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        mapTask?.cancel()
        mapTask = nil
        tickTask?.cancel()
        tickTask = nil
        clock = nil
        contentId = nil
        ownerID = nil
        wantsMarks = false
        circuitKey = nil
        loaded = nil
        lapStates = nil
        archiveSession = nil
        cardFeeds = [:]
        carData?.cancel()
        carData = nil
        if status != .idle { status = .idle }
        if snapshot != .empty { snapshot = .empty }
        if !tower.isEmpty { tower = [] }
        if header != .empty { header = .empty }
        if battleRival != nil { battleRival = nil }
        if !cards.isEmpty { cards = [:] }
        if !timelineMarks.isEmpty { timelineMarks = [] }
        map = nil
        mapMessage = nil
        mapTurn = 0
        if !panels.isEmpty { panels = [] }
    }

    // MARK: Picture time

    /// Picture time now, from the attached clock; nil before anything is loaded or while the
    /// player has no time to give.
    var pictureTime: UTCms? {
        reading()?.t
    }

    /// Picture time and the player seconds it was read with, from one clock reading.
    private func reading() -> (t: UTCms, estimated: Bool, playerSeconds: Double)? {
        guard let loaded, let clock else { return nil }
        let now = clock()
        guard let time = PictureClock(offsetMs: offsetMs).time(
            programDate: now.programDate, sessionStart: loaded.info.start, playerSeconds: now.playerSeconds)
        else { return nil }
        return (time.t, time.estimated, now.playerSeconds)
    }

    // MARK: Map

    /// The map at `t` (picture time): each car where its own samples put it at `t` (no (0,0)
    /// samples, none after `t`, hidden across a gap over 5 s), dimmed in the pits, knocked out or
    /// stopped, and left out once retired; the flags at `t`; the safety car's dot just ahead of
    /// the leader while it is out. Cheap enough for every frame.
    func mapState(at t: UTCms) -> MapState {
        guard let loaded, let lapStates else { return .empty }
        // Dimmed cars underneath, then from the back up, so the leader is drawn on top.
        let visible = MapCars.visible(at: t, session: loaded, lapStates: lapStates)
        let leader = visible.first { $0.position == 1 }?.point
        let cars = visible.map {
            MapCar(number: $0.number, tla: $0.tla, colour: $0.teamColour, point: $0.point, dimmed: $0.dimmed,
                   flyingRing: $0.flying)
        }
        let flags = loaded.flags.at(t)
        var safetyCar: TrackPoint?
        if flags.status == .safetyCar || flags.status == .safetyCarInThisLap, let leader, let map {
            let progress = map.geometry.progress(of: leader)
            safetyCar = map.geometry.point(atProgress: progress + (map.forward ? 1 : -1) * Self.safetyCarLead)
        }
        return MapState(cars: cars, flags: flags, caption: flags.caption, safetyCar: safetyCar)
    }

    /// The map's −1 s / +1 s: picture time moves by whole seconds (positive is later).
    func nudge(_ seconds: Int) {
        settings.nudge(by: seconds)
        offsetChanged()
    }

    /// Settings › Track map › "Reset to −7 s".
    func resetOffset() {
        settings.resetOffset()
        offsetChanged()
    }

    /// ⟲ ⟳: turns this circuit's map by `degrees` (15° steps), remembered per circuit.
    func turnMap(by degrees: Double) {
        let turned = (mapTurn + degrees).truncatingRemainder(dividingBy: 360)
        setTurn(turned)
    }

    func resetMapTurn() {
        setTurn(0)
    }

    private func setTurn(_ degrees: Double) {
        mapTurn = degrees
        if let circuitKey { settings.setMapTurn(degrees, circuitKey: circuitKey) }
    }

    private func offsetChanged() {
        let value = settings.offsetMs
        if offsetMs != value { offsetMs = value }
        publish()
    }

    // MARK: Panels and switches

    /// The "Map" control: both panels on when none shows, else both off.
    func toggleMapPanels() {
        panels = panels.isEmpty ? Set(TimingPanel.allCases) : []
        updateTicking()
        publish()
    }

    /// A panel's own ✕.
    func closePanel(_ panel: TimingPanel) {
        panels.remove(panel)
        updateTicking()
    }

    /// "Show the whole race": every flag period on the timeline (and, later, the Scrub Deck).
    func setShowWholeRace(_ on: Bool) {
        settings.showWholeRace = on
        showWholeRace = settings.showWholeRace
        publish()
    }

    func setSpeedOnMobileData(_ on: Bool) {
        settings.speedOnMobileData = on
        speedOnMobileData = settings.speedOnMobileData
        carData?.setAllowsExpensive(speedOnMobileData)
    }

    /// Settings › Multiview › My driver (a last name), for the battle highlight; nil turns it off.
    func setFavouriteDriver(_ lastName: String?) {
        guard favouriteDriver != lastName else { return }
        favouriteDriver = lastName
        publish()
    }

    // MARK: Driver cards and tap-a-car

    /// The onboards the attached player shows (`owner`), channel id → racing number: each gets a
    /// card unless hidden, and while one does the tick runs and the car data downloads. Ignored
    /// from a player that isn't attached.
    func setCardFeeds(_ feeds: [Int: String], owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner), cardFeeds != feeds else { return }
        cardFeeds = feeds
        cardsChanged()
    }

    /// "Hide card" / "Show card" on a tile: per channel, remembered.
    func toggleCard(channelId: Int) {
        _ = settings.toggleHiddenCard(channelId)
        hiddenCards = settings.hiddenCards
        cardsChanged()
    }

    /// The racing numbers whose cards show.
    private var cardCars: Set<String> {
        Set(cardFeeds.filter { !hiddenCards.contains($0.key) }.map(\.value))
    }

    private func cardsChanged() {
        updateTicking()
        startCarDataIfShown()
        publish()
    }

    /// Each car's lap state at picture time, for tap-a-car's ranking; empty before anything loads.
    func lapStatesNow() -> [String: LapState] {
        guard let lapStates, let t = pictureTime else { return [:] }
        return lapStates.at(t)
    }

    /// The car data downloads once a card shows (spec: as soon as an onboard is showing), and
    /// goes on to the end of the file once started.
    private func startCarDataIfShown() {
        guard carData == nil, loaded != nil, !cardCars.isEmpty, let archiveSession, let loaded else { return }
        let loader = CarDataLoader(
            archive: archive,
            sessionPath: archiveSession.path,
            cacheName: CarDataLoader.cacheName(key: archiveSession.key, path: archiveSession.path),
            streamStart: loaded.streamStart,
            allowsExpensive: speedOnMobileData)
        carData = loader
        loader.start()
    }

    // MARK: Loading

    private func load(ref: TimingRef, generation mine: Int) async {
        var attempt = 0
        while generation == mine, !Task.isCancelled {
            let outcome = await fetch(ref: ref)
            guard generation == mine, !Task.isCancelled else { return }
            switch outcome {
            case .found(let found):
                adopt(found.loaded, archiveSession: found.session, ref: ref, generation: mine)
                return
            case .unavailable:
                status = .unavailable(Self.noTiming)
                return
            case .failed:
                let waiting = TimingStatus.unavailable(Self.retrying)
                if status != waiting { status = waiting }
                guard await Self.wait(attempt: attempt) else { return }
                attempt += 1
            }
        }
    }

    /// The session (by the archive's index), then its files: off the main actor.
    private func fetch(ref: TimingRef) async -> ArchiveOutcome<FoundSession> {
        switch await archive.lookup(for: ref, watched: nil) {
        case .found(let session):
            switch await TimingArchive.loadOutcome(session, using: archive) {
            case .found(let loaded): return .found(FoundSession(session: session, loaded: loaded))
            case .unavailable: return .unavailable
            case .failed: return .failed
            }
        case .unavailable:
            return .unavailable
        case .failed:
            return .failed
        }
    }

    private func adopt(_ session: LoadedSession, archiveSession: ArchiveSession, ref: TimingRef, generation mine: Int) {
        loaded = session
        self.archiveSession = archiveSession
        // A snapshot of this session's timing: built once here, never per frame.
        lapStates = LapStates(session: session)
        gapHeader = Tower.gapHeader(session: session)
        let key = session.info.circuitKey ?? ref.circuitKey
        circuitKey = key
        mapTurn = key.map { settings.mapTurn(circuitKey: $0) } ?? 0
        status = .ready
        publish()
        updateTicking()
        startCarDataIfShown()
        let year = session.info.year ?? ref.year
        let http = http
        mapTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                let outcome = await Task.detached(priority: .utility) {
                    await CircuitLoader.load(circuitKey: key, year: year, session: session, http: http)
                }.value
                guard let self, self.generation == mine, !Task.isCancelled else { return }
                switch outcome {
                case .final(let map):
                    self.map = map
                    self.mapMessage = nil
                    return
                case .interim(let map):
                    // The same traced outline comes back on every try: assign it only when new.
                    if self.map == nil || self.map?.geometry.outline != map.geometry.outline { self.map = map }
                    if self.mapMessage != nil { self.mapMessage = nil }
                case .none:
                    if self.mapMessage != Self.retrying { self.mapMessage = Self.retrying }
                }
                guard await Self.wait(attempt: attempt) else { return }
                attempt += 1
            }
        }
    }

    /// Waits the retry delay for this attempt; false when cancelled.
    private static func wait(attempt: Int) async -> Bool {
        let delays = retryDelays
        let delay = delays[min(attempt, delays.count - 1)]
        do {
            try await Task.sleep(for: delay)
            return true
        } catch {
            return false
        }
    }

    // MARK: The 2 Hz snapshot

    /// Whether the tick has a reader: a session loaded, and a panel showing, the marks shown or a
    /// driver card showing.
    private var needsTicking: Bool {
        loaded != nil && (wantsMarks || !panels.isEmpty || !cardCars.isEmpty)
    }

    /// Starts or stops the tick to match `needsTicking`.
    private func updateTicking() {
        if needsTicking {
            startTicking()
        } else {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.publish()
                do {
                    try await Task.sleep(for: TimingController.snapshotInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// Reads picture time once and publishes what changed: the status (estimated or not), the
    /// snapshot, the timeline marks, and the tower, header, battle and cards when something shows
    /// them.
    private func publish() {
        guard let loaded, let now = reading() else { return }
        let state: TimingStatus = now.estimated ? .estimated : .ready
        if status != state { status = state }
        let t = now.t
        let next = TimingSnapshot(
            drivers: loaded.drivers,
            flags: loaded.flags.at(t),
            header: loaded.header.at(t),
            timing: loaded.timing.at(t),
            stints: loaded.stints.at(t),
            sessionStatus: loaded.sessionStatus.status(at: t),
            pictureTime: t)
        if snapshot != next { snapshot = next }
        let marks = wantsMarks
            ? TimelineMark.marks(for: loaded, pictureTime: t, playerSeconds: now.playerSeconds, wholeRace: showWholeRace)
            : []
        if timelineMarks != marks { timelineMarks = marks }
        publishPanels(loaded, at: t)
        publishCards(loaded, at: t)
    }

    /// The tower, its header and the battle, while a panel shows (the tower, or the map with its
    /// Battle chip).
    private func publishPanels(_ loaded: LoadedSession, at t: UTCms) {
        guard !panels.isEmpty else {
            if !tower.isEmpty { tower = [] }
            if battleRival != nil { battleRival = nil }
            return
        }
        let favourite = favouriteDriver.flatMap { Tower.carNumber(forDriver: $0, in: loaded) }
        let rows = Tower.rows(at: t, session: loaded, favourite: favourite)
        if tower != rows { tower = rows }
        let rival = BattleRival.from(rows, favourite: favourite)
        if battleRival != rival { battleRival = rival }
        let next = SessionHeaderState(header: loaded.header.at(t), flags: loaded.flags.at(t), race: loaded.info.isRace)
        if header != next { header = next }
    }

    /// The cards of the onboards showing, with their speed readouts.
    private func publishCards(_ loaded: LoadedSession, at t: UTCms) {
        var next: [String: DriverCardState] = [:]
        for number in cardCars {
            guard let card = DriverCardModel.at(t, number: number, session: loaded) else { continue }
            var speed: Int?
            if let samples = carData?.samples(car: number, around: t),
               let readout = CarDataWindow.readout(samples, at: t), !readout.stale {
                speed = readout.sample.speedKmh
            }
            next[number] = DriverCardState(card: card, speedKmh: speed)
        }
        if cards != next { cards = next }
    }
}

/// A session found in the archive and loaded: its folder and key (for the car data) and its timing.
private struct FoundSession: Sendable {
    var session: ArchiveSession
    var loaded: LoadedSession
}

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
/// - The 2 Hz tick runs only while something reads it: a floating panel showing, a data layout's
///   docked map or tower (`setDockedPanels`), the multiview's timeline marks, a driver card over
///   an onboard (`setCardFeeds`), Race Engineer's console (`setConsole`) or the Scrub Deck
///   (`setDeck`).
/// - The console (`console`) and the deck (`deck`) are built at the tick, never per frame: their
///   DuoCore calculations rescan the session's history. The console reads timing at picture time;
///   the deck too, unless "Show the whole race" is on (then it is built once and kept).
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
    /// The floating panels switched on (the Map control). One the attached player's data layout
    /// already shows (`dockedPanels`) is hidden while it does.
    private(set) var panels: Set<TimingPanel> = []
    /// The panels the attached player's data layout shows in its own regions (the multiview's
    /// Director's Desk, book data screen): read like a floating panel, drawn in place.
    private(set) var dockedPanels: Set<TimingPanel> = []
    /// Settings › Multiview › "Tracker delay", in half-seconds (mirrors
    /// `TimingSettings.trackerDelayHalfSeconds`, so the multiview's sync and the stepper don't
    /// read the store).
    private(set) var trackerDelayHalfSeconds: Int
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
    /// Race Engineer's console for the top onboard's car at picture time; nil while the console
    /// isn't showing or has no car.
    private(set) var console: ConsoleState?
    /// The Scrub Deck at picture time (or the whole race, opted in); nil while it isn't showing.
    private(set) var deck: DeckState?

    @ObservationIgnored let settings: TimingSettings
    @ObservationIgnored private let archive: TimingArchive
    /// For MultiViewer's circuit data: no token is ever added to its requests.
    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private var loaded: LoadedSession? {
        didSet { loadedRevision &+= 1 }
    }
    /// Which `loaded` this is: the console's and deck's builds are kept only for the same one.
    @ObservationIgnored private var loadedRevision = 0
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
    /// The attached item is a live broadcast: its car data will come from the live connection,
    /// so the archive's is never downloaded.
    @ObservationIgnored private var contentIsLive = false
    /// Your driver's last name (Settings › Multiview › My driver), for the battle highlight.
    @ObservationIgnored private var favouriteDriver: String?
    /// The attached player shows Race Engineer's console, and the racing number of the car on its
    /// top screen (nil: no onboard there).
    @ObservationIgnored private var consoleShown = false
    /// Observed on its own, so the console's mini map follows only the car, not the 2 Hz values.
    private(set) var consoleCar: String?
    /// The attached player shows the Scrub Deck.
    @ObservationIgnored private var deckShown = false
    /// The console and the deck as last built, with what they were built from: kept while that
    /// doesn't change (paused; the whole race is built once). Builds run off the main actor, one
    /// of each at a time.
    @ObservationIgnored private var consoleBuild: (key: ConsoleKey, state: ConsoleState)?
    @ObservationIgnored private var deckBuild: (key: DeckKey, state: DeckState)?
    @ObservationIgnored private var consoleTask: Task<Void, Never>?
    @ObservationIgnored private var deckTask: Task<Void, Never>?
    /// Channel 45 was seen moving in a 2026 car data window this session: the light stays "Aero"
    /// rather than coming and going with the window.
    @ObservationIgnored private var activeAeroSeen = false

    init(archive: TimingArchive, settings: TimingSettings, http: any HTTPClient) {
        self.archive = archive
        self.settings = settings
        self.http = http
        offsetMs = settings.offsetMs
        showWholeRace = settings.showWholeRace
        speedOnMobileData = settings.speedOnMobileData
        hiddenCards = settings.hiddenCards
        trackerDelayHalfSeconds = settings.trackerDelayHalfSeconds
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

    /// The session's timing is loaded (picture time exact or estimated): the data layouts are
    /// offered. Not while loading, retrying or unavailable.
    var hasTiming: Bool {
        status == .ready || status == .estimated
    }

    /// A floating panel shows: switched on, and not already in the data layout.
    func showsFloating(_ panel: TimingPanel) -> Bool {
        panels.contains(panel) && !dockedPanels.contains(panel)
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
            // Another player took over: its own cards and docked panels come with its next
            // `setCardFeeds` and `setDockedPanels`.
            if ownerID != newOwner, !cardFeeds.isEmpty {
                cardFeeds = [:]
                if !cards.isEmpty { cards = [:] }
            }
            if ownerID != newOwner, !dockedPanels.isEmpty { dockedPanels = [] }
            if ownerID != newOwner { clearRaceViews() }
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
        contentIsLive = item.isLive
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
        contentIsLive = false
        carData?.cancel()
        carData = nil
        clearRaceViews()
        activeAeroSeen = false
        if status != .idle { status = .idle }
        if snapshot != .empty { snapshot = .empty }
        if !tower.isEmpty { tower = [] }
        if gapHeader != "Leader" { gapHeader = "Leader" }
        if header != .empty { header = .empty }
        if battleRival != nil { battleRival = nil }
        if !cards.isEmpty { cards = [:] }
        if !timelineMarks.isEmpty { timelineMarks = [] }
        map = nil
        mapMessage = nil
        mapTurn = 0
        if !panels.isEmpty { panels = [] }
        if !dockedPanels.isEmpty { dockedPanels = [] }
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

    /// The attached player's data layout shows these panels in its own regions (`owner` must be
    /// the attached player; anyone else is ignored): they tick and publish like floating ones, and
    /// the floating copies hide while they show.
    func setDockedPanels(_ docked: Set<TimingPanel>, owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner), dockedPanels != docked else { return }
        dockedPanels = docked
        updateTicking()
        publish()
    }

    /// The attached player (`owner`) shows Race Engineer's console (`shown`), with `car` (a racing
    /// number) on its top screen, or none. While it shows, the tick runs; with a car, its car data
    /// downloads. Ignored from a player that isn't attached.
    func setConsole(shown: Bool, car: String?, owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner) else { return }
        let car = shown ? car : nil
        guard consoleShown != shown || consoleCar != car else { return }
        consoleShown = shown
        consoleCar = car
        updateTicking()
        startCarDataIfShown()
        publish()
    }

    /// The attached player (`owner`) shows the Scrub Deck: the tick runs and builds it. Ignored
    /// from a player that isn't attached.
    func setDeck(shown: Bool, owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner), deckShown != shown else { return }
        deckShown = shown
        updateTicking()
        publish()
    }

    /// Forgets the console and the deck (detach, or another player took over).
    private func clearRaceViews() {
        consoleShown = false
        if consoleCar != nil { consoleCar = nil }
        deckShown = false
        dropConsole()
        dropDeck()
    }

    private func dropConsole() {
        consoleTask?.cancel()
        consoleTask = nil
        consoleBuild = nil
        if console != nil { console = nil }
    }

    private func dropDeck() {
        deckTask?.cancel()
        deckTask = nil
        deckBuild = nil
        if deck != nil { deck = nil }
    }

    /// Settings › Multiview › "Tracker delay": longer (positive) or shorter by half-seconds,
    /// within 0–20 s.
    func nudgeTrackerDelay(by halfSeconds: Int) {
        let value = settings.nudgeTrackerDelay(by: halfSeconds)
        if trackerDelayHalfSeconds != value { trackerDelayHalfSeconds = value }
    }

    /// "Show the whole race": the Scrub Deck's whole lap chart and event strip, and every flag
    /// period on the timeline.
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
    /// goes on to the end of the file once started (topping it up while the session isn't known
    /// to be over). Never for a live item (`CarDataPolicy`).
    private func startCarDataIfShown() {
        // A card showing, or the console's car (its readouts: even with that onboard's card hidden).
        guard carData == nil, loaded != nil, !cardCars.isEmpty || consoleCar != nil, let archiveSession, let loaded
        else { return }
        let plan = CarDataPolicy.plan(live: contentIsLive, status: loaded.sessionStatus)
        guard plan != .skip else { return }
        let loader = CarDataLoader(
            archive: archive,
            sessionPath: archiveSession.path,
            cacheName: CarDataLoader.cacheName(key: archiveSession.key, path: archiveSession.path),
            streamStart: loaded.streamStart,
            allowsExpensive: speedOnMobileData,
            finished: plan == .whole)
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

    /// The panels read at 2 Hz: floating or docked.
    private var readPanels: Set<TimingPanel> {
        panels.union(dockedPanels)
    }

    /// Whether the tick has a reader: a session loaded, and a panel showing (floating or docked),
    /// the marks shown or a driver card showing.
    private var needsTicking: Bool {
        loaded != nil && (wantsMarks || !readPanels.isEmpty || !cardCars.isEmpty || consoleShown || deckShown)
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
        publishConsole(loaded, at: t)
        publishDeck(loaded, at: t, playerSeconds: now.playerSeconds)
    }

    /// Race Engineer's console for the top onboard's car, while it shows. Built off the main
    /// actor (it rescans the session's history), only when something it reads changed.
    private func publishConsole(_ loaded: LoadedSession, at t: UTCms) {
        guard consoleShown, let car = consoleCar else {
            dropConsole()
            return
        }
        let samples = carData?.samples(car: car, around: t) ?? []
        var meaning = Channel45Meaning.of(year: loaded.info.year, samples: [car: samples])
        if meaning == .activeAero { activeAeroSeen = true }
        if activeAeroSeen, meaning == .absent { meaning = .activeAero }
        let stored = circuitKey.flatMap { settings.pitLossMs(circuitKey: $0) }.map { Int(clamping: $0) }
        let key = ConsoleKey(session: loadedRevision, car: car, t: t, samples: samples.count,
                             lastSample: samples.last?.t, channel45: meaning, storedPitLossMs: stored)
        if let built = consoleBuild, built.key == key {
            if console != built.state { console = built.state }
            return
        }
        // One build at a time: the next tick asks again with the newest moment.
        guard consoleTask == nil else { return }
        let channel45 = meaning
        consoleTask = Task { [weak self] in
            let state = await Task.detached(priority: .userInitiated) {
                ConsoleState.make(number: car, at: t, session: loaded, samples: samples, channel45: channel45,
                                  storedPitLossMs: stored)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.consoleTask = nil
            self.adoptConsole(state, key: key)
        }
    }

    /// A finished console build, dropped when superseded: another car or session, the console
    /// gone, or the picture moved back before its moment (no data ahead of the picture).
    private func adoptConsole(_ state: ConsoleState, key: ConsoleKey) {
        guard consoleShown, consoleCar == key.car, loadedRevision == key.session,
              let now = pictureTime, key.t <= now else { return }
        consoleBuild = (key, state)
        if console != state { console = state }
    }

    /// The Scrub Deck, while it shows: built off the main actor when picture time moves (so a seek
    /// back shrinks it), or once with the whole race on; a kept build takes the latest clock
    /// reading.
    private func publishDeck(_ loaded: LoadedSession, at t: UTCms, playerSeconds: Double) {
        guard deckShown else {
            dropDeck()
            return
        }
        let favourite = favouriteDriver.flatMap { Tower.carNumber(forDriver: $0, in: loaded) }
        let whole = showWholeRace
        let key = DeckKey(session: loadedRevision, cut: whole ? nil : t, favourite: favourite)
        if let built = deckBuild, built.key == key {
            var next = built.state
            next.pictureTime = t
            next.playerSeconds = playerSeconds
            if deck != next { deck = next }
            return
        }
        guard deckTask == nil else { return }
        deckTask = Task { [weak self] in
            let state = await Task.detached(priority: .userInitiated) {
                DeckState.make(session: loaded, at: t, playerSeconds: playerSeconds, wholeRace: whole, favourite: favourite)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.deckTask = nil
            self.adoptDeck(state, key: key)
        }
    }

    /// A finished deck build, dropped when superseded: another session, the deck gone, the whole
    /// race switched, or (cut at picture time) the picture moved back before its cut.
    private func adoptDeck(_ state: DeckState, key: DeckKey) {
        guard deckShown, loadedRevision == key.session, (key.cut == nil) == showWholeRace else { return }
        if let cut = key.cut {
            guard let now = pictureTime, cut <= now else { return }
        }
        deckBuild = (key, state)
        if deck != state { deck = state }
    }

    /// The tower, its header and the battle, while a panel shows, floating or docked (the tower,
    /// or the map with its Battle chip).
    private func publishPanels(_ loaded: LoadedSession, at t: UTCms) {
        guard !readPanels.isEmpty else {
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

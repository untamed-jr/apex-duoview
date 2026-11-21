import Foundation
import LiveTiming
import Multiview
import Observation

/// A player whose feeds a card can jump: the multiview. The single-feed player is only a
/// `PlaybackHost`, so it gets no cards (haptics only, from Task 13).
@MainActor
protocol CompanionJumpHost: PlaybackHost {
    /// Every feed to picture time `t`, through the Scrub Deck's seek, remembering where they were
    /// for `jumpBack()`. False when nothing moved (no picture time, the feeds not ready).
    func jump(toPictureTime t: UTCms) -> Bool
    /// Back to where the last jump left from: that place, or the live edge if it was there.
    func jumpBack()
}

/// The closed phone's companion for whichever player plays: the event cards and Unfold to See,
/// "Back to where you were", and the events for haptics. One for the app, beside the radio.
///
/// - Every 500 ms at picture time, one `EventDetector.step` for your driver (`listening: []`:
///   your driver's radio is a card; the Scanner's auto-play comes from `radio.crossed`). A changed
///   `host.seekGeneration` makes this tick and the next a `.seek` (the clock may still read the
///   old time until the seek lands), and the cards for moments after picture time go. The
///   detector's own rules do the rest: a jump of over 10 s, a step back, 2 s of quiet after any
///   of them, a yellow at most once a minute of picture time.
/// - Cards only while the multiview's closed layout shows (`setCardsShown`), only from a host
///   that can jump, and only the groups switched on in Settings (`CardStack`). Newest first.
/// - Closed → open with a card showing, or a tap on it while closed (or on any phone without a
///   fold): every feed jumps to the card's `t − rewindSeconds`, and "Back to where you were"
///   shows for 15 s. The event jumped to brings no second card when play crosses it again.
/// - `hapticEvents`: every event crossed in normal play, cards or not, for Task 13.
@MainActor
@Observable
final class CompanionController {
    static let tickInterval: Duration = .milliseconds(500)
    /// Ticks after a changed seek generation that still count as a seek (as the radio's).
    static let seekTicks = 2

    /// The cards, newest first (`CardStack`).
    private(set) var cards: [CompanionEvent] = []
    /// After a jump: the card's title and when the chip goes.
    private(set) var backChip: (title: String, until: Date)?
    /// Your driver's racing number in this session, if any.
    private(set) var favourite: String?

    @ObservationIgnored let settings: CompanionSettings
    @ObservationIgnored let timing: TimingController
    @ObservationIgnored let radio: RadioController
    @ObservationIgnored private weak var host: (any PlaybackHost)?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var detector = EventDetector()
    @ObservationIgnored private var stack = CardStack()
    @ObservationIgnored private var lastSeekGeneration: Int?
    @ObservationIgnored private var seekTicksLeft = 0
    @ObservationIgnored private var sessionID: String?
    /// The multiview's closed layout shows: cards are made.
    @ObservationIgnored private(set) var cardsShown = false
    @ObservationIgnored private var hapticListeners: [UUID: AsyncStream<CompanionEvent>.Continuation] = [:]

    init(settings: CompanionSettings, timing: TimingController, radio: RadioController,
         now: (@MainActor () -> Date)? = nil) {
        self.settings = settings
        self.timing = timing
        self.radio = radio
        self.now = now ?? { Date() }
    }

    isolated deinit {
        tickTask?.cancel()
        for continuation in hapticListeners.values { continuation.finish() }
    }

    // MARK: Hosts

    /// The player now playing (the multiview, or the single-feed player for haptics only).
    func attach(host newHost: any PlaybackHost) {
        if let host, host !== newHost { forget() }
        host = newHost
        lastSeekGeneration = nil
        seekTicksLeft = 0
        startTicking()
        tick()
    }

    /// Detaches only when `candidate` is the attached host: the cards, the chip and the session go.
    func detach(host candidate: any PlaybackHost) {
        guard let host, host === candidate else { return }
        self.host = nil
        tickTask?.cancel()
        tickTask = nil
        forget()
    }

    /// The multiview's closed layout came on screen or went. Gone, its cards go too.
    func setCardsShown(_ shown: Bool) {
        guard cardsShown != shown else { return }
        cardsShown = shown
        if !shown { setStack { $0.removeAll() } }
    }

    // MARK: Cards

    /// The viewer swiped the top card away: unfolding then simply carries on.
    func dismissTop() {
        setStack { $0.dismissTop() }
    }

    /// The fold moved. Closed → open with a card showing jumps to it. Call it before the closed
    /// layout is reported gone (`setCardsShown(false)`), which clears the cards.
    func postureChanged(from old: Posture, to new: Posture) {
        guard old == .closed, new != .closed, let card = stack.top else { return }
        jump(to: card)
    }

    /// A tap on the top card: the jump (a phone without a fold, or the Duo while closed).
    func tapCard() {
        guard let card = stack.top else { return }
        jump(to: card)
    }

    /// "Back to where you were".
    func back() {
        guard backChip != nil else { return }
        backChip = nil
        (host as? any CompanionJumpHost)?.jumpBack()
    }

    private func jump(to card: CompanionEvent) {
        guard let host = host as? any CompanionJumpHost else { return }
        let target = CompanionModels.jumpMoment(card, rewindSeconds: settings.rewindSeconds)
        guard host.jump(toPictureTime: target) else { return }
        let drivers = timing.loadedSession?.drivers ?? [:]
        setStack { $0.jumped(to: card) }
        backChip = (title: CompanionModels.cardTitle(card, drivers: drivers),
                    until: CompanionModels.backChipUntil(from: now()))
    }

    // MARK: Haptics

    /// Every event crossed in normal play, from now on (each read is its own stream; a slow reader
    /// keeps the newest 16).
    var hapticEvents: AsyncStream<CompanionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CompanionEvent.self, bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        hapticListeners[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.hapticListeners[id] = nil }
        }
        return stream
    }

    // MARK: The tick

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: CompanionController.tickInterval)
                } catch {
                    return
                }
                self?.tick()
            }
        }
    }

    /// One look at picture time: the chip's time, seeks, the events crossed.
    func tick() {
        if let chip = backChip, !CompanionModels.chipShows(until: chip.until, now: now()) { backChip = nil }
        guard let host, let session = timing.loadedSession else {
            forgetSession()
            return
        }
        let id = "\(session.info.key.map { String($0) } ?? "")|\(session.info.path)"
        if id != sessionID {
            sessionID = id
            detector = EventDetector()
            setStack { $0.removeAll() }
            backChip = nil
        }
        let mine = timing.favouriteDriverName.flatMap { Tower.carNumber(forDriver: $0, in: session) }
        if favourite != mine { favourite = mine }

        let generation = host.seekGeneration
        if let last = lastSeekGeneration, last != generation { seekTicksLeft = Self.seekTicks }
        lastSeekGeneration = generation
        let motion: PictureMotion = seekTicksLeft > 0 ? .seek : .play
        if seekTicksLeft > 0 { seekTicksLeft -= 1 }

        guard let t = timing.pictureTime else { return }
        if motion == .seek { setStack { $0.dropLater(than: t) } }
        let events = detector.step(to: t, motion: motion, session: session, radio: session.radio,
                                   favourite: mine, listening: [])
        guard !events.isEmpty else { return }
        for event in events {
            for continuation in hapticListeners.values { continuation.yield(event) }
        }
        if cardsShown, host is any CompanionJumpHost {
            let settings = settings
            setStack { $0.add(events, favourite: mine, groupOn: { settings.cardGroupOn($0) }) }
        }
    }

    /// Changes the stack and publishes its cards only when they changed.
    private func setStack(_ change: (inout CardStack) -> Void) {
        change(&stack)
        if cards != stack.cards { cards = stack.cards }
    }

    /// No session: no cards, no chip, a fresh detector.
    private func forgetSession() {
        guard sessionID != nil || !stack.cards.isEmpty || backChip != nil else { return }
        sessionID = nil
        detector = EventDetector()
        setStack { $0.removeAll() }
        backChip = nil
    }

    private func forget() {
        lastSeekGeneration = nil
        seekTicksLeft = 0
        forgetSession()
        if favourite != nil { favourite = nil }
    }
}

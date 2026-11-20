import AVFoundation
import AVKit
import F1TV
import Foundation
import Library
import LiveTiming
import Multiview
import Observation
import UIKit

/// Plays one feed at a time: asks F1 TV for the stream, drives an `AVPlayer`, saves the place
/// (bookmark and watch history) while playing, and tears everything down on `close()`.
/// It also holds AVKit's player view controller (the picture only; the app's own controls sit on
/// it), so picture in picture outlives the cover: it starts by itself on leaving the app, and the
/// window's restore brings the cover back with the same view controller.
/// It attaches the session's timing (shared with the multiview) once the PLAY is answered, with a
/// clock reading this player's program date and position, and detaches it on close.
/// Tap a car (`showOnboard`) switches to that car's onboard at the same moment; an onboard shows
/// its driver card.
/// Never logs or prints the stream URL, tokens or `PlayInfo`.
@MainActor
@Observable
final class PlayerController {
    /// The player to show; nil while loading or after an error.
    private(set) var player: AVPlayer?
    /// True from the moment a start is requested until `close()`: the full-screen cover follows it.
    private(set) var isPresented = false
    private(set) var isLoading = false
    var errorText: String?
    /// The resume banner's "×": hides it for this run.
    var resumeBannerDismissed = false
    /// Picture in picture is showing this player. The cover may be hidden meanwhile: the player
    /// and its play session stay until the window closes.
    private(set) var isInPictureInPicture = false
    /// The onboard playing, for its driver card; nil for any other feed.
    private(set) var onboard: PlayerOnboard?
    /// One short line for the viewer ("No onboard for car 44 in this session."); clears itself
    /// after 6 s.
    private(set) var notice: String?

    @ObservationIgnored private let coordinator: PlayCoordinator
    @ObservationIgnored private let recents: RecentsStore
    @ObservationIgnored private let history: WatchHistory
    @ObservationIgnored private let catalogue: Catalogue
    /// F1 TV's session, for FairPlay keys (live streams).
    @ObservationIgnored private let f1: F1TVSession
    /// The key handler of the FairPlay stream playing now, kept for the whole playback.
    @ObservationIgnored private var fairPlayKeys: FairPlayKeys?
    /// The session's timing, shared with the multiview; the cover's map panel reads it.
    @ObservationIgnored let timing: TimingController

    @ObservationIgnored private var currentItem: CatalogItem?
    @ObservationIgnored private var currentChannel: Channel?
    /// Saving waits until the item is ready (and any resume seek is done), so a not-yet-seeked
    /// position 0 never overwrites a good bookmark.
    @ObservationIgnored private var canSave = false
    /// Where to start, decided against the real timeline once the item is ready.
    @ObservationIgnored private var pendingStart: Start = .position(0)
    /// Tap-a-car: the moment (program date) the new onboard starts at, ahead of `pendingStart`,
    /// which stands in when the stream has no date there.
    @ObservationIgnored private var pendingDate: Date?
    /// The item whose seek to `pendingDate` AVFoundation accepted: only its completion plays and
    /// allows saving (a refused date seek's handler, should one come, must not).
    @ObservationIgnored private var dateSeekItemID: ObjectIdentifier?
    /// The session's feeds, for tap-a-car: fetched once per content.
    @ObservationIgnored private var sessionChannels: (contentId: Int, channels: [Channel])?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// The AVPlayerItem callbacks are for; anything from another item is dropped.
    @ObservationIgnored private var currentItemID: ObjectIdentifier?
    /// Bumped by every start, resume and close, so a slow answer for something superseded is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    /// "From the start" of a live session: waits for the item's seekable range, seeks to the
    /// start, then plays. Cancelled by any teardown.
    @ObservationIgnored private var beginningTask: Task<Void, Never>?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observedPlayer: AVPlayer?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    /// AVKit's view controller for `player`, kept here rather than by the cover's view, so hiding
    /// the cover never ends picture in picture. A new player gets a new one.
    @ObservationIgnored private var playerViewController: AVPlayerViewController?
    /// AVKit holds its delegate weakly: this keeps it.
    @ObservationIgnored private let pictureInPictureDelegate: PlayerPictureInPictureDelegate
    /// What the app's own controls show (play, scrubber, LIVE, speed, audio). Refreshed twice a
    /// second; its own object, so the cover's body never redraws for it.
    @ObservationIgnored let transport = PlayerTransport()
    @ObservationIgnored private var transportObserver: Any?
    /// The playing item's audio choices (commentary languages), once loaded.
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    /// A seek's target, shown by the scrubber until the player gets there.
    @ObservationIgnored private var seekTarget: Double?

    static let saveInterval: Double = 5
    /// How long a notice stays up, as the multiview's.
    static let noticeDuration: Duration = .seconds(6)
    /// Tap-a-car couldn't get the session's feeds (offline, or F1 TV didn't answer).
    static let noFeedsNotice = "Couldn't load this session's onboards. Check your connection and try again."
    /// "From the start" checks for the seekable range this often, this many times (10 s), then
    /// plays live.
    static let beginningPoll: Duration = .milliseconds(250)
    static let beginningAttempts = 40

    init(coordinator: PlayCoordinator, recents: RecentsStore, history: WatchHistory, catalogue: Catalogue,
         timing: TimingController, f1: F1TVSession) {
        self.coordinator = coordinator
        self.f1 = f1
        self.recents = recents
        self.history = history
        self.catalogue = catalogue
        self.timing = timing
        pictureInPictureDelegate = PlayerPictureInPictureDelegate()
        pictureInPictureDelegate.owner = self
    }

    isolated deinit {
        removeObservers()
        noticeTask?.cancel()
    }

    // MARK: Starting

    /// Plays from a tile: a replay with a recent bookmark for this feed resumes there, any other
    /// replay starts at 0, and a live session at the live edge, or at its start when the viewer
    /// chose "From the start" (`fromStart`).
    func play(item: CatalogItem, channel: Channel, fromStart: Bool = false) async {
        var start: Start = item.isLive ? .liveEdge : .position(0)
        if fromStart {
            start = .beginning
        } else if let bookmark = recents.all().first(where: { $0.contentId == item.contentId && $0.channelId == channel.id }) {
            start = ResumePlan.make(
                bookmark: bookmark,
                availableChannelIds: [channel.id],
                defaultChannelId: channel.id,
                isLiveNow: item.isLive,
                durationMs: item.durationSeconds.map { Int64($0) * 1_000 }).start
        }
        await self.start(item: item, channel: channel, startAt: start)
    }

    /// `at`: tap-a-car's moment, the program date the new feed starts at when its stream has one
    /// (else `startAt`).
    func start(item: CatalogItem, channel: Channel, startAt: Start, at date: Date? = nil) async {
        // Asking for what is already on screen changes nothing (and never sends a second PLAY).
        if player != nil, errorText == nil, currentItem?.contentId == item.contentId, currentChannel?.id == channel.id {
            // `resume` may have set the spinner; this player is already past loading.
            isLoading = false
            isPresented = true
            return
        }
        generation += 1
        let mine = generation
        // Keep the place in the feed being left, then drop it.
        save()
        teardownPlayback()
        // Another feed of the same session keeps its timing; other content drops it.
        if currentItem?.contentId != item.contentId { timing.detach(owner: self) }
        // The feed before had its own card: none until this one plays, so a failed PLAY leaves
        // no card, tick or car data download behind.
        timing.setCardFeeds([:], owner: self)
        currentItem = item
        currentChannel = channel
        let card = PlayerOnboard(channel)
        if onboard != card { onboard = card }
        errorText = nil
        isLoading = true
        isPresented = true

        // A close() just before this must finish its stop() first, or it could end this play.
        if let stopTask { await stopTask.value }
        guard generation == mine else { return }

        let info: PlayInfo
        do {
            // F1 TV's own link decides the channelId: none for the main INTERNATIONAL feed (else 404).
            info = try await coordinator.play(contentId: item.contentId, channelId: channel.playChannelId)
        } catch is CancellationError {
            // Superseded (silent), or cancelled from outside with nothing newer: leave the player.
            if generation == mine { dismiss() }
            return
        } catch {
            guard generation == mine else { return }
            isLoading = false
            errorText = Self.message(for: error)
            return
        }
        guard generation == mine else { return }
        timing.attach(item: item, owner: self, clock: { [weak self] in
            guard let self else { return (programDate: nil, playerSeconds: .nan) }
            return self.timingClock()
        })
        // An onboard gets its driver card (unless hidden).
        timing.setCardFeeds(card.map { [$0.channelId: $0.number] } ?? [:], owner: self)
        // Live sessions come as FairPlay: their keys come from F1 TV's licence service. Replays
        // are clear and take the plain path, as before.
        begin(url: info.url, license: info.isFairPlay ? info.licenseURL : nil, startAt: startAt, date: date)
    }

    // MARK: Tap a car

    /// Tap a car (map, tower, Battle chip): switches to that car's onboard at the same moment,
    /// the program date when the stream has one, else the same position (the live edge for a
    /// live stream without dates). Returns the notice when the session has no onboard for it
    /// ("No onboard for car 44 in this session."), else nil. Its own onboard changes nothing.
    @discardableResult
    func showOnboard(racingNumber: Int) async -> String? {
        guard let item = currentItem, let current = currentChannel, let player, errorText == nil, !isLoading,
              !(current.isOnboard && current.racingNumber == racingNumber) else { return nil }
        // Read before the fetch, so the moment is the tap's.
        let date = player.currentItem?.currentDate()
        let now = player.currentTime()
        let live = player.currentItem?.duration.isIndefinite ?? item.isLive
        let start: Start = live || !now.isNumeric ? .liveEdge : .position(max(Int64((now.seconds * 1_000).rounded()), 0))
        let channels = await channels(for: item.contentId)
        guard currentItem?.contentId == item.contentId else { return nil }
        guard let channels else {
            showNotice(Self.noFeedsNotice)
            return Self.noFeedsNotice
        }
        guard let onboard = channels.first(where: { $0.isOnboard && $0.racingNumber == racingNumber && $0.id != nil }) else {
            let message = Placement.noOnboard(racingNumber).message
            if let message { showNotice(message) }
            return message
        }
        await self.start(item: item, channel: onboard, startAt: start, at: date)
        return nil
    }

    /// The session's feeds (once per content); nil when they can't be had.
    private func channels(for contentId: Int) async -> [Channel]? {
        if let sessionChannels, sessionChannels.contentId == contentId { return sessionChannels.channels }
        guard let detail = try? await catalogue.video(contentId: contentId) else { return nil }
        sessionChannels = (contentId, detail.channels)
        return detail.channels
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: PlayerController.noticeDuration)
            } catch {
                return
            }
            self?.notice = nil
        }
    }

    /// The viewer tapped the notice away.
    func dismissNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }

    /// Resumes a bookmark: fetches the session's feeds, plans the start and plays.
    func resume(_ bookmark: WatchBookmark) async {
        generation += 1
        let mine = generation
        errorText = nil
        isLoading = true
        isPresented = true
        let detail: VideoDetail
        do {
            detail = try await catalogue.video(contentId: bookmark.contentId)
        } catch is CancellationError {
            if generation == mine { dismiss() }
            return
        } catch {
            guard generation == mine else { return }
            isLoading = false
            errorText = Self.message(for: error)
            return
        }
        guard generation == mine else { return }
        // Saved live is not live now: only F1 TV's live-now list makes the item live.
        var liveNow: [CatalogItem]?
        if LiveResume.needsCheck(bookmark) {
            liveNow = try? await catalogue.liveNow()
            if Task.isCancelled {
                if generation == mine { dismiss() }
                return
            }
            guard generation == mine else { return }
        }
        let channels = detail.channels
        let defaultId = (channels.first(where: \.isDefault) ?? channels.first)?.id
        let plan = ResumePlan.make(
            bookmark: bookmark,
            availableChannelIds: channels.map(\.id),
            defaultChannelId: defaultId,
            isLiveNow: bookmark.live,
            durationMs: bookmark.durationMs)
        let channel = channels.first(where: { $0.id == plan.channelId }) ?? Channel(id: plan.channelId, isDefault: true)
        // Live (live timing, the next-live check) only while F1 TV lists it live now.
        let item = LiveResume.item(bookmark, detail: detail, isLive: LiveResume.isLive(bookmark, liveNow: liveNow))
        await start(item: item, channel: channel, startAt: plan.start)
    }

    // MARK: Closing

    func close() {
        save()
        generation += 1
        teardownPlayback()
        timing.detach(owner: self)
        currentItem = nil
        currentChannel = nil
        onboard = nil
        sessionChannels = nil
        dismissNotice()
        errorText = nil
        isLoading = false
        isPresented = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let coordinator = coordinator
        let previous = stopTask
        stopTask = Task {
            await previous?.value
            await coordinator.stop()
        }
    }

    /// Waits until the stop() of every close() so far has landed on the shared play session. The
    /// multiview waits for this before its PLAY, or the player's stop could end that PLAY.
    func waitForStop() async {
        if let stopTask { await stopTask.value }
    }

    /// The cover went away by itself (the root's binding): closes, unless picture in picture is
    /// what hid it, which keeps the player.
    func coverDismissed() {
        guard !isInPictureInPicture else { return }
        close()
    }

    /// Hides the cover without a stop(): nothing was playing (a cancelled request).
    private func dismiss() {
        teardownPlayback()
        timing.detach(owner: self)
        currentItem = nil
        currentChannel = nil
        onboard = nil
        sessionChannels = nil
        dismissNotice()
        isLoading = false
        isPresented = false
    }

    // MARK: Timing

    /// The program date and position of what plays, read together (picture time's inputs).
    private func timingClock() -> (programDate: Date?, playerSeconds: Double) {
        guard let item = player?.currentItem else { return (programDate: nil, playerSeconds: .nan) }
        let now = item.currentTime()
        return (programDate: item.currentDate(), playerSeconds: now.isNumeric ? now.seconds : .nan)
    }

    // MARK: Picture in picture

    /// The view controller the cover shows for `player`: the same one each time the cover comes
    /// back, so a picture in picture it started keeps going. Touches only unobserved state (it is
    /// called while SwiftUI makes the view).
    func playerViewController(for player: AVPlayer) -> AVPlayerViewController {
        if let existing = playerViewController {
            if existing.player !== player { existing.player = player }
            return existing
        }
        let viewController = AVPlayerViewController()
        viewController.player = player
        // The app's own controls instead (`PlayerChrome`, owner 2026-11-20, option B).
        viewController.showsPlaybackControls = false
        viewController.allowsPictureInPicturePlayback = true
        viewController.canStartPictureInPictureAutomaticallyFromInline = true
        viewController.delegate = pictureInPictureDelegate
        playerViewController = viewController
        return viewController
    }

    fileprivate func pictureInPictureWillStart() {
        guard player != nil else { return }
        isInPictureInPicture = true
    }

    /// Started with the app in front (no button for it now, since AVKit's controls are off; kept
    /// in case iOS starts it another way): the cover steps aside so the app can be used while the
    /// window plays. Started on leaving the app, the cover stays.
    fileprivate func pictureInPictureDidStart() {
        guard isInPictureInPicture, isPresented, UIApplication.shared.applicationState == .active else { return }
        isPresented = false
    }

    fileprivate func pictureInPictureFailed() {
        guard isInPictureInPicture else { return }
        isInPictureInPicture = false
        if player != nil, !isPresented { isPresented = true }
    }

    /// The window's restore: the cover comes back (with the same view controller). Answers
    /// whether there is a player to come back to.
    fileprivate func pictureInPictureRestore() -> Bool {
        guard player != nil, currentItem != nil else { return false }
        isLoading = false
        if !isPresented { isPresented = true }
        return true
    }

    /// The window closed. Without a restore and with the cover hidden, nothing would show the
    /// player again: that is a close (saved first). With the cover up, the player stays, paused.
    fileprivate func pictureInPictureDidStop() {
        guard isInPictureInPicture else { return }
        isInPictureInPicture = false
        if !isPresented { close() }
    }

    // MARK: Playback

    private func begin(url: URL, license: URL? = nil, startAt: Start, date: Date? = nil) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        let item: AVPlayerItem
        if let license {
            // The key session takes the asset before the item exists, so the first key request
            // goes to it.
            let asset = AVURLAsset(url: url)
            let keys = FairPlayKeys(f1: f1, licenseURL: license)
            keys.attach(asset)
            fairPlayKeys = keys
            item = AVPlayerItem(asset: asset)
        } else {
            item = AVPlayerItem(url: url)
        }
        let player = AVPlayer(playerItem: item)
        pendingStart = startAt
        pendingDate = date
        let itemID = ObjectIdentifier(item)
        currentItemID = itemID
        canSave = false
        self.player = player
        observedPlayer = player

        // The callbacks may arrive on any thread: they carry only the item's identity, hop to the
        // main actor, and read the item there.
        statusObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor [weak self] in self?.statusChanged(itemID: itemID) }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.saveInterval, preferredTimescale: 1), queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.tick(itemID: itemID) }
        }
        transport.reset()
        seekTarget = nil
        audioGroup = nil
        transportObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 2), queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTransport(itemID: itemID) }
        }
        item.asset.loadMediaSelectionGroup(for: .audible) { @Sendable [weak self] group, _ in
            let box = PlayerAudioGroupBox(group)
            Task { @MainActor [weak self] in self?.audioGroupLoaded(itemID: itemID, box: box) }
        }

        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { @Sendable [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let reason = error?.localizedDescription ?? ""
            Task { @MainActor [weak self] in
                guard self?.currentItemID == itemID else { return }
                self?.feedStopped(reason: reason)
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.currentItemID == itemID else { return }
                self?.save()
            }
        })
        // The one background save: no scenePhase involved, so nothing saves twice. Delivered on
        // the main queue, so it runs now, before the app can be suspended.
        notificationTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        })
    }

    private func statusChanged(itemID: ObjectIdentifier) {
        guard itemID == currentItemID, let player, let item = player.currentItem,
              ObjectIdentifier(item) == itemID else { return }
        switch item.status {
        case .readyToPlay:
            guard !canSave else {
                isLoading = false
                return
            }
            // "From the start" is under way: the spinner stays until its seek lands.
            guard beginningTask == nil else { return }
            let duration = item.duration
            let timeline: Timeline = duration.isIndefinite
                ? .live
                : .replay(durationMs: duration.isNumeric ? Int64((duration.seconds * 1_000).rounded()) : 0)
            let start = pendingStart.resolved(for: timeline)
            pendingStart = .position(0)
            let date = pendingDate
            pendingDate = nil
            if let date {
                // Tap-a-car: the same moment as the feed it came from, by the streams' own dates.
                // False when this stream has no date there: the position below stands in.
                isLoading = false
                let accepted = item.seek(to: date) { @Sendable [weak self] _ in
                    // Runs after the flag below is set: the hop queues behind this call.
                    Task { @MainActor [weak self] in
                        // Dropped if the item was replaced or closed while seeking, or if the
                        // date seek was refused (the position seek below is the one that counts).
                        guard let self, self.currentItemID == itemID, self.dateSeekItemID == itemID,
                              let current = self.player else { return }
                        self.dateSeekItemID = nil
                        self.canSave = true
                        current.play()
                    }
                }
                if accepted {
                    dateSeekItemID = itemID
                    return
                }
            }
            if start == .beginning {
                // A live session from its start (Android 0.98): nothing plays, and the spinner
                // stays over the picture, until the seek to the start lands.
                startFromBeginning(itemID: itemID)
                return
            }
            isLoading = false
            if case .position(let ms) = start, ms > 0 {
                let target = CMTime(value: CMTimeValue(ms), timescale: 1_000)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] _ in
                    Task { @MainActor [weak self] in
                        // Dropped if the item was replaced or closed while seeking.
                        guard let self, self.currentItemID == itemID, let current = self.player else { return }
                        self.canSave = true
                        current.play()
                    }
                }
            } else {
                // The live edge, or the beginning: AVKit starts there on its own.
                canSave = true
                player.play()
            }
        case .failed:
            // A FairPlay key that couldn't be had says why, rather than AVFoundation's generic text.
            let reason = fairPlayKeys?.lastFailure.map { "couldn't unlock this live stream: \($0)" }
            feedStopped(reason: reason ?? item.error?.localizedDescription ?? "")
        default:
            break
        }
    }

    /// Tries now, then every 250 ms for 10 s, to seek to the session's start: the item's seekable
    /// range is often, but not always, in when it reports ready.
    private func startFromBeginning(itemID: ObjectIdentifier) {
        beginningTask?.cancel()
        beginningTask = Task { [weak self] in
            var attempt = 0
            while true {
                guard let done = self?.tryStartFromBeginning(
                    itemID: itemID, giveUp: attempt >= PlayerController.beginningAttempts), !done else { return }
                attempt += 1
                do {
                    try await Task.sleep(for: PlayerController.beginningPoll)
                } catch {
                    return
                }
            }
        }
    }

    /// One try: true when finished (sought, gave up and played live, or the item is gone).
    private func tryStartFromBeginning(itemID: ObjectIdentifier, giveUp: Bool) -> Bool {
        guard itemID == currentItemID, let player, let item = player.currentItem,
              ObjectIdentifier(item) == itemID else { return true }
        if let seconds = Self.beginningSeconds(of: item, sessionStart: currentItem?.start) {
            let target = CMTime(seconds: seconds, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    // Dropped if the item was replaced or closed while seeking.
                    guard let self, self.currentItemID == itemID, let current = self.player else { return }
                    self.isLoading = false
                    self.canSave = true
                    current.play()
                }
            }
            return true
        }
        guard giveUp else { return false }
        // The range never came: live, rather than a spinner for ever.
        isLoading = false
        canSave = true
        player.play()
        return true
    }

    /// Where "From the start" begins in this item, in seconds on its timeline, once its seekable
    /// range is known (nil until then): the session's start within what the stream keeps, by
    /// program date, else the earliest moment it keeps (`LiveStart.beginning`).
    static func beginningSeconds(of item: AVPlayerItem, sessionStart: Date?) -> Double? {
        let ranges = item.seekableTimeRanges.map(\.timeRangeValue)
        guard let first = ranges.first, let last = ranges.last else { return nil }
        let start = first.start
        let end = last.end
        guard start.isNumeric, end.isNumeric, start.seconds.isFinite, end.seconds.isFinite,
              end.seconds > start.seconds else { return nil }
        let now = item.currentTime()
        return LiveStart.beginning(
            seekable: start.seconds...end.seconds,
            current: now.isNumeric ? now.seconds : .nan,
            currentDate: item.currentDate(),
            sessionStart: sessionStart)
    }

    private func feedStopped(reason: String) {
        guard player != nil else { return }
        save()
        teardownPlayback()
        isLoading = false
        errorText = Self.stoppedMessage(reason)
        // Playing in picture in picture with the cover hidden: the cover comes back with the
        // reason and its Close, rather than leave a session nobody sees.
        if !isPresented { isPresented = true }
    }

    /// Every 5 s once saving is possible, playing or not, so a seek or pause just before the app
    /// is killed keeps its position. Paused ticks leave the watch history alone (it counts time).
    private func tick(itemID: ObjectIdentifier) {
        guard itemID == currentItemID, let player else { return }
        save(recordHistory: player.timeControlStatus == .playing)
    }

    /// Bookmark and watch history, together. Skipped until the item is ready.
    private func save(recordHistory: Bool = true) {
        guard canSave, let item = currentItem, let channel = currentChannel,
              let player, let playerItem = player.currentItem else { return }
        let duration = playerItem.duration
        let live = duration.isIndefinite
        let now = player.currentTime()
        let positionMs = live || !now.isNumeric ? 0 : max(Int64((now.seconds * 1_000).rounded()), 0)
        let durationMs = live || !duration.isNumeric ? 0 : max(Int64((duration.seconds * 1_000).rounded()), 0)
        recents.save(WatchBookmark(
            contentId: item.contentId,
            title: item.title,
            picturePath: item.picturePath,
            channelId: channel.id,
            positionMs: positionMs,
            durationMs: durationMs,
            live: live,
            savedAt: Date()))
        if recordHistory {
            history.record(contentId: item.contentId, positionMs: positionMs, durationMs: durationMs)
        }
    }

    private func teardownPlayback() {
        beginningTask?.cancel()
        beginningTask = nil
        fairPlayKeys?.stop()
        fairPlayKeys = nil
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        // Ends a picture in picture still up; its stop then finds nothing to do.
        isInPictureInPicture = false
        playerViewController?.player = nil
        playerViewController = nil
        player = nil
        canSave = false
        pendingStart = .position(0)
        pendingDate = nil
        dateSeekItemID = nil
        currentItemID = nil
    }

    private func removeObservers() {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let transportObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(transportObserver)
        }
        transportObserver = nil
        audioGroup = nil
        seekTarget = nil
        transport.reset()
        observedPlayer = nil
        statusObservation?.invalidate()
        statusObservation = nil
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens = []
    }

    // MARK: The app's own controls

    /// Play or pause. Playing goes at the chosen speed (`defaultRate`).
    func togglePlay() {
        guard let player else { return }
        if player.timeControlStatus == .paused {
            player.play()
        } else {
            player.pause()
        }
        refreshTransport()
    }

    /// Moves to `seconds`, kept inside the scrubber's span.
    func seek(toSeconds seconds: Double) {
        guard let player, seconds.isFinite else { return }
        var target = max(seconds, 0)
        if let span = transport.timeline { target = min(max(target, span.lowerBound), span.upperBound) }
        seekTarget = target
        let itemID = currentItemID
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: CMTime(value: 1, timescale: 2),
                    toleranceAfter: CMTime(value: 1, timescale: 2)) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentItemID == itemID else { return }
                self.seekTarget = nil
                self.refreshTransport()
            }
        }
        refreshTransport()
    }

    /// Back or forward 10 s.
    func skip(by seconds: Double) {
        seek(toSeconds: transport.position + seconds)
    }

    /// The LIVE button: back to the live point. It only moves; a paused player stays paused.
    func goLive() {
        refreshTransport()
        guard transport.isLive, let span = transport.timeline else { return }
        seek(toSeconds: span.upperBound)
    }

    /// One speed, kept for this video until it closes or switches.
    func setRate(_ newRate: Double) {
        guard newRate.isFinite, newRate > 0, let player else { return }
        player.defaultRate = Float(newRate)
        if player.timeControlStatus != .paused { player.rate = Float(newRate) }
        transport.setRate(newRate)
    }

    /// One of `transport.audioOptions` (the commentary language), for the playing item.
    func selectAudioOption(_ id: Int) {
        guard let group = audioGroup, let item = player?.currentItem, group.options.indices.contains(id) else { return }
        item.select(group.options[id], in: group)
        transport.setAudio(options: transport.audioOptions, selected: id)
    }

    private func refreshTransport(itemID: ObjectIdentifier? = nil) {
        if let itemID, itemID != currentItemID { return }
        guard let player else { return }
        transport.update(player: player, heldPosition: seekTarget)
        // At the live point the speed menu hides, so any other speed goes back to 1× there (as
        // in multiview).
        if transport.isLive, transport.rate != 1, transport.behindLive != nil, transport.isAtLiveEdge {
            setRate(1)
            showNotice(MultiviewController.caughtUpNotice)
        }
    }

    private func audioGroupLoaded(itemID: ObjectIdentifier, box: PlayerAudioGroupBox) {
        guard itemID == currentItemID, let item = player?.currentItem, let group = box.group else { return }
        audioGroup = group
        let current = item.currentMediaSelection.selectedMediaOption(in: group)
        var options: [MultiviewAudioOption] = []
        var selected: Int?
        for (index, option) in group.options.enumerated() {
            let name = option.displayName
            options.append(MultiviewAudioOption(id: index, name: name.isEmpty ? "Track \(index + 1)" : name))
            if let current, option == current { selected = index }
        }
        transport.setAudio(options: options, selected: selected)
    }

    // MARK: Messages

    static func message(for error: Error) -> String {
        switch error {
        case F1TVError.protectedContent:
            return "This session is protected and can't play in this app yet"
        case F1TVError.refused, F1TVError.noVideoPlan:
            return "F1 TV won't play this on your account. Its plan may not include this session."
        case F1TVError.notSignedIn:
            return AppModel.signInPrompt
        case F1TVError.network(let reason):
            let text = sanitized(reason)
            return text.isEmpty ? "Couldn't load F1 TV." : "Couldn't load F1 TV: \(text)"
        case let error as F1TVError where !error.detail.isEmpty:
            // F1 TV's own reason (its error number and words), without any link.
            let text = sanitized(error.detail)
            return text.isEmpty ? "Couldn't load F1 TV." : "Couldn't load F1 TV: \(text)."
        default:
            return "Couldn't load F1 TV."
        }
    }

    static func stoppedMessage(_ reason: String) -> String {
        let text = sanitized(reason)
        return text.isEmpty ? "This feed stopped." : "This feed stopped: \(text)."
    }

    /// Drops anything that looks like a link (AVFoundation can put the stream URL in an error),
    /// then tidies what is left.
    static func sanitized(_ reason: String) -> String {
        var text = reason.replacingOccurrences(
            of: #"[A-Za-z][A-Za-z0-9+.\-]*://\S*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:,;()-"))
        return text.trimmingCharacters(in: trim)
    }
}

/// AVKit's picture-in-picture callbacks for the single-feed player. `nonisolated`, so they satisfy
/// the protocol whether or not the SDK isolates it to the main actor; only plain values (and a
/// boxed completion handler) go to the main actor, at once when called on the main thread as
/// AVKit does, so a restore and the stop after it are handled in order.
@MainActor
final class PlayerPictureInPictureDelegate: NSObject, AVPlayerViewControllerDelegate {
    weak var owner: PlayerController?

    /// The app hides the cover itself (only when started from inside the app), keeping the view
    /// controller; AVKit dismissing it would take the cover away behind SwiftUI's back.
    nonisolated func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
        _ playerViewController: AVPlayerViewController
    ) -> Bool {
        false
    }

    nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        onMainActor { [weak self] in self?.owner?.pictureInPictureWillStart() }
    }

    nonisolated func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        onMainActor { [weak self] in self?.owner?.pictureInPictureDidStart() }
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        onMainActor { [weak self] in self?.owner?.pictureInPictureFailed() }
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        let completion = PictureInPictureCompletion(completionHandler)
        onMainActor { [weak self] in
            let restored = self?.owner?.pictureInPictureRestore() ?? false
            completion.call(restored)
        }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        onMainActor { [weak self] in self?.owner?.pictureInPictureDidStop() }
    }
}

/// AVKit's restore completion handler, carried to the main actor. Unchecked: the SDK doesn't mark
/// the handler Sendable, but AVKit hands it over on the main thread and it is called once, on the
/// main actor.
final class PictureInPictureCompletion: @unchecked Sendable {
    private let handler: (Bool) -> Void

    init(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func call(_ restored: Bool) {
        handler(restored)
    }
}

/// Runs `body` on the main actor: at once when already on the main thread (AVKit's delegate calls
/// are), so calls are handled in the order they came; otherwise as a main-actor task.
nonisolated func onMainActor(_ body: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        Task { @MainActor in body() }
    }
}

/// The onboard the single feed plays, for its driver card: its channel and racing number.
struct PlayerOnboard: Equatable, Sendable {
    let channelId: Int
    let number: String

    /// Nil for a feed that isn't an onboard, or has no id or racing number.
    init?(_ channel: Channel) {
        guard channel.isOnboard, let id = channel.id, let racingNumber = channel.racingNumber else { return nil }
        channelId = id
        number = String(racingNumber)
    }
}

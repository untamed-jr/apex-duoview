import F1TV
import Foundation
import Library
import LiveTiming
import Multiview
import Observation

enum AuthState: Equatable {
    case signedOut
    case signingIn
    case signedIn(Account)
}

@MainActor
@Observable
final class AppModel {
    static let expiredMessage = "Your F1 TV sign-in has expired. Sign in again."
    static let signInPrompt = "Sign in to watch."

    var auth: AuthState = .signedOut
    var message: String?
    /// A token is saved but the last launch attempt failed for network or server reasons (not
    /// refused). Foreground and the banner's "Try again" retry it; a refusal never does.
    private(set) var restorePending = false

    @ObservationIgnored let session: F1TVSession
    @ObservationIgnored let catalogue: Catalogue
    @ObservationIgnored let player: PlayCoordinator
    @ObservationIgnored let recents: RecentsStore
    @ObservationIgnored let history: WatchHistory
    /// The one player, shown full screen by the root while it has something to show.
    @ObservationIgnored let playback: PlayerController
    /// The one multiview store: its writes are atomic per instance only.
    @ObservationIgnored let multiviewStore: MultiviewStore
    /// The multiview player, shown full screen by the root while it has something to show.
    @ObservationIgnored let multiview: MultiviewController
    /// Timing for whatever plays (F1's archive with this sign-in, MultiViewer's circuits), with the
    /// one `TimingSettings` and `TimingArchive`; both players attach it.
    @ObservationIgnored let timing: TimingController
    /// The beta.4 choices (team radio, the closed phone, haptics), kept between launches.
    @ObservationIgnored let companion: CompanionSettings
    /// Team radio for whatever plays, beside the timing: both players attach it as its host, and
    /// it starts afresh with each session the timing loads. Clips come from F1's archive host only.
    @ObservationIgnored let radio: RadioController
    /// The closed phone's event cards and Unfold to See, and the events for haptics: both players
    /// attach it as its host (the single-feed player for haptics only).
    @ObservationIgnored let companionController: CompanionController
    /// Your driver (Settings › Multiview › My driver): their onboard is the second default feed.
    /// Mirrors the multiview store, which isn't observed.
    private(set) var favouriteDriver: String?
    /// The next live programme offered while a live one is watched (`NextLivePrompt`).
    private(set) var nextLive = NextLiveState()
    /// F1's live timing, one connection for the app (the timing listens while a live item plays).
    @ObservationIgnored let liveTiming: LiveConnection
    /// The 60 s "live now" check, only while a live programme is watched.
    @ObservationIgnored private var nextLiveTask: Task<Void, Never>?

    init() {
        let session = F1TVSession(http: URLSessionHTTPClient())
        let store = UserDefaultsStore()
        let catalogue = Catalogue(session: session)
        let player = PlayCoordinator(session: session)
        let recents = RecentsStore(store: store)
        let history = WatchHistory(store: store)
        self.session = session
        self.catalogue = catalogue
        self.player = player
        self.recents = recents
        self.history = history
        // Its own client: longer timeouts for the archive's large files, and the token never
        // follows a redirect to another host. The token is read from the session when needed.
        let timingHTTP = TimingHTTPClient()
        // Live timing: the same token, read when needed, only ever sent to F1's hub. The
        // recording goes to Caches/live; recordings older than 7 days go at launch.
        let liveTiming = LiveConnection(
            transport: URLSessionLiveTransport(), recorder: LiveRecorder(), token: { await session.bearerToken() })
        self.liveTiming = liveTiming
        Task.detached(priority: .background) {
            LiveRecorder.deleteOld(in: LiveRecorder.defaultDirectory, now: Date())
        }
        let timing = TimingController(
            archive: TimingArchive(http: timingHTTP, token: { await session.bearerToken() }),
            settings: TimingSettings(store: store),
            http: timingHTTP,
            live: liveTiming)
        self.timing = timing
        // Team radio: the timing's own client (the token never follows a redirect to another
        // host), sent only on a refused clip. Clips older than 7 days go at launch.
        let companion = CompanionSettings(store: store)
        self.companion = companion
        let radio = RadioController(settings: companion, timing: timing, http: timingHTTP,
                                    token: { await session.bearerToken() })
        self.radio = radio
        companionController = CompanionController(settings: companion, timing: timing, radio: radio)
        if let radioCache = RadioFetch.defaultBase {
            Task.detached(priority: .background) {
                RadioFetch.deleteExpired(in: radioCache, now: Date())
            }
        }
        self.playback = PlayerController(
            coordinator: player, recents: recents, history: history, catalogue: catalogue, timing: timing,
            radio: radio, f1: session)
        let multiviewStore = MultiviewStore(store: store)
        self.multiviewStore = multiviewStore
        self.multiview = MultiviewController(
            coordinator: player, store: multiviewStore, recents: recents, history: history, timing: timing,
            radio: radio, f1: session)
        favouriteDriver = multiviewStore.favouriteDriver
        // Your driver's battles glow in the tower.
        timing.setFavouriteDriver(favouriteDriver)
    }

    // MARK: The next live programme

    /// What live programme plays (the timing's live item), and whether in multiview; nil when no
    /// live programme plays. The root reports it: the 60 s check runs only while one does.
    func liveWatchChanged(contentId: Int?, multiview: Bool) {
        guard let contentId else {
            nextLiveTask?.cancel()
            nextLiveTask = nil
            nextLive.stop()
            return
        }
        let same = nextLive.watching == contentId
        nextLive.watch(contentId: contentId, multiview: multiview)
        guard !same || nextLiveTask == nil else { return }
        nextLiveTask?.cancel()
        nextLiveTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkLiveNow()
                do {
                    try await Task.sleep(for: NextLiveState.checkInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// One check of F1 TV's "live now" list. A failure learns nothing and offers nothing (and
    /// never signs anyone out).
    private func checkLiveNow() async {
        guard let live = try? await catalogue.liveNow(), !Task.isCancelled, nextLive.watching != nil else { return }
        nextLive.checked(live: live)
    }

    /// "Not now": that programme isn't offered again.
    func declineNextLive() {
        nextLive.decline()
    }

    /// "Switch": opens the offered programme at the live edge, in multiview when that is how the
    /// last one was watched (the multiview shows one feed as well as four), else the single-feed
    /// player on its default feed.
    func switchToNextLive() async {
        let watched = nextLive.watching
        guard let (offer, inMultiview) = nextLive.accept() else { return }
        // A failed fetch puts the prompt back rather than dropping it without a word.
        guard let detail = try? await catalogue.video(contentId: offer.contentId),
              let channel = detail.channels.first(where: \.isDefault) ?? detail.channels.first
        else {
            nextLive.restore(offer, watched: watched)
            return
        }
        var item = offer
        if item.title.isEmpty { item.title = detail.title }
        // The live list's tile may carry no metadata: the video's details say where its timing is.
        if item.timingRef == nil { item.timingRef = detail.timingRef }
        var multiviewAllowed = false
        if case .signedIn(let account) = auth { multiviewAllowed = account.hasMultiview }
        if (inMultiview || multiview.isPresented), multiviewAllowed {
            // The single-feed player's stop() must land before the multiview's PLAY.
            if playback.isPresented || playback.isInPictureInPicture { playback.close() }
            await playback.waitForStop()
            await multiview.open(item: item, detail: detail, startAt: .liveEdge)
        } else {
            await playback.play(item: item, channel: channel)
        }
    }

    // MARK: Your driver

    /// The first-run "Pick your driver" sheet was answered (a driver, or Skip).
    var driverPromptShown: Bool { multiviewStore.driverPromptShown }

    /// The drivers to choose from, by racing number: the onboard feeds of the newest race replay
    /// of this season that has them. If this season has none (or can't load), the newest of the
    /// archive's races (F1 TV's 100 most watched). Empty when those races list no onboards.
    func driverChoices() async throws -> [Channel] {
        let season = Calendar.current.component(.year, from: Date())
        if let thisSeason = try? await catalogue.raceReplays(season: season),
           let drivers = try? await newestDrivers(in: thisSeason), !drivers.isEmpty {
            return drivers
        }
        return try await newestDrivers(in: try await catalogue.archiveRaces())
    }

    /// The onboards of the newest of these races that lists some, trying the newest three. Throws
    /// the last failure when none of them could be read.
    private func newestDrivers(in races: [CatalogItem]) async throws -> [Channel] {
        var lastError: Error?
        var readAny = false
        for race in DriverChoice.newestFirst(races).prefix(3) {
            do {
                let detail = try await catalogue.video(contentId: race.contentId)
                readAny = true
                let drivers = DriverChoice.drivers(in: detail.channels)
                if !drivers.isEmpty { return drivers }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        if !readAny, let lastError { throw lastError }
        return []
    }

    /// Settings › Multiview › My driver. Only the driver changes; the last-used feeds stay.
    func setFavouriteDriver(_ lastName: String?) {
        multiviewStore.favouriteDriver = lastName
        favouriteDriver = multiviewStore.favouriteDriver
        timing.setFavouriteDriver(favouriteDriver)
    }

    /// The first-run sheet's answer: a driver (also resets the last-used feeds to the new
    /// default), or nil for "Skip". Either way it isn't asked again.
    func answerDriverPrompt(_ lastName: String?) {
        if let lastName {
            multiviewStore.favouriteDriver = lastName
            multiviewStore.resetToDefault()
            favouriteDriver = multiviewStore.favouriteDriver
            timing.setFavouriteDriver(favouriteDriver)
        }
        multiviewStore.driverPromptShown = true
    }

    /// Opens a session's multiview where its bookmark left off (a live one at the live edge, or at
    /// its start when the viewer chose "From the start").
    /// The two players share one play session, so the single-feed one closes first, also when only
    /// its picture in picture is showing (never two windows at once), and its stop() lands before
    /// the multiview's PLAY, which it would otherwise end.
    func openMultiview(item: CatalogItem, detail: VideoDetail, fromStart: Bool = false) async {
        if playback.isPresented || playback.isInPictureInPicture { playback.close() }
        await playback.waitForStop()
        let start: Start = fromStart ? .beginning : multiview.resumeStart(for: item)
        await multiview.open(item: item, detail: detail, startAt: start)
    }

    /// "Watch the main feed" on the multiview's "Not available for this race": closes the
    /// multiview and plays the session's main feed in the single-feed player, from where the
    /// multiview was asked to start. The multiview's stop() lands first, or it would end the PLAY.
    func watchMainFeed() async {
        guard let fallback = multiview.mainFeedFallback else { return }
        multiview.close()
        await multiview.waitForStop()
        await playback.start(item: fallback.item, channel: fallback.channel, startAt: fallback.start)
    }

    /// The resume banner. A bookmark saved in multiview opens multiview again (one fresh PLAY,
    /// the last-used feeds, at the saved place; live at the live edge) when the account has it;
    /// anything else resumes the single-feed player, as in beta.1.
    func resume(_ bookmark: WatchBookmark) async {
        if bookmark.multiview, case .signedIn(let account) = auth, account.hasMultiview {
            if playback.isPresented || playback.isInPictureInPicture { playback.close() }
            // The single-feed player's stop() must land before the multiview's PLAY.
            await playback.waitForStop()
            await multiview.resume(bookmark, catalogue: catalogue)
        } else {
            await playback.resume(bookmark)
        }
    }

    /// Launch: load the anonymous catalogue config, then sign in with the saved token.
    func restore() async {
        let saved = Keychain.loadToken()
        // With a saved token the sign-in screen must not show (or accept taps) while we prepare.
        if saved != nil { auth = .signingIn }
        // Browsing before sign-in needs the anonymous location; a failure here is retried by callers.
        try? await session.prepare()
        guard let token = saved else {
            restorePending = false
            auth = .signedOut
            message = Self.signInPrompt
            return
        }
        do {
            let account = try await session.signIn(token: token)
            restorePending = false
            auth = .signedIn(account)
            message = nil
        } catch is CancellationError {
            if Task.isCancelled { auth = .signedOut }
            return
        } catch F1TVError.refused {
            await expire(message: Self.expiredMessage)
        } catch {
            // The saved token stays: this may be only a bad connection. Foreground and
            // "Try again" retry it.
            restorePending = true
            auth = .signedOut
            message = Self.failureMessage(error)
        }
    }

    /// Retries a launch that failed for network or server reasons. Does nothing otherwise, and
    /// never retries a refused token (that token is already deleted).
    func retryRestore() async {
        guard restorePending, auth == .signedOut else { return }
        await restore()
    }

    func dismissMessage() { message = nil }

    func signIn(token: String) async {
        auth = .signingIn
        message = nil
        do {
            let account = try await session.signIn(token: token)
            Keychain.saveToken(token)
            auth = .signedIn(account)
        } catch is CancellationError {
            if Task.isCancelled { auth = .signedOut }
            return
        } catch F1TVError.refused {
            // A refused fresh paste leaves any saved token and the pending restore alone.
            await session.signOut()
            auth = .signedOut
            message = "F1 TV didn't accept that sign-in. Try again."
        } catch {
            auth = .signedOut
            message = Self.failureMessage(error)
        }
    }

    func signOut() {
        Keychain.deleteToken()
        restorePending = false
        auth = .signedOut
        message = Self.signInPrompt
        // Closing also stops the play session and keeps the bookmark.
        playback.close()
        multiview.close()
        let session = session
        let player = player
        Task {
            await player.stop()
            await session.signOut()
        }
    }

    /// Foreground re-check of the saved sign-in.
    func revalidate() async {
        if case .signedOut = auth, restorePending {
            await retryRestore()
            return
        }
        guard case .signedIn = auth, let token = Keychain.loadToken() else { return }
        do {
            let account = try await session.signIn(token: token)
            // A sign-out the user made while we waited stands.
            guard case .signedIn = auth else { return }
            auth = .signedIn(account)
        } catch is CancellationError {
            return
        } catch F1TVError.refused {
            guard case .signedIn = auth else { return }
            await expire(message: Self.expiredMessage)
        } catch {
            // A bad connection doesn't end a sign-in that may still be good.
        }
    }

    /// The one path for a refused sign-in (restore, sign-in, foreground check): the same as
    /// signing out, plus the reason. The bookmark and recents stay; the token, playback and the
    /// play session go.
    private func expire(message newMessage: String) async {
        Keychain.deleteToken()
        restorePending = false
        // Saves the bookmark first, then closes the players and stops the play session.
        playback.close()
        multiview.close()
        await player.stop()
        await session.signOut()
        auth = .signedOut
        message = newMessage
    }

    private static func failureMessage(_ error: Error) -> String {
        if case F1TVError.network(let reason) = error {
            return "Couldn't load F1 TV: \(reason)"
        }
        return "Couldn't load F1 TV."
    }
}

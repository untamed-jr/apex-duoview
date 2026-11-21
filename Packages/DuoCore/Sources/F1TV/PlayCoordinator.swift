import Foundation

/// Asks F1 TV to play a feed, one play session at a time. A second PLAY request can end the
/// first session, so asking again for what is already playing (or loading) never sends one.
public actor PlayCoordinator {
    private struct Key: Equatable {
        var contentId: Int
        var channelId: Int?
        var multiview = false
    }

    /// What one PLAY request produced; single and multiview share the one-session logic.
    private enum Played: Sendable {
        case single(PlayInfo)
        case multi(MultiPlayInfo)
    }

    private struct Pending {
        var key: Key
        var generation: Int
        var task: Task<Played, Error>
    }

    /// One feed's PLAY of a live multiview, in flight. `id` tells a newer request for the same
    /// feed from this one.
    private struct LiveRequest {
        var id: Int
        var task: Task<PlayInfo, Error>
    }

    private let session: F1TVSession
    private var playing: (key: Key, info: Played)?
    private var pending: Pending?
    /// Bumped by every new request and by `stop()`, so a result that arrives after either is dropped.
    private var generation = 0
    /// Live multiview: each feed's own PLAY (several play side by side), by channel id, for
    /// `liveContentId`. Cleared by `play`, `playMultiview` and `stop()`.
    private var liveContentId: Int?
    private var liveFeeds: [Int: PlayInfo] = [:]
    private var livePending: [Int: LiveRequest] = [:]
    private var liveRequestCount = 0
    /// Bumped whenever the live feeds are cleared, so an answer that arrives after is dropped.
    private var liveGeneration = 0

    public init(session: F1TVSession) {
        self.session = session
    }

    public var active: (contentId: Int, channelId: Int?)? {
        playing.map { ($0.key.contentId, $0.key.channelId) }
    }

    public func play(contentId: Int, channelId: Int?) async throws -> PlayInfo {
        let key = Key(contentId: contentId, channelId: channelId)
        guard case .single(let info) = try await start(key: key, refresh: false) else {
            throw F1TVError.badResponse("Unexpected PLAY result")
        }
        return info
    }

    /// One PLAY request for every feed of a race. Same one-session rules as `play`; `refresh`
    /// always sends a new request, for when the feed URLs have gone stale.
    public func playMultiview(
        contentId: Int, defaultChannelId: Int?, refresh: Bool = false
    ) async throws -> MultiPlayInfo {
        let key = Key(contentId: contentId, channelId: defaultChannelId, multiview: true)
        guard case .multi(let info) = try await start(key: key, refresh: refresh) else {
            throw F1TVError.badResponse("Unexpected PLAY result")
        }
        return info
    }

    /// One feed of a live multiview, asked on its own and Safari-style (as `play` asks): asked as
    /// one multiview PLAY, F1 TV sends live as Widevine, which no iPhone plays; asked per feed it
    /// sends FairPlay, and several such feeds play side by side. Each feed's answer is kept by
    /// `channelId` until `play`, `playMultiview` or `stop()`: asking again returns it without a
    /// request, and asking for another feed never ends this one. `refresh` asks F1 TV again (the
    /// links went stale); a request already in flight for the feed is waited for instead.
    /// `playChannelId` is the channelId PLAY takes: nil for a feed F1 TV links without one.
    /// A DRM stream other than FairPlay throws `.protectedContent` and is not kept.
    public func playLiveFeed(
        contentId: Int, channelId: Int, playChannelId: Int?, refresh: Bool = false
    ) async throws -> PlayInfo {
        // Another session's feeds go; the live feeds replace a single or multiview session.
        if liveContentId != contentId {
            clearLiveFeeds()
            liveContentId = contentId
        }
        if playing != nil || pending != nil {
            pending?.task.cancel()
            pending = nil
            playing = nil
            generation += 1
        }
        if !refresh, let info = liveFeeds[channelId] { return info }
        let mine = liveGeneration
        // This feed is already being asked for: wait for that one request.
        if let request = livePending[channelId] {
            let info: PlayInfo
            do {
                info = try await request.task.value
            } catch {
                if liveGeneration != mine { throw CancellationError() }
                throw error
            }
            guard liveGeneration == mine else { throw CancellationError() }
            return info
        }

        liveFeeds[channelId] = nil
        liveRequestCount += 1
        let id = liveRequestCount
        let session = self.session
        let key = Key(contentId: contentId, channelId: playChannelId)
        let task = Task { () throws -> PlayInfo in
            guard case .single(let info) = try await Self.request(session: session, key: key) else {
                throw F1TVError.badResponse("Unexpected PLAY result")
            }
            return info
        }
        livePending[channelId] = LiveRequest(id: id, task: task)
        do {
            let info = try await task.value
            // Cleared meanwhile (stop, another play): a cancellation, never kept.
            guard liveGeneration == mine else { throw CancellationError() }
            if livePending[channelId]?.id == id { livePending[channelId] = nil }
            liveFeeds[channelId] = info
            return info
        } catch {
            guard liveGeneration == mine else { throw CancellationError() }
            if livePending[channelId]?.id == id { livePending[channelId] = nil }
            throw error
        }
    }

    private func clearLiveFeeds() {
        for request in livePending.values { request.task.cancel() }
        livePending = [:]
        liveFeeds = [:]
        liveContentId = nil
        liveGeneration += 1
    }

    private func start(key: Key, refresh: Bool) async throws -> Played {
        // A single or multiview session replaces the live feeds, as it replaces any other session.
        clearLiveFeeds()
        if !refresh, let playing, playing.key == key { return playing.info }
        // The same item is already being requested: wait for that one request.
        if let pending, pending.key == key {
            let info: Played
            do {
                info = try await pending.task.value
            } catch {
                // Superseded or stopped meanwhile: the failure is a cancellation, not a network error.
                if generation != pending.generation { throw CancellationError() }
                throw error
            }
            if let playing, playing.key == key, generation == pending.generation { return playing.info }
            guard generation == pending.generation else { throw CancellationError() }
            return info
        }

        // A different item replaces whatever was playing or loading.
        pending?.task.cancel()
        playing = nil
        generation += 1
        let mine = generation
        let session = self.session
        let task = Task { try await Self.request(session: session, key: key) }
        pending = Pending(key: key, generation: mine, task: task)
        do {
            let info = try await task.value
            guard generation == mine else { throw CancellationError() }
            playing = (key, info)
            pending = nil
            return info
        } catch {
            // Superseded by a newer play or by stop(): a cancelled request surfaces from the session
            // as a network error, but the caller must see a cancellation.
            guard generation == mine else { throw CancellationError() }
            pending = nil
            throw error
        }
    }

    public func stop() {
        pending?.task.cancel()
        pending = nil
        playing = nil
        generation += 1
        clearLiveFeeds()
    }

    private static func request(session: F1TVSession, key: Key) async throws -> Played {
        var query = [("contentId", "\(key.contentId)"), ("player", key.multiview ? "player_tm" : "player_bm")]
        if let channelId = key.channelId { query.append(("channelId", "\(channelId)")) }
        let json = try await session.getJSON(
            path: "CONTENT/PLAY", version: .play, platform: key.multiview ? .webDASH : .webHLS,
            query: query, authorized: true, multiview: key.multiview)
        // A DRM stream other than FairPlay can't play in this app; it never becomes the active one.
        // FairPlay (live, asked Safari-style) plays with a key from F1 TV's licence service.
        if key.multiview { return .multi(try Parsers.multiPlay(json)) }
        let info = try Parsers.play(json)
        if info.licenseURL != nil, !info.isFairPlay { throw F1TVError.protectedContent }
        return .single(info)
    }
}

import Foundation
import Testing
@testable import F1TV

private let stream = "https://example.invalid/x/index.m3u8"

private func playBody(license: Bool = false) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/play-1000010431-WEB_HLS.json")
    var text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
    text = text.replacingOccurrences(of: #""url": "<removed>""#, with: #""url": "\#(stream)""#)
    if license {
        text = text.replacingOccurrences(
            of: #""streamType""#, with: #""laURL": "https://example.invalid/license", "streamType""#)
    }
    return Data(text.utf8)
}

private let playSuffix = "/3.0/R/ENG/WEB_HLS/ALL/CONTENT/PLAY"

@Suite struct PlayCoordinatorTests {
    /// Config without versions, so PLAY uses the default 3.0.
    static func fake() async -> FakeHTTPClient {
        let f = await SessionTests.fake()
        await f.respond(pathSuffix: "/config", json: #"{"apiConfig":{}}"#)
        return f
    }

    static func signedIn(_ f: FakeHTTPClient) async throws -> F1TVSession {
        let s = F1TVSession(http: f)
        try await s.prepare()
        _ = try await s.signIn(token: "TOK")
        return s
    }

    static func plays(_ f: FakeHTTPClient) async -> [HTTPRequest] {
        await f.requests.filter { $0.url.path.hasSuffix("/CONTENT/PLAY") }
    }

    @Test func requestShapeAndHeaders() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        let info = try await p.play(contentId: 1000010431, channelId: 1016)
        #expect(info.url.absoluteString == stream)
        let r = try #require(await Self.plays(f).first)
        #expect(r.url.path == "/3.0/R/ENG/WEB_HLS/ALL/CONTENT/PLAY")
        #expect(r.url.query == "contentId=1000010431&player=player_bm&channelId=1016")
        #expect(r.headers["ascendontoken"] == "TOK")
        #expect(r.headers["entitlementtoken"] == "ENT")
        #expect(r.headers["x-f1-device-info"] == Endpoints.deviceInfo(multiview: false))
    }

    @Test func noChannelOmitsChannelId() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.play(contentId: 1000010431, channelId: nil)
        #expect(await Self.plays(f).first?.url.query == "contentId=1000010431&player=player_bm")
    }

    @Test func playingTwiceSendsOneRequestThenStopClears() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        let a = try await p.play(contentId: 1000010431, channelId: nil)
        let b = try await p.play(contentId: 1000010431, channelId: nil)
        #expect(a == b)
        #expect(await Self.plays(f).count == 1)
        #expect(await p.active?.contentId == 1000010431)
        #expect(await p.active?.channelId == nil)
        await p.stop()
        #expect(await p.active == nil)
        _ = try await p.play(contentId: 1000010431, channelId: nil)
        #expect(await Self.plays(f).count == 2)
    }

    @Test func otherChannelReplacesWithOneNewRequest() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.play(contentId: 1000010431, channelId: nil)
        _ = try await p.play(contentId: 1000010431, channelId: 1016)
        let plays = await Self.plays(f)
        #expect(plays.count == 2)
        #expect(plays[1].url.query == "contentId=1000010431&player=player_bm&channelId=1016")
        #expect(await p.active?.channelId == 1016)
    }

    @Test func protectedContentThrowsAndIsNotActive() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody(license: true))
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        await #expect(throws: F1TVError.protectedContent) {
            try await p.play(contentId: 1000010431, channelId: nil)
        }
        #expect(await p.active == nil)
    }

    @Test func refusedThrows403() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, status: 403, json: "{}")
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        await #expect(throws: F1TVError.refused(status: 403)) {
            try await p.play(contentId: 1000010431, channelId: nil)
        }
        #expect(await p.active == nil)
    }

    @Test func signedOutThrowsNotSignedIn() async throws {
        let f = await Self.fake()
        let s = F1TVSession(http: f)
        try await s.prepare()
        let p = PlayCoordinator(session: s)
        await #expect(throws: F1TVError.notSignedIn) {
            try await p.play(contentId: 1000010431, channelId: nil)
        }
        #expect(await Self.plays(f).isEmpty)
    }

    @Test func overlappingPlaysForSameItemSendOneRequest() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody())
        let gate = GatedHTTPClient(f, gatedSuffix: "/CONTENT/PLAY")
        let s = F1TVSession(http: gate)
        try await s.prepare()
        _ = try await s.signIn(token: "TOK")
        let p = PlayCoordinator(session: s)
        async let first = p.play(contentId: 1000010431, channelId: nil)
        await gate.waitUntilHeld()
        async let second = p.play(contentId: 1000010431, channelId: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        await gate.release()
        let (a, b) = try await (first, second)
        #expect(a == b)
        #expect(await Self.plays(f).count == 1)
        #expect(await p.active?.contentId == 1000010431)
    }

    @Test func stopDuringRequestDropsTheResult() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, body: try playBody())
        let gate = GatedHTTPClient(f, gatedSuffix: "/CONTENT/PLAY")
        let s = F1TVSession(http: gate)
        try await s.prepare()
        _ = try await s.signIn(token: "TOK")
        let p = PlayCoordinator(session: s)
        let t = Task { try await p.play(contentId: 1000010431, channelId: nil) }
        await gate.waitUntilHeld()
        await p.stop()
        await gate.release()
        _ = await t.result
        #expect(await p.active == nil)
    }

    @Test func supersededCallerGetsCancellationNotNetworkError() async throws {
        let f = await Self.fake()
        await f.fail(pathSuffix: playSuffix, with: URLError(.cancelled))
        let gate = GatedHTTPClient(f, gatedSuffix: "/CONTENT/PLAY")
        let s = F1TVSession(http: gate)
        try await s.prepare()
        _ = try await s.signIn(token: "TOK")
        let p = PlayCoordinator(session: s)
        let t = Task { try await p.play(contentId: 1000010431, channelId: nil) }
        await gate.waitUntilHeld()
        await p.stop()
        await gate.release()
        let result = await t.result
        #expect({ if case .failure(let e) = result, e is CancellationError { return true } else { return false } }())
        #expect(await p.active == nil)
    }

    @Test func genuineFailureStaysNetworkError() async throws {
        let f = await Self.fake()
        await f.fail(pathSuffix: playSuffix, with: URLError(.notConnectedToInternet))
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        let result = await Task { try await p.play(contentId: 1000010431, channelId: nil) }.result
        #expect({ if case .failure(let e) = result, case F1TVError.network = e { return true } else { return false } }())
    }

    // MARK: Live multiview: each feed on its own PLAY

    private static func liveReply(_ drm: String = "fairplay") -> String {
        #"{"resultCode":"OK","resultObj":{"url":"https://example.invalid/live.m3u8","streamType":"X","drmType":"\#(drm)","laURL":"https://example.invalid/LA/\#(drm)"}}"#
    }

    private static func gatedSession(_ f: FakeHTTPClient) async throws -> (F1TVSession, GatedHTTPClient) {
        let gate = GatedHTTPClient(f, gatedSuffix: "/CONTENT/PLAY")
        let s = F1TVSession(http: gate)
        try await s.prepare()
        _ = try await s.signIn(token: "TOK")
        return (s, gate)
    }

    @Test func liveFeedAsksSafariStyleWithItsChannel() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        let info = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(info.isFairPlay)
        let r = try #require(await Self.plays(f).first)
        #expect(r.url.path == "/3.0/R/ENG/WEB_HLS/ALL/CONTENT/PLAY")
        #expect(r.url.query == "contentId=1000010431&player=player_bm&channelId=1033")
        #expect(r.headers["x-f1-device-info"] == Endpoints.deviceInfo(multiview: false))
        #expect(r.headers["User-Agent"] == Endpoints.userAgent)
    }

    @Test func liveFeedWithoutChannelIdForInternational() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1025, playChannelId: nil)
        #expect(await Self.plays(f).first?.url.query == "contentId=1000010431&player=player_bm")
    }

    @Test func liveFeedsCoexist() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        let first = try await p.playLiveFeed(contentId: 1000010431, channelId: 1025, playChannelId: nil)
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1006, playChannelId: 1006)
        // The second feed's PLAY kept the first: asking for it again sends nothing.
        let again = try await p.playLiveFeed(contentId: 1000010431, channelId: 1025, playChannelId: nil)
        #expect(again == first)
        let plays = await Self.plays(f)
        #expect(plays.count == 2)
        #expect(plays[1].url.query == "contentId=1000010431&player=player_bm&channelId=1006")
    }

    @Test func liveFeedAgainSendsNoRequest() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        let a = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        let b = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(a == b)
        #expect(await Self.plays(f).count == 1)
    }

    @Test func refreshSendsOne() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1006, playChannelId: 1006)
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033, refresh: true)
        let plays = await Self.plays(f)
        #expect(plays.count == 3)
        #expect(plays[2].url.query == "contentId=1000010431&player=player_bm&channelId=1033")
        // The other feed is still kept.
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1006, playChannelId: 1006)
        #expect(await Self.plays(f).count == 3)
    }

    @Test func widevineLiveFeedRejected() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply("widevine"))
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        await #expect(throws: F1TVError.protectedContent) {
            try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        }
        // Not kept: asking again asks F1 TV again.
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(await Self.plays(f).count == 2)
    }

    @Test func singlePlayClearsLiveFeeds() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        _ = try await p.play(contentId: 1000010431, channelId: 1033)
        #expect(await Self.plays(f).count == 2)
        // The single play replaced the live feeds: this one is asked again.
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(await Self.plays(f).count == 3)
    }

    @Test func stopClearsLiveFeeds() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        await p.stop()
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(await Self.plays(f).count == 2)
    }

    @Test func multiviewPlayClearsLiveFeeds() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        await f.respond(pathSuffix: "/3.0/R/ENG/WEB_DASH/ALL/CONTENT/PLAY", status: 404, json: "{}")
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        _ = try? await p.playMultiview(contentId: 1000010431, defaultChannelId: 1033)
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(await Self.plays(f).count == 3)
    }

    @Test func otherSessionGetsItsOwnLiveFeeds() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let p = PlayCoordinator(session: try await Self.signedIn(f))
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        _ = try await p.playLiveFeed(contentId: 1000010432, channelId: 1033, playChannelId: 1033)
        let plays = await Self.plays(f)
        #expect(plays.count == 2)
        #expect(plays[1].url.query == "contentId=1000010432&player=player_bm&channelId=1033")
    }

    @Test func overlappingLiveFeedRequestsSendOne() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let (s, gate) = try await Self.gatedSession(f)
        let p = PlayCoordinator(session: s)
        async let first = p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        await gate.waitUntilHeld()
        // Asked again (even to refresh) while in flight: it waits for that one request.
        async let second = p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033, refresh: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        await gate.release()
        let (a, b) = try await (first, second)
        #expect(a == b)
        #expect(await Self.plays(f).count == 1)
    }

    @Test func stopDuringLiveFeedRequestCancelsIt() async throws {
        let f = await Self.fake()
        await f.respond(pathSuffix: playSuffix, json: Self.liveReply())
        let (s, gate) = try await Self.gatedSession(f)
        let p = PlayCoordinator(session: s)
        let t = Task { try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033) }
        await gate.waitUntilHeld()
        await p.stop()
        await gate.release()
        let result = await t.result
        #expect({ if case .failure(let e) = result, e is CancellationError { return true } else { return false } }())
        // Dropped: asking again sends a new request.
        _ = try await p.playLiveFeed(contentId: 1000010431, channelId: 1033, playChannelId: 1033)
        #expect(await Self.plays(f).count == 2)
    }
}

import Foundation
import Testing
@testable import F1TV

private func fixture(_ name: String) throws -> JSONValue {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
    return try JSONValue.parse(try Data(contentsOf: url))
}

/// F1 TV's own play link for a feed (`playbackUrl`) says whether PLAY takes a `channelId`. The
/// main INTERNATIONAL feed (1025) has none, and asking for channel 1025 gets a 404 (Abu Dhabi
/// 2021 on the Duo, 2026-11-18).
@Suite struct PlayChannelTests {
    @Test func abuDhabi2021MainFeedPlaysWithoutChannel() throws {
        let detail = try Parsers.video(try fixture("video-1000004712-WEB_HLS.json"))
        #expect(detail.contentId == 1000004712)
        let found = detail.channels.first { $0.isDefault }
        let main = try #require(found)
        #expect(main.id == 1025)
        #expect(main.title == "INTERNATIONAL")
        #expect(main.playChannelId == nil)
        let hamilton = detail.channels.first { $0.racingNumber == 44 }
        let ham = try #require(hamilton)
        #expect(ham.playChannelId == 1006)
        #expect(detail.channels.count == 23)
    }

    @Test func saoPaulo2026KeepsItsChannels() throws {
        let detail = try Parsers.video(try fixture("video-1000010431-WEB_HLS.json"))
        let found = detail.channels.first { $0.isDefault }
        let live = try #require(found)
        #expect(live.id == 1033)
        #expect(live.playChannelId == 1033)
        // INTERNATIONAL here also plays without a channel.
        #expect(detail.channels.first(where: { $0.id == 1025 })?.playChannelId == nil)
    }

    @Test func channelWithoutLinkPlaysWithItsOwnId() {
        #expect(Channel(id: 1016).playChannelId == 1016)
        #expect(Channel(id: nil).playChannelId == nil)
    }

    @Test func linkWithChannelOrNoLinkUsesTheId() throws {
        let text = #"{"resultObj":{"containers":[{"metadata":{"contentId":5,"title":"T","additionalStreams":[{"channelId":1003,"type":"additional","playbackUrl":"CONTENT/PLAY?channelId=1003&contentId=5"},{"channelId":1009,"type":"obc","racingNumber":33}]}}]}}"#
        let detail = try Parsers.video(try JSONValue.parse(Data(text.utf8)))
        #expect(detail.channels.map(\.playChannelId) == [1003, 1009])
    }
}

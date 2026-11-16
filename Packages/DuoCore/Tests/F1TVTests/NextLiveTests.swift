import Testing
@testable import F1TV

/// Android's NextLiveTest, ported: a São Paulo race weekend's live programmes.
struct NextLiveTests {
    let preRace = CatalogItem(contentId: 1, title: "Pre-Race Show", subtype: "LIVE", meeting: "São Paulo Grand Prix")
    let race = CatalogItem(contentId: 2, title: "Race", subtype: "LIVE", meeting: "São Paulo Grand Prix")
    let postRace = CatalogItem(contentId: 3, title: "Post-Race Show", subtype: "LIVE", meeting: "São Paulo Grand Prix")

    @Test func nextLivePicksNewSinceOpening() {
        // The race goes live during the pre-race show.
        #expect(NextLive.pick(live: [preRace, race], onScreen: 1, liveAtStart: [1], declined: [], watchedEnded: false) == race)
        // The post-race show follows the race.
        #expect(NextLive.pick(live: [race, postRace], onScreen: 2, liveAtStart: [2], declined: [], watchedEnded: false) == postRace)
        // Something already live when the programme was opened waits until it ends.
        #expect(NextLive.pick(live: [preRace, race], onScreen: 1, liveAtStart: [1, 2], declined: [], watchedEnded: false) == nil)
        // Nothing but what's on screen.
        #expect(NextLive.pick(live: [preRace], onScreen: 1, liveAtStart: [], declined: [], watchedEnded: false) == nil)
    }

    @Test func nextLiveSkipsDeclined() {
        #expect(NextLive.pick(live: [race, postRace], onScreen: 2, liveAtStart: [2], declined: [3], watchedEnded: false) == nil)
        #expect(NextLive.pick(live: [race, postRace], onScreen: 2, liveAtStart: [2], declined: [3], watchedEnded: true) == nil)
        // The first one not turned down.
        let other = CatalogItem(contentId: 4, title: "F1 Live", subtype: "LIVE")
        #expect(NextLive.pick(live: [postRace, other], onScreen: 2, liveAtStart: [2], declined: [3], watchedEnded: false) == other)
    }

    @Test func nextLiveAnyOnceEnded() {
        // Already live at opening, offered once the pre-race show has gone off air.
        #expect(NextLive.pick(live: [race], onScreen: 1, liveAtStart: [1, 2], declined: [], watchedEnded: true) == race)
        // Never what's on screen, ended or not.
        #expect(NextLive.pick(live: [preRace], onScreen: 1, liveAtStart: [1], declined: [], watchedEnded: true) == nil)
        // In F1 TV's order.
        #expect(NextLive.pick(live: [postRace, race], onScreen: 1, liveAtStart: [1, 2, 3], declined: [], watchedEnded: true) == postRace)
    }

    @Test func nextLiveNeverOffersAnItemWithoutAnId() {
        let blank = CatalogItem(contentId: 0, title: "Unknown", subtype: "LIVE")
        #expect(NextLive.pick(live: [blank, race], onScreen: 1, liveAtStart: [1], declined: [], watchedEnded: true) == race)
    }
}

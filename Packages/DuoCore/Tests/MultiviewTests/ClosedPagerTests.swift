import Foundation
import Testing
import F1TV
import LiveTiming
@testable import Multiview

@Suite struct ClosedPagerTests {
    /// A session whose TimingData puts the given cars at the given positions (nil: no position yet).
    /// Cars in `onlyListed` are named in DriverList but have no timing.
    static func session(positions: [String: Int?], onlyListed: [String] = []) -> LoadedSession {
        let start: UTCms = 1_000_000
        var lines: [String: JSONValue] = [:]
        for (number, position) in positions {
            lines[number] = position.map { .object(["Position": .string(String($0))]) } ?? .object(["NumberOfLaps": .number(1)])
        }
        let timing = TimingTimeline.build(
            lines: [StreamLine(offsetMs: 0, json: .object(["Lines": .object(lines)]))], streamStart: start)
        var drivers: [String: DriverInfo] = [:]
        for number in Array(positions.keys) + onlyListed {
            drivers[number] = DriverInfo(number: number, tla: "D" + number, firstName: "", lastName: "",
                                         teamName: "", teamColour: "")
        }
        let info = TimingSessionInfo(key: 1, name: "Race", type: "Race", path: "", start: start,
                                     gmtOffsetSeconds: 0, circuitKey: nil, meetingName: "", year: 2026)
        return LoadedSession(
            info: info, drivers: drivers, streamStart: start, positions: PositionSeries(cars: [:]), timing: timing,
            stints: StintTimeline.build(lines: [], streamStart: start),
            header: HeaderTimeline.build(lapCount: [], clock: [], weather: [], streamStart: start),
            flags: TrackFlags.build(trackStatus: [], raceControl: [], streamStart: start, gmtOffsetSeconds: 0),
            missing: [])
    }

    @Test func pagesUpDownNoWrap() {
        #expect(ClosedPager.page(from: .picture, up: true) == .radio)
        #expect(ClosedPager.page(from: .radio, up: true) == .gap)
        #expect(ClosedPager.page(from: .gap, up: true) == nil)
        #expect(ClosedPager.page(from: .gap, up: false) == .radio)
        #expect(ClosedPager.page(from: .radio, up: false) == .picture)
        #expect(ClosedPager.page(from: .picture, up: false) == nil)
        #expect(ClosedPage.allCases == [.picture, .radio, .gap])
    }

    @Test func orderIsRacePositionNotRadio() {
        // Positions 1..3, a car with no position, a car with no timing at all, and a tie on 2.
        let s = Self.session(positions: ["44": 2, "1": 1, "63": 2, "16": nil, "4": 3], onlyListed: ["10", "9"])
        let at: UTCms = 1_000_100
        #expect(ClosedPager.raceOrder(at: at, session: s) == ["1", "44", "63", "4", "9", "10", "16"])
        // Before any timing: nobody has a position, so it is by number.
        #expect(ClosedPager.raceOrder(at: 999_999, session: s) == ["1", "4", "9", "10", "16", "44", "63"])
    }

    @Test func driverSwipeWraps() {
        let order = ["1", "44", "63"]
        #expect(ClosedPager.driver(after: "1", forward: true, order: order) == "44")
        #expect(ClosedPager.driver(after: "63", forward: true, order: order) == "1")
        #expect(ClosedPager.driver(after: "1", forward: false, order: order) == "63")
        #expect(ClosedPager.driver(after: "44", forward: false, order: order) == "1")
        // Nobody chosen, or a driver no longer listed: forward starts at the first, back at the last.
        #expect(ClosedPager.driver(after: nil, forward: true, order: order) == "1")
        #expect(ClosedPager.driver(after: nil, forward: false, order: order) == "63")
        #expect(ClosedPager.driver(after: "99", forward: true, order: order) == "1")
        #expect(ClosedPager.driver(after: "1", forward: true, order: []) == nil)
    }

    @Test func defaultDriverIsLeaderWithoutFavourite() {
        let order = ["1", "44", "63"]
        #expect(ClosedPager.defaultDriver(favourite: nil, order: order) == "1")
        #expect(ClosedPager.defaultDriver(favourite: "63", order: order) == "63")
        // A favourite not in the race falls back to the leader.
        #expect(ClosedPager.defaultDriver(favourite: "99", order: order) == "1")
        #expect(ClosedPager.defaultDriver(favourite: "63", order: []) == nil)
    }
}

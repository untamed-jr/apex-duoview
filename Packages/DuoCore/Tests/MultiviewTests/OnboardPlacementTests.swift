import Testing
import Foundation
import F1TV
import LiveTiming
@testable import Multiview

@Suite struct OnboardPlacementTests {
    static let world = Channel(id: 1025, title: "INTERNATIONAL")
    static let tracker = Channel(id: 1003, title: "TRACKER")
    static let data = Channel(id: 1004, title: "DATA")
    static func onboard(_ number: Int, id: Int? = nil) -> Channel {
        Channel(id: id ?? 2000 + number, isOnboard: true, title: "CAR \(number)", racingNumber: number, driverLastName: "Driver\(number)")
    }
    static let channels: [Channel] = [world, tracker, data] + [1, 4, 16, 44, 63, 81].map { onboard($0) }
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func place(_ number: Int, _ slots: [Channel?], audio: Int? = nil, states: [String: LapState] = [:],
                      placedAt: [Int: Date] = [:], channels: [Channel] = channels) -> Placement {
        OnboardPlacement.place(racingNumber: number, slots: slots, channels: channels, audioChannelId: audio,
                               lapStates: states, placedAt: placedAt)
    }

    @Test func placeMakesMainWhenShowing() {
        #expect(Self.place(44, [Self.world, Self.onboard(1), Self.onboard(44), Self.data]) == .makeMain(slot: 2))
        #expect(Self.place(44, [Self.onboard(44), Self.world]) == .makeMain(slot: 0))
        // Even with an empty spot and the car's feed audible.
        #expect(Self.place(44, [Self.world, nil, Self.onboard(44)], audio: 2044) == .makeMain(slot: 2))
    }

    @Test func placeFillsEmpty() {
        #expect(Self.place(44, [Self.world, Self.onboard(1), nil, nil]) == .fill(slot: 2, channel: Self.onboard(44)))
        #expect(Self.place(44, [nil]) == .fill(slot: 0, channel: Self.onboard(44)))
    }

    @Test func placeReplacesPittingOverFlying() {
        let slots: [Channel?] = [Self.world, Self.onboard(1), Self.onboard(4), Self.onboard(16)]
        // A car in the pits or knocked out goes first, then an out lap or cool-down, then a flying lap.
        let states: [String: LapState] = ["1": .push, "4": .pit, "16": .outLap]
        #expect(Self.place(44, slots, states: states) == .replace(slot: 2, channel: Self.onboard(44)))
        #expect(Self.place(44, slots, states: ["1": .push, "4": .knockedOut, "16": .coolDown]) == .replace(slot: 2, channel: Self.onboard(44)))
        #expect(Self.place(44, slots, states: ["1": .push, "4": .push, "16": .coolDown]) == .replace(slot: 3, channel: Self.onboard(44)))
        // A car with no lap state yet counts as neither pitting nor flying.
        #expect(Self.place(44, slots, states: ["1": .push, "4": .push]) == .replace(slot: 3, channel: Self.onboard(44)))
        #expect(OnboardPlacement.interest(.pit) < OnboardPlacement.interest(.outLap))
        #expect(OnboardPlacement.interest(.knockedOut) == OnboardPlacement.interest(.pit))
        #expect(OnboardPlacement.interest(.coolDown) == OnboardPlacement.interest(.outLap))
        #expect(OnboardPlacement.interest(.unknown) == OnboardPlacement.interest(.outLap))
        #expect(OnboardPlacement.interest(.outLap) < OnboardPlacement.interest(.push))
    }

    @Test func placeNeverReplacesAudible() {
        let slots: [Channel?] = [Self.world, Self.onboard(1), Self.onboard(4)]
        // 4 is in the pits but has the sound: 1, flying, goes instead.
        #expect(Self.place(44, slots, audio: 2004, states: ["1": .push, "4": .pit]) == .replace(slot: 1, channel: Self.onboard(44)))
        #expect(Self.place(44, [Self.world, Self.onboard(4)], audio: 2004, states: ["4": .pit]) == .noFreeSpot)
    }

    @Test func placeNeverReplacesWorldFeed() {
        // Only onboards are replaced: the world feed, tracker and data stay, whatever the states.
        #expect(Self.place(44, [Self.world, Self.tracker, Self.data, Self.onboard(1)], states: ["1": .push]) == .replace(slot: 3, channel: Self.onboard(44)))
        #expect(Self.place(44, [Self.world, Self.tracker, Self.data]) == .noFreeSpot)
        // An onboard without a racing number has no lap state: it goes last.
        let pitLane = Channel(id: 3000, isOnboard: true, title: "PIT LANE")
        #expect(Self.place(44, [Self.world, pitLane, Self.onboard(1)], states: ["1": .push]) == .replace(slot: 2, channel: Self.onboard(44)))
    }

    @Test func placeTieOldestFirst() {
        let slots: [Channel?] = [Self.world, Self.onboard(1), Self.onboard(4), Self.onboard(16)]
        let states: [String: LapState] = ["1": .push, "4": .push, "16": .push]
        // placedAt is by slot index: the one placed longest ago goes.
        let placed = [1: Self.t0.addingTimeInterval(60), 2: Self.t0, 3: Self.t0.addingTimeInterval(30)]
        #expect(Self.place(44, slots, states: states, placedAt: placed) == .replace(slot: 2, channel: Self.onboard(44)))
        // A slot never placed by a tap counts as oldest.
        #expect(Self.place(44, slots, states: states, placedAt: [1: Self.t0, 2: Self.t0]) == .replace(slot: 3, channel: Self.onboard(44)))
        // Equal times: the later slot goes.
        #expect(Self.place(44, [Self.world, Self.onboard(1), Self.onboard(4)], states: ["1": .pit, "4": .pit]) == .replace(slot: 2, channel: Self.onboard(44)))
        // The rank comes before age.
        #expect(Self.place(44, slots, states: ["1": .push, "4": .push, "16": .pit], placedAt: placed) == .replace(slot: 3, channel: Self.onboard(44)))
    }

    @Test func placeNeverReplacesMain() {
        // The main feed (slot 0) stays even when it is the least interesting onboard, as on Android.
        let slots: [Channel?] = [Self.onboard(4), Self.onboard(1), Self.onboard(16)]
        #expect(Self.place(44, slots, states: ["4": .pit, "1": .push, "16": .push],
                           placedAt: [1: Self.t0, 2: Self.t0.addingTimeInterval(10)]) == .replace(slot: 1, channel: Self.onboard(44)))
        #expect(Self.place(44, [Self.onboard(4)], states: ["4": .pit]) == .noFreeSpot)
        #expect(Self.place(44, [Self.onboard(4), Self.world], states: ["4": .knockedOut]) == .noFreeSpot)
        #expect(Self.place(44, [Self.onboard(4), Self.onboard(1)], audio: 2001, states: ["4": .pit]) == .noFreeSpot)
        // Showing in the main slot already is still "make main".
        #expect(Self.place(4, [Self.onboard(4), Self.onboard(1)]) == .makeMain(slot: 0))
    }

    @Test func placeNoOnboardForCar() {
        #expect(Self.place(99, [Self.world, nil]) == .noOnboard(99))
        // A world feed tagged with the number is no onboard; nor is an onboard without an id.
        let tagged = Channel(id: 5000, title: "INTERNATIONAL", racingNumber: 99)
        let noID = Channel(id: nil, isOnboard: true, title: "CAR 99", racingNumber: 99, driverLastName: "X")
        #expect(Self.place(99, [nil], channels: Self.channels + [tagged, noID]) == .noOnboard(99))
        #expect(Placement.noOnboard(99).message == "No onboard for car 99 in this session.")
    }

    @Test func placeNoFreeSpot() {
        #expect(Self.place(44, [Self.world, Self.onboard(1)], audio: 2001) == .noFreeSpot)
        #expect(Self.place(44, []) == .noFreeSpot)
        #expect(Placement.noFreeSpot.message == "No free spot — change a feed in the editor.")
        #expect(Placement.fill(slot: 0, channel: Self.onboard(1)).message == nil)
    }
}

import Foundation
import F1TV
import LiveTiming

/// Where a tapped car's onboard goes in multiview.
public enum Placement: Sendable, Equatable {
    /// The car's onboard already shows in this slot: make it the main feed.
    case makeMain(slot: Int)
    /// Put the onboard in this empty slot.
    case fill(slot: Int, channel: Channel)
    /// Put the onboard in this slot, in place of the onboard there.
    case replace(slot: Int, channel: Channel)
    /// Every slot holds the sound or a feed that isn't an onboard.
    case noFreeSpot
    /// This session has no onboard for that car number.
    case noOnboard(Int)

    /// The message to show, for the cases that change nothing.
    public var message: String? {
        switch self {
        case .noFreeSpot: return "No free spot — change a feed in the editor."
        case .noOnboard(let n): return "No onboard for car \(n) in this session."
        default: return nil
        }
    }
}

/// Tap a car (map, tower, battle chip) to open its onboard, matched by the onboard channel's
/// `racingNumber` against the timing data's car number.
public enum OnboardPlacement {
    /// In order:
    /// 1. no onboard channel (with an id) for the car: `.noOnboard`;
    /// 2. the car's onboard already in a slot: `.makeMain` for that slot;
    /// 3. an empty slot (the first): `.fill`;
    /// 4. otherwise `.replace` the least interesting onboard other than the main feed (slot 0),
    ///    as Android ranks them (`interest`):
    ///    a car in the pits or knocked out first, then an out lap, a cool-down lap or no lap
    ///    state yet, then a flying lap; an onboard without a racing number last. Ties go to the
    ///    onboard placed longest ago (`placedAt`, by channel id, so it follows a feed when slots
    ///    swap; a channel missing from it counts as oldest), then to the later slot. The main feed, the feed with the sound
    ///    (`audioChannelId`) and feeds that aren't onboards (world feed, F1 Live, tracker, data)
    ///    are never replaced, as on Android;
    /// 5. nothing to replace: `.noFreeSpot`.
    ///
    /// `lapStates` are by car number at picture time (`LapStates.at`); push laps only appear in
    /// qualifying, so elsewhere every car on track ranks the same.
    public static func place(racingNumber: Int, slots: [Channel?], channels: [Channel], audioChannelId: Int?,
                             lapStates: [String: LapState], placedAt: [Int: Date]) -> Placement {
        guard let onboard = channels.first(where: { $0.isOnboard && $0.racingNumber == racingNumber && $0.id != nil }) else {
            return .noOnboard(racingNumber)
        }
        if let showing = slots.firstIndex(where: { $0.map { isOnboard($0, of: racingNumber) || $0.id == onboard.id } ?? false }) {
            return .makeMain(slot: showing)
        }
        if let empty = slots.firstIndex(where: { $0 == nil }) {
            return .fill(slot: empty, channel: onboard)
        }
        let candidates = slots.enumerated().compactMap { index, channel -> (slot: Int, rank: Int, placed: Date)? in
            guard index != 0, let channel, channel.isOnboard else { return nil }
            if let audio = audioChannelId, channel.id == audio { return nil }
            let rank = channel.racingNumber.map { interest(lapStates[String($0)] ?? .unknown) } ?? 3
            return (index, rank, channel.id.flatMap { placedAt[$0] } ?? .distantPast)
        }
        let target = candidates.min { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.placed != b.placed { return a.placed < b.placed }
            return a.slot > b.slot
        }
        guard let target else { return .noFreeSpot }
        return .replace(slot: target.slot, channel: onboard)
    }

    /// Lower is less worth keeping on screen: 0 in the pits or knocked out, 1 on an out lap, a
    /// cool-down lap or with no lap state, 2 on a flying lap.
    public static func interest(_ state: LapState) -> Int {
        switch state {
        case .pit, .knockedOut: return 0
        case .push: return 2
        case .unknown, .outLap, .coolDown: return 1
        }
    }

    private static func isOnboard(_ channel: Channel, of number: Int) -> Bool {
        channel.isOnboard && channel.racingNumber == number
    }
}

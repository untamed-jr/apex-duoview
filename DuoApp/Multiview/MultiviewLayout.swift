import CoreGraphics
import F1TV
import Foundation
import LiveTiming
import Multiview

/// What the multiview lays its tiles out by: the layout engine's posture, the fold it can use,
/// and the area the tiles go in. `screen` and `foldFrame` are in the layout area's own space
/// (origin at its top-left corner); `origin` is where that area sits in the full screen (the space
/// of `FoldState.foldFrame`), so the engine's frames are shifted by it to be drawn.
struct MultiviewLayoutInput: Equatable {
    var posture: Multiview.Posture
    /// Only for book and laptop: a fold in the layout area, the right way round for the posture.
    var foldFrame: CGRect?
    var screen: CGSize
    var origin: CGPoint = .zero

    /// A rect from the layout engine, in full-screen coordinates.
    func onScreen(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: origin.x, dy: origin.y)
    }
}

/// The pure parts of the multiview's layout: the posture mapping and the closed layout's swipe.
enum MultiviewLayout {
    /// Narrower than this (the Duo's outer screen, a phone in portrait) is the closed layout,
    /// whatever the hinge says. The same width beta.1 uses to choose the Settings panel.
    static let minimumOpenWidth: CGFloat = 600

    /// The app's posture and fold, as the layout engine takes them, with the whole screen as the
    /// layout area.
    static func input(posture: Posture, foldFrame: CGRect?, screen: CGSize) -> MultiviewLayoutInput {
        input(posture: posture, foldFrame: foldFrame, screen: screen,
              safeRect: CGRect(origin: .zero, size: screen))
    }

    /// The app's posture and fold, as the layout engine takes them, laid out inside `safeRect`
    /// (the safe area, in full-screen coordinates; the spec keeps tiles out of cutouts). Closed
    /// when the whole screen is narrower than 600 pt or the posture is closed; book or laptop with
    /// a fold the right way round in the safe area → that posture and the fold (in the safe
    /// area's space); anything else (flat, unknown, or a half-open phone whose fold doesn't fit)
    /// → flat, no fold. The result is the posture the tiles really use, so a remembered layout
    /// choice is stored under it. An empty safe rect falls back to the whole screen.
    static func input(posture: Posture, foldFrame: CGRect?, screen: CGSize, safeRect: CGRect) -> MultiviewLayoutInput {
        let area = safeRect.width > 0 && safeRect.height > 0 ? safeRect : CGRect(origin: .zero, size: screen)
        func result(_ posture: Multiview.Posture, _ fold: CGRect?) -> MultiviewLayoutInput {
            MultiviewLayoutInput(posture: posture, foldFrame: fold, screen: area.size, origin: area.origin)
        }
        if screen.width < minimumOpenWidth || posture == .closed { return result(.closed, nil) }
        let shifted = foldFrame?.offsetBy(dx: -area.minX, dy: -area.minY)
        switch posture {
        case .book:
            if let fold = usableFold(shifted, screen: area.size, tall: true) { return result(.book, fold) }
        case .laptop:
            if let fold = usableFold(shifted, screen: area.size, tall: false) { return result(.laptop, fold) }
        case .closed, .flat, .unknown:
            break
        }
        return result(.flat, nil)
    }

    /// The fold clipped to the screen; nil when it misses it or lies the wrong way (book needs it
    /// taller than wide, laptop wider than tall). A fold reported as a line with no thickness
    /// (Settings › Debug's simulated fold) is widened to 1 pt first: the layout engine only takes
    /// a fold with an area.
    static func usableFold(_ frame: CGRect?, screen: CGSize, tall: Bool) -> CGRect? {
        guard var fold = frame, screen.width > 0, screen.height > 0 else { return nil }
        if fold.width <= 0, fold.height > 0 {
            fold = CGRect(x: fold.minX - 0.5, y: fold.minY, width: 1, height: fold.height)
        } else if fold.height <= 0, fold.width > 0 {
            fold = CGRect(x: fold.minX, y: fold.minY - 0.5, width: fold.width, height: 1)
        }
        let clipped = fold.intersection(CGRect(origin: .zero, size: screen))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        if tall { return clipped.height > clipped.width ? clipped : nil }
        return clipped.width > clipped.height ? clipped : nil
    }

    /// The slot whose feed a swipe on the closed layout makes the main one, or nil.
    ///
    /// Taking the main spot trades places with slot 0, so "the next slot" would only ever trade
    /// the same two feeds back and forth. Instead the swipe steps through the filled feeds in a
    /// fixed order, the session's feed list (`order`), wrapping, and skips feeds that can't take
    /// the main spot (`playable` lacks them). Forward is a swipe to the left.
    static func swipeSlot(slots: [Int?], order: [Int], forward: Bool, playable: Set<Int>) -> Int? {
        guard let main = slots.first ?? nil else { return nil }
        let filled = slots.compactMap { $0 }
        guard filled.count > 1 else { return nil }
        // Feeds missing from `order` go last, by id: never by slot, which the swipe itself changes.
        func rank(_ id: Int) -> (Int, Int) {
            (order.firstIndex(of: id) ?? order.count, id)
        }
        let cycle = filled.sorted { rank($0) < rank($1) }
        guard let start = cycle.firstIndex(of: main) else { return nil }
        let step = forward ? 1 : cycle.count - 1
        var index = start
        for _ in 1..<cycle.count {
            index = (index + step) % cycle.count
            let id = cycle[index]
            if playable.contains(id) { return slots.firstIndex(of: id) }
        }
        return nil
    }
}

/// Which layout shows: the posture's options with or without the data layouts (`hasTiming`: the
/// session's timing is loaded), the remembered choice when it is one of them, else the default.
/// A remembered data layout stays remembered while timing is missing: the posture's default shows
/// meanwhile, and the data layout comes back with the timing.
enum LayoutChoice {
    /// The layout for this posture and feed count, from the remembered choice (`saved`).
    static func option(saved: String?, posture: Multiview.Posture, feedCount: Int, hasTiming: Bool) -> String {
        let options = LayoutEngine.optionIDs(posture: posture, feedCount: feedCount, hasTiming: hasTiming)
        if let saved, options.contains(saved) { return saved }
        return options[0]
    }

    /// "Switch layout": the option after `current` among `options` (those that fit the screen),
    /// wrapping; from the first when `current` isn't among them (it didn't fit). nil with one
    /// option or none.
    static func next(after current: String, in options: [String]) -> String? {
        guard options.count > 1 else { return nil }
        let shown = options.firstIndex(of: current) ?? 0
        return options[(shown + 1) % options.count]
    }
}

/// Settings › Multiview › "Tracker delay": F1's TRACKER feed runs a little ahead of the world
/// feed, so the sync holds the TRACKER and DATA tiles that much behind the feed they line up
/// with. Matched by title, as the feed picker matches them (`FeedPick`).
enum TrackerDelay {
    /// The stored half-seconds, in seconds.
    static func seconds(halfSeconds: Int) -> Double {
        Double(max(halfSeconds, 0)) * 0.5
    }

    /// The delay as Settings shows it: "0 s", "1.5 s", "2 s".
    static func text(halfSeconds: Int) -> String {
        let value = max(halfSeconds, 0)
        return value % 2 == 0 ? "\(value / 2) s" : "\(value / 2).5 s"
    }

    /// TRACKER or DATA.
    static func applies(to channel: Channel?) -> Bool {
        guard let channel else { return false }
        switch FeedPick(channel) {
        case .tracker, .data: return true
        default: return false
        }
    }

    /// How far behind the main feed this feed should run, in seconds. Never ahead of it: with a
    /// delayed main feed (TRACKER made the main one) the others stay level with it, and a delayed
    /// feed beside a delayed main one runs level with it too. The main feed's own lag is 0.
    static func lag(feedDelayed: Bool, mainDelayed: Bool, delay: Double) -> Double {
        guard delay > 0, feedDelayed, !mainDelayed else { return 0 }
        return delay
    }

    /// What the sync corrects when a feed lines up with a reference feed (the main one, or any
    /// feed in place while the main one isn't): the feed's offset from the reference (positive =
    /// ahead) plus how much more it should lag behind the main feed than the reference does. Zero
    /// when the two sit exactly as their lags say.
    static func syncError(offset: Double?, feedLag: Double, referenceLag: Double) -> Double? {
        offset.map { $0 + feedLag - referenceLag }
    }
}

/// Race Engineer's top onboard: which slot's feed goes on the top screen.
enum RaceEngineerTop {
    /// The first available of: the main feed (slot 0) if it's an onboard; else your driver's
    /// onboard (`favourite`, a last name, matched as the feed picker matches it); else the first
    /// onboard among the feeds. Only feeds already in the slots count, and only those in
    /// `playable` (they have a player that hasn't ended: `canBeMain`) can be brought up from
    /// another slot. Nil when no onboard is available ("Tap a car to pick an onboard"). Choosing a
    /// slot never moves the sound: the caller swaps it into the main spot with `makeMain`.
    static func slot(slots: [Channel?], favourite: String?, playable: Set<Int>) -> Int? {
        if slots.first??.isOnboard == true { return 0 }
        func available(_ index: Int) -> Bool {
            guard let channel = slots[index], channel.isOnboard, let id = channel.id else { return false }
            return playable.contains(id)
        }
        if let favourite, !favourite.isEmpty {
            let pick = FeedPick.onboard(lastName: favourite)
            if let index = slots.indices.first(where: { available($0) && slots[$0].map(pick.matches) == true }) {
                return index
            }
        }
        return slots.indices.first(where: available)
    }
}

extension RaceEngineerTop {
    /// Where a car tapped in Race Engineer goes: tap-a-car's own placement (`OnboardPlacement`),
    /// except that with no free spot the top onboard itself (the main feed) gives way, as long as
    /// it isn't the feed with the sound. With Race Engineer's own swap and the default feeds (an
    /// onboard on top, then the world feed with the sound, the tracker and the data feed) nothing
    /// else can be replaced, and the car ahead or behind must still come up on top.
    static func placement(racingNumber: Int, slots: [Channel?], channels: [Channel], audioChannelId: Int?,
                          lapStates: [String: LapState], placedAt: [Int: Date]) -> Placement {
        let placement = OnboardPlacement.place(
            racingNumber: racingNumber, slots: slots, channels: channels, audioChannelId: audioChannelId,
            lapStates: lapStates, placedAt: placedAt)
        guard placement == .noFreeSpot, let main = slots.first ?? nil, main.isOnboard, let mainId = main.id,
              mainId != audioChannelId,
              let onboard = channels.first(where: { $0.isOnboard && $0.racingNumber == racingNumber && $0.id != nil })
        else { return placement }
        return .replace(slot: 0, channel: onboard)
    }
}

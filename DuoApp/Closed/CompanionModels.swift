import CoreGraphics
import Foundation
import LiveTiming
import Multiview

/// The closed phone's words and decisions, with no views: the cards' copy, the Gap Thermometer's
/// text and colour, the Radio Scanner's header, the jump's target and the card stack. Pure, so the
/// Linux harness checks it.
enum CompanionModels {
    // MARK: Copy (verbatim from the spec)

    static let unfoldToSee = "Unfold to see"
    static let scannerTitle = "Radio Scanner"
    static let newRadio = "New radio \u{2014} tap to play"
    static let pagerHint = "Swipe up or down for Picture, Radio and Gap"
    static let gapTitle = "Gap Thermometer"
    static let gapNotRace = "The Gap Thermometer works in races and sprints."
    static let gapBeforeFirstLap = "Gaps start after the first lap."

    static func noRadio(_ code: String) -> String {
        "No radio from \(code) yet. Swipe for another driver."
    }

    static func inThePits(_ code: String) -> String {
        "\(code) in the pits"
    }

    static func outOfPair(_ code: String) -> String {
        "\(code) is out \u{2014} swipe for another pair"
    }

    /// The chip after a jump: "Rewound to Safety car · Lap 23 — Back to where you were".
    static func backChipText(_ title: String) -> String {
        "Rewound to \(title) \u{2014} Back to where you were"
    }

    /// Older cards behind the top one: "+2"; nil with none.
    static func moreText(_ older: Int) -> String? {
        older > 0 ? "+\(older)" : nil
    }

    /// A car's code: its three letters, else its number.
    static func code(_ number: String, drivers: [String: DriverInfo]) -> String {
        let tla = drivers[number]?.tla ?? ""
        return tla.isEmpty ? number : tla
    }

    /// The spec's card copy. A track or car event carries " · Lap n" when it has a lap (a race
    /// after lights out); a red flag, a car out, a pass and the chequered flag never do.
    static func cardTitle(_ e: CompanionEvent, drivers: [String: DriverInfo]) -> String {
        let lap = e.lap.map { " \u{00B7} Lap \($0)" } ?? ""
        func c(_ number: String) -> String { code(number, drivers: drivers) }
        switch e.kind {
        case .yellow: return "Yellow flag" + lap
        case .safetyCar: return "Safety car" + lap
        case .vsc: return "Virtual safety car" + lap
        case .red: return "Red flag"
        case .chequered: return "Chequered flag"
        case .pit(let car): return "\(c(car)) pits" + lap
        case .radio(let car, _): return "\(c(car)) on the radio" + lap
        case .out(let car): return "\(c(car)) is out"
        case .passed(let car, let other, let position): return "\(c(car)) passes \(c(other)) for P\(position)"
        // No card; named as Settings › Haptics names it.
        case .purpleSector: return "Purple sector"
        }
    }

    // MARK: Gap Thermometer

    /// What the Thermometer shows: the gap in large digits ("1.4", F1's "1L"), a line for a pair
    /// with no gap to read, and ▼ (closing) or ▲ (growing). `.sameCar` shows nothing special.
    static func gapText(_ r: GapReading, drivers: [String: DriverInfo]) -> (big: String, note: String?, arrow: String?) {
        switch r {
        case .gap(let ms, _, _, let trend, _):
            let arrow: String?
            switch trend {
            case .closing?: arrow = "\u{25BC}"
            case .growing?: arrow = "\u{25B2}"
            case .steady?, nil: arrow = nil
            }
            return (seconds(ms), nil, arrow)
        case .lapped(let text, _, _):
            return (text, nil, nil)
        case .inPit(let car):
            return ("", inThePits(code(car, drivers: drivers)), nil)
        case .out(let car):
            return ("", outOfPair(code(car, drivers: drivers)), nil)
        case .beforeFirstLap:
            return ("", gapBeforeFirstLap, nil)
        case .notRace:
            return ("", gapNotRace, nil)
        case .sameCar:
            return ("", nil, nil)
        }
    }

    /// A gap to the nearest tenth: "0.4", "12.0"; from a minute "1:02.3".
    static func seconds(_ ms: Int) -> String {
        let tenths = (max(ms, 0) + 50) / 100
        let whole = tenths / 10, tenth = tenths % 10
        guard whole >= 60 else { return "\(whole).\(tenth)" }
        let s = whole % 60
        return "\(whole / 60):\(s < 10 ? "0" : "")\(s).\(tenth)"
    }

    /// The bar's colour for `heat` (0 cool … 1 red): cool blue at 0 (a gap of 3 s or more), amber
    /// at 0.5 (2 s), red at 1 (1 s or less), linear between. Components 0–1.
    static func heatColour(_ heat: Double) -> (red: Double, green: Double, blue: Double) {
        let blue = (red: 0x3A / 255.0, green: 0x8E / 255.0, blue: 0xFF / 255.0)
        let amber = (red: 0xFF / 255.0, green: 0xB0 / 255.0, blue: 0x20 / 255.0)
        // Theme.flagRed.
        let red = (red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x30 / 255.0)
        let h = heat.isFinite ? min(max(heat, 0), 1) : 0
        func mix(_ a: (red: Double, green: Double, blue: Double), _ b: (red: Double, green: Double, blue: Double),
                 _ f: Double) -> (red: Double, green: Double, blue: Double) {
            (a.red + (b.red - a.red) * f, a.green + (b.green - a.green) * f, a.blue + (b.blue - a.blue) * f)
        }
        return h <= 0.5 ? mix(blue, amber, h / 0.5) : mix(amber, red, (h - 0.5) / 0.5)
    }

    /// Which code goes at the top of the bar (the car ahead) and which at the bottom. A reading
    /// with no gap orders the pair by position at `t`, else keeps it as given.
    static func pairEnds(_ pair: (String, String), reading: GapReading, at t: UTCms,
                         session: LoadedSession) -> (top: String, bottom: String) {
        switch reading {
        case .gap(_, let ahead, let behind, _, _), .lapped(_, let ahead, let behind):
            return (ahead, behind)
        default:
            let states = session.timing.at(t)
            if let a = states[pair.0]?.position, let b = states[pair.1]?.position, b < a { return (pair.1, pair.0) }
            return (pair.0, pair.1)
        }
    }

    // MARK: Radio Scanner

    /// The Scanner's top line: the driver's code, team colour, position ("P4") and lap label
    /// ("Lap 23", "Q2 · 8:12 left"), from timing at `t` (picture time). Position and lap are nil
    /// when timing has none.
    struct ScannerHeader: Equatable, Sendable {
        var code: String
        /// "RRGGBB", or "".
        var teamColour: String
        var position: String?
        var lap: String?
    }

    static func scannerHeader(number: String, at t: UTCms?, session: LoadedSession) -> ScannerHeader {
        let colour = session.drivers[number]?.teamColour ?? ""
        let header = ScannerHeader(code: code(number, drivers: session.drivers), teamColour: colour)
        guard let t else { return header }
        var out = header
        out.position = session.timing.at(t)[number]?.position.map { "P\($0)" }
        out.lap = RadioModels.label(RadioClips.lapLabel(for: RadioClip(utc: t, racingNumber: number, path: ""), in: session))
        return out
    }

    /// The Scanner's driver: the stored one when this session has that car, else your driver, else
    /// `held` (the leader when the page first found one, so a change of lead doesn't move the
    /// page), else the leader (`order` is the race order, `ClosedPager.raceOrder`).
    static func scannerDriver(stored: String?, favourite: String?, held: String? = nil, order: [String]) -> String? {
        if let stored, order.contains(stored) { return stored }
        if let favourite, order.contains(favourite) { return favourite }
        if let held, order.contains(held) { return held }
        return ClosedPager.defaultDriver(favourite: favourite, order: order)
    }

    /// The Thermometer's pair: the stored one when both are this session's cars, else `held` (the
    /// default when the page first found one, so the pair doesn't flip between the cars ahead and
    /// behind as the gaps move), else your driver and the nearer car ahead or behind
    /// (`GapPair.defaultPair`).
    static func gapPair(stored: [String]?, favourite: String?, held: [String]? = nil, at t: UTCms,
                        session: LoadedSession) -> (String, String)? {
        let cars = Set(ClosedPager.raceOrder(at: t, session: session))
        for pair in [stored, held] {
            if let pair, pair.count == 2, pair[0] != pair[1], cars.contains(pair[0]), cars.contains(pair[1]) {
                return (pair[0], pair[1])
            }
        }
        return GapPair.defaultPair(favourite: favourite, at: t, session: session)
    }

    // MARK: Unfold to See

    /// How long "Back to where you were" stays.
    static let backChipSeconds: TimeInterval = 15

    /// The chip's end, from the jump.
    static func backChipUntil(from now: Date) -> Date {
        now.addingTimeInterval(backChipSeconds)
    }

    static func chipShows(until: Date, now: Date) -> Bool {
        now < until
    }

    /// Picture time the jump goes to: `rewindSeconds` (Settings' "Rewind when opening", in
    /// seconds) before the event.
    static func jumpMoment(_ e: CompanionEvent, rewindSeconds: Int) -> UTCms {
        e.t &- Int64(max(rewindSeconds, 0)) &* 1000
    }

    /// The main feed's seconds at picture time `u`, from one reading of the clock (picture time
    /// and the seconds read with it, so the timing offset is in), kept inside the scrubber's span
    /// (`timeline`; at least 0 without one), as the Scrub Deck's marker seek. nil without a usable
    /// reading.
    static func seekSeconds(to u: UTCms, pictureTime: UTCms, playerSeconds: Double,
                            timeline: ClosedRange<Double>?) -> Double? {
        guard playerSeconds.isFinite else { return nil }
        let target = playerSeconds + Double(u &- pictureTime) / 1000
        guard target.isFinite else { return nil }
        guard let timeline else { return max(target, 0) }
        return min(max(target, timeline.lowerBound), timeline.upperBound)
    }

    /// The jump for a card: `t − rewind`, in the main feed's seconds, kept in the timeline.
    static func jumpTarget(_ e: CompanionEvent, rewindSeconds: Int, pictureTime: UTCms, playerSeconds: Double,
                           timeline: ClosedRange<Double>?) -> Double? {
        seekSeconds(to: jumpMoment(e, rewindSeconds: rewindSeconds), pictureTime: pictureTime,
                    playerSeconds: playerSeconds, timeline: timeline)
    }

    // MARK: The pager's swipes

    enum Swipe: Equatable, Sendable {
        case up, down, left, right
    }

    /// A finger's whole movement as a swipe: the longer axis, once it is past `distance`.
    static func swipe(_ translation: CGSize, distance: CGFloat) -> Swipe? {
        let dx = translation.width, dy = translation.height
        if abs(dy) > abs(dx), abs(dy) > distance { return dy < 0 ? .up : .down }
        if abs(dx) > abs(dy), abs(dx) > distance { return dx < 0 ? .left : .right }
        return nil
    }

    /// The page a vertical swipe leads to: a finger moving up goes down the list (Picture → Radio
    /// → Gap), as a page scrolls; nil at either end or for a sideways swipe.
    static func page(after swipe: Swipe, from page: ClosedPage) -> ClosedPage? {
        switch swipe {
        case .up: return ClosedPager.page(from: page, up: true)
        case .down: return ClosedPager.page(from: page, up: false)
        case .left, .right: return nil
        }
    }
}

/// The closed phone's event cards, newest first. Only cards whose group is switched on are kept
/// (`CardGroup`; a purple sector has none), and radio only for your driver.
struct CardStack: Equatable, Sendable {
    /// Older cards beyond this are dropped.
    static let limit = 20

    private(set) var cards: [CompanionEvent] = []
    /// The event the last jump went to: crossing it again in normal play (as the picture plays on
    /// from just before it) brings no second card.
    private(set) var jumpedTo: CompanionEvent?

    var top: CompanionEvent? { cards.first }
    var olderCount: Int { max(cards.count - 1, 0) }

    /// `events` from one detector step (oldest first), crossed in normal play.
    mutating func add(_ events: [CompanionEvent], favourite: String?, groupOn: (CardGroup) -> Bool) {
        for event in events {
            if let jumped = jumpedTo, jumped == event {
                jumpedTo = nil
                continue
            }
            guard let group = CardGroup.of(event.kind), groupOn(group) else { continue }
            if case .radio(let car, _) = event.kind, car != favourite { continue }
            cards.insert(event, at: 0)
        }
        if cards.count > Self.limit { cards.removeLast(cards.count - Self.limit) }
    }

    /// After a seek: the cards for moments the picture hasn't reached any more go. The event
    /// jumped to is kept: the first seek tick may still read the time before the jump landed.
    mutating func dropLater(than t: UTCms) {
        cards.removeAll { $0.t > t }
    }

    /// Normal play is at `t`: once it is 10 s past the event jumped to without crossing it (the
    /// crossing fell in a seek's quiet, or the viewer went on past it), that event is forgotten.
    mutating func played(to t: UTCms) {
        if let jumped = jumpedTo, jumped.t < t &- 10_000 { jumpedTo = nil }
    }

    mutating func dismissTop() {
        if !cards.isEmpty { cards.removeFirst() }
    }

    /// The jump went to `card`: the stack empties.
    mutating func jumped(to card: CompanionEvent) {
        cards = []
        jumpedTo = card
    }

    mutating func removeAll() {
        cards = []
        jumpedTo = nil
    }
}

import Foundation
import LiveTiming
import Multiview

/// The book layouts' words and decisions (pure: no SwiftUI or AVFoundation, so the Linux harness
/// checks it): Onboard and Logbook's logbook, Ear-Matched Rivals' strips and ears, and the hinge
/// mixer's bar. Everything shown is read at the cut (picture time; nil only with "Show the whole
/// race" on), as the radio's rows are.
enum BookModels {
    // MARK: Copy (verbatim from the spec)

    static let radioTitle = "Radio"
    static let lapsTitle = "Laps"
    static let stopsTitle = "Stops"
    static let raceControlTitle = "Race control"
    static let noStops = "No stops yet."
    static let pickOnboard = ConsoleText.pickOnboard
    static let headphonesHint = "Put on headphones to hear each driver in one ear"
    static let mixerSetting = "Hinge mixer"
    static let mixerFooter = "Hinge mixer \u{2014} fold to hear more radio, open for more commentary"
    static let noRadioToMix = "No radio to mix yet"
    /// The surfaces the radio counts as radio views (transcription runs while one shows).
    static let logbookSurface = "book.logbook"
    static let rivalsSurface = "book.rivals"

    static func noRaceControl(_ code: String) -> String { "Nothing from race control about \(code)." }

    static func noRadio(_ code: String) -> String { RadioModels.noRadio(from: code) }

    /// "Left ear · HAM", "Right ear · VER".
    static func earLabel(left: Bool, tla: String) -> String {
        "\(left ? "Left" : "Right") ear \u{00B7} \(tla)"
    }

    /// A Rivals clip's pan: the left screen's driver in the left ear (−1), the right's in the right
    /// (+1), with headphones; centred (0) without, so a speaker plays both whole.
    static func pan(left: Bool, headphones: Bool) -> Float {
        guard headphones else { return 0 }
        return left ? -1 : 1
    }

    // MARK: The logbook

    /// One stop: "Lap 23 · 21.8 s · Medium → Hard". The lap is left out when its count isn't
    /// known; a car still in the lane at the cut says so; a tyre not known yet is "—", and both
    /// unknown leaves the tyres out.
    static func stopLine(_ s: LogbookStop) -> String {
        var parts: [String] = []
        if let lap = s.lap { parts.append("Lap \(lap)") }
        parts.append(s.laneMs.map(laneText) ?? "In the pit lane")
        if s.off != nil || s.on != nil {
            parts.append("\(s.off ?? ConsoleText.absent) \u{2192} \(s.on ?? ConsoleText.absent)")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Pit-lane time in seconds to a tenth: "21.8 s".
    static func laneText(_ ms: Int) -> String {
        let tenths = (max(ms, 0) + 50) / 100
        return "\(tenths / 10).\(tenths % 10) s"
    }

    /// A race control message as F1 wrote it, its spacing tidied (one line, single spaces).
    static func raceControlLine(_ e: RaceControlEntry) -> String {
        e.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A blue flag, by F1's own fields (Category "Flag", Flag "BLUE"), never by the words.
    static func isBlueFlag(_ e: RaceControlEntry) -> Bool {
        e.category?.caseInsensitiveCompare("Flag") == .orderedSame
            && e.flag?.caseInsensitiveCompare("BLUE") == .orderedSame
    }

    /// The race control messages the logbook lists: every one naming the car, except blue flags
    /// (dozens a race, and nothing a viewer acts on).
    static func raceControlShown(_ entries: [RaceControlEntry]) -> [RaceControlEntry] {
        entries.filter { !isBlueFlag($0) }
    }

    /// The logbook's header.
    struct Header: Equatable, Sendable {
        var number: String
        var code: String
        /// "RRGGBB", or "".
        var teamColour: String
        /// "P4", or "—".
        var position: String
        /// "Medium · 18 laps"; nil when F1 has no compound yet.
        var tyre: String?
        /// "1:29.518"; nil before the first timed lap.
        var lastLap: String?
        /// The cars either side, by racing number and code: a tap switches both screens to them.
        var ahead: (number: String, code: String)?
        var behind: (number: String, code: String)?

        static func == (a: Header, b: Header) -> Bool {
            a.number == b.number && a.code == b.code && a.teamColour == b.teamColour && a.position == b.position
                && a.tyre == b.tyre && a.lastLap == b.lastLap
                && a.ahead?.number == b.ahead?.number && a.ahead?.code == b.ahead?.code
                && a.behind?.number == b.behind?.number && a.behind?.code == b.behind?.code
        }
    }

    static func header(_ m: LogbookModel, drivers: [String: DriverInfo]) -> Header {
        func car(_ number: String?) -> (number: String, code: String)? {
            number.map { (number: $0, code: CompanionModels.code($0, drivers: drivers)) }
        }
        return Header(
            number: m.number,
            code: CompanionModels.code(m.number, drivers: drivers),
            teamColour: drivers[m.number]?.teamColour ?? "",
            position: ConsoleText.position(m.position),
            // The compound comes named as Race Engineer names it ("Medium"): shown as given.
            tyre: m.tyre.map { ConsoleText.tyre(compound: $0.compound, laps: $0.laps) },
            lastLap: m.lastLap,
            ahead: car(m.ahead),
            behind: car(m.behind))
    }

    /// One lap in the Laps list: "L41 1:32.456" with its sector colours.
    struct LapRow: Equatable, Sendable, Identifiable {
        var lap: Int
        /// F1's lap time, or "—" (a race's first lap has none).
        var time: String
        var pace: SectorPace
        var sectors: [SectorPace]
        var id: Int { lap }
    }

    /// The laps, newest first.
    static func lapRows(_ laps: [CompletedLap]) -> [LapRow] {
        laps.reversed().map {
            LapRow(lap: $0.lap, time: $0.lapMs.map(Tower.lapText) ?? ConsoleText.absent, pace: $0.pace, sectors: $0.sectors)
        }
    }

    /// One race control line, with its lap label (as the radio's: "Lap 12", "Q2 · 8:12 left").
    struct RaceControlRow: Equatable, Sendable, Identifiable {
        var id: Int
        var label: String?
        var text: String
    }

    /// The car's race control lines, oldest first, blue flags left out.
    static func raceControlRows(_ entries: [RaceControlEntry], car: String, session: LoadedSession) -> [RaceControlRow] {
        raceControlShown(entries).enumerated().map { index, e in
            let label = RadioModels.label(RadioClips.lapLabel(for: RadioClip(utc: e.t, racingNumber: car, path: ""), in: session))
            return RaceControlRow(id: index, label: label, text: raceControlLine(e))
        }
    }

    /// The logbook at the cut: nil with no picture time (and the whole race off), so nothing ahead
    /// of the picture can show; else `Logbook.at` at picture time, or the whole race.
    static func logbook(car: String, pictureTime: UTCms?, wholeRace: Bool, session: LoadedSession) -> LogbookModel? {
        guard wholeRace || pictureTime != nil else { return nil }
        return Logbook.at(RadioModels.cut(pictureTime: pictureTime, wholeRace: wholeRace), car: car, session: session,
                          radio: session.radio, raceControl: session.raceControl)
    }

    /// Whether a logbook built at `cut` (nil: the whole race) may still show now: never one built
    /// for later than the picture (a rewind landed after it was built), nor a whole-race build once
    /// "Show the whole race" is off. Without picture time, only with the whole race on.
    static func logbookShows(cut: UTCms?, pictureTime: UTCms?, wholeRace: Bool) -> Bool {
        if wholeRace { return true }
        guard let cut, let pictureTime else { return false }
        return cut <= pictureTime
    }

    // MARK: Rivals

    /// Rivals' first pair, ahead first: in a race, your driver and the nearer rival
    /// (`GapPair.defaultPair`); elsewhere (no race, or no pair yet) your driver and the car next to
    /// them in the running order (ahead, else behind), or the first two. Nil with fewer than two cars.
    static func defaultRivals(favourite: String?, at t: UTCms, session: LoadedSession) -> (String, String)? {
        if let pair = GapPair.defaultPair(favourite: favourite, at: t, session: session) { return pair }
        let order = ClosedPager.raceOrder(at: t, session: session)
        guard order.count >= 2 else { return nil }
        guard let favourite, let i = order.firstIndex(of: favourite) else { return (order[0], order[1]) }
        return i > 0 ? (order[i - 1], favourite) : (favourite, order[i + 1])
    }

    // MARK: The hinge mixer

    /// The mixer works only in book and laptop, with Settings' "Hinge mixer" on.
    static func mixerActive(posture: Posture, on: Bool) -> Bool {
        on && (posture == .book || posture == .laptop)
    }

    /// The bar: "Commentary ◀━━●━━▶ Radio", the ● at the radio's share in five places (all
    /// commentary at the left, an even mix in the middle as the spec draws it, all radio at the right).
    static func mixBar(_ levels: MixLevels) -> String {
        let radio = levels.radio.isFinite ? min(max(levels.radio, 0), 1) : 0.5
        let at = Int((radio * 4).rounded())
        let line = String(repeating: "\u{2501}", count: at) + "\u{25CF}" + String(repeating: "\u{2501}", count: 4 - at)
        return "Commentary \u{25C0}\(line)\u{25B6} Radio"
    }

    /// The bar shows this long after the mix changes.
    static let mixBarSeconds: Double = 2

    /// Whether the bar (or "No radio to mix yet") still shows `now`, the mix having changed at `changed`.
    static func mixBarShows(changed: Date?, now: Date) -> Bool {
        guard let changed else { return false }
        let age = now.timeIntervalSince(changed)
        return age >= 0 && age < mixBarSeconds
    }
}

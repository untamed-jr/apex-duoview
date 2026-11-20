import Foundation
import LiveTiming

// Race Engineer's console and the Scrub Deck: their plain values and the pure arithmetic behind
// them (the readouts' texts, the pit line, the deck's axis, its hit tests and seek targets). No
// SwiftUI, no UIKit and no actor isolation, so all of it can be read (and checked) on its own.
// Everything here is built at the 2 Hz tick from timing at or before picture time; the Scrub
// Deck's only exception is the opt-in "Show the whole race".

// MARK: - Race Engineer's console

/// The car ahead or behind on the console: tapping it makes it the top onboard.
struct ConsoleRival: Equatable, Sendable {
    /// Its racing number (for the onboard); nil when F1 gives none.
    var number: String?
    var tla: String
    /// "+1.2s" ahead, "-0.8s" behind, or F1's own words ("1L").
    var gap: String
    /// The gap is shrinking (true) or growing (false) over the last 3 laps; nil with no trend.
    var closing: Bool?
}

/// One of the last 5 laps: its number, its time ("" when F1 sent none) and its sectors.
struct ConsoleLap: Equatable, Sendable, Identifiable {
    var lap: Int
    var time: String
    var sectors: [SectorPace]
    var id: Int { lap }
}

/// The console for the car on the top screen, at picture time.
struct ConsoleState: Equatable, Sendable {
    var number: String
    var tla: String
    var lastName: String
    /// "RRGGBB", or "" when F1 gives none.
    var teamColour: String
    /// Speed, gear, revs, throttle, brake and the light; nil before any car data reaches picture
    /// time (and always on a live item until live car data comes).
    var readout: Readout?
    /// The light's label ("DRS", "Aero"), or nil: channel 45 carries nothing (no light at all).
    var light: String?
    var race: Bool
    var position: Int?
    var ahead: ConsoleRival?
    var behind: ConsoleRival?
    /// "Medium · 18 laps", or nil.
    var tyre: String?
    /// "Pit now → P7 behind ALO", or why the pit circle has nothing yet; nil outside races.
    var pitLine: String?
    /// The last 5 laps finished, newest first.
    var laps: [ConsoleLap]

    /// The console for `number` at `t` (picture time): the readouts from `samples` (its car data
    /// around `t`, oldest first) with channel 45 read as `channel45`, and the race lines from
    /// timing at or before `t`. `storedPitLossMs` is this circuit's stored pit loss.
    static func make(number: String, at t: UTCms, session: LoadedSession, samples: [CarSample],
                     channel45: Channel45Meaning, storedPitLossMs: Int?) -> ConsoleState {
        let driver = session.drivers[number]
        let race = session.info.isRace
        let lines = RaceLines.at(t, car: number, session: session, storedPitLossMs: storedPitLossMs)
        let pitLine = ConsoleText.pitLine(
            race: race, pitNow: lines?.pitNow,
            circleShown: { PitCircle.layout(at: t, session: session, storedPitLossMs: storedPitLossMs) != nil },
            lapFinished: { session.timing.at(t).values.contains { ($0.numberOfLaps ?? 0) >= 1 } })
        return ConsoleState(
            number: number,
            tla: driver?.tla ?? number,
            lastName: driver?.lastName ?? "",
            teamColour: driver?.teamColour ?? "",
            readout: Readouts.at(t, samples: samples, channel45: channel45),
            light: channel45.label,
            race: race,
            position: lines?.position,
            ahead: lines?.ahead.map { ConsoleRival(number: lines?.aheadNumber, tla: $0.tla, gap: $0.gap, closing: $0.closing) },
            behind: lines?.behind.map { ConsoleRival(number: lines?.behindNumber, tla: $0.tla, gap: $0.gap, closing: $0.closing) },
            tyre: lines?.tyre.map { ConsoleText.tyre(compound: $0.compound, laps: $0.laps) },
            pitLine: pitLine,
            laps: (lines?.lastLaps ?? []).map { ConsoleLap(lap: $0.lap, time: $0.time, sectors: $0.sectors) })
    }
}

/// The console's fixed texts.
enum ConsoleText {
    /// Before the leader has finished a lap (the pit circle's own wording).
    static let circleStarts = "The circle starts once the leader has finished a lap."
    /// A lap is finished but the circle isn't there yet: joined late, until the leader's next
    /// crossing (controller ruling).
    static let circleNextLine = "The pit circle appears when the leader next crosses the line."
    /// Race Engineer with no onboard on the top screen.
    static let pickOnboard = "Tap a car to pick an onboard"
    /// A channel F1 left out: never shown as 0.
    static let absent = "\u{2014}"

    /// The pit line: "Pit now → …" when the circle places the car; otherwise, in a race, why there
    /// is none yet. `circleShown` and `lapFinished` are asked only when there is no pit line (the
    /// pit circle rescans the session's history). Nil outside races, and when the circle is there
    /// but doesn't place this car (retired, stopped).
    static func pitLine(race: Bool, pitNow: String?, circleShown: () -> Bool, lapFinished: () -> Bool) -> String? {
        guard race else { return nil }
        if let pitNow { return pitNow }
        if circleShown() { return nil }
        return lapFinished() ? circleNextLine : circleStarts
    }

    /// "Medium · 18 laps", "Soft · 1 lap".
    static func tyre(compound: String, laps: Int) -> String {
        "\(compound) \u{00B7} \(laps) \(laps == 1 ? "lap" : "laps")"
    }

    /// The gear: "N" for neutral, "—" when absent.
    static func gear(_ gear: Int?) -> String {
        guard let gear else { return absent }
        return gear == 0 ? "N" : "\(gear)"
    }

    /// "11840 rpm", or "—".
    static func rpm(_ rpm: Int?) -> String {
        rpm.map { "\($0) rpm" } ?? absent
    }

    /// The speed in the phone's units, or "—".
    static func speed(_ kmh: Int?, metric: Bool) -> String {
        kmh.map { TimingText.speed(kmh: $0, metric: metric) } ?? absent
    }

    /// "P4", or "—".
    static func position(_ position: Int?) -> String {
        position.map { "P\($0)" } ?? absent
    }

    /// A bar's fill, 0–1; nil (an empty bar) when the channel is absent.
    static func fill(_ percent: Int?) -> Double? {
        percent.map { Double(min(max($0, 0), 100)) / 100 }
    }

    /// The trend's words: "closing", "growing", or "".
    static func trend(_ closing: Bool?) -> String {
        switch closing {
        case true?: return "closing"
        case false?: return "growing"
        case nil: return ""
        }
    }
}

// MARK: - Scrub Deck

/// A car on the deck: its code and team colour ("RRGGBB").
struct DeckDriver: Equatable, Sendable {
    var tla: String
    var colour: String
}

/// A lap's first crossing of the line (the leader's), or lights out as lap 0.
struct DeckCrossing: Equatable, Sendable {
    var lap: Int
    var at: UTCms
}

/// What the Scrub Deck draws, at picture time (or the whole session with "Show the whole race").
struct DeckState: Equatable, Sendable {
    /// A race or sprint: the deck runs by lap and has the lap chart; otherwise by time.
    var race: Bool
    var rows: [LapChartRow]
    var events: [RaceEvent]
    /// Lights out (lap 0), then each lap's first crossing, up to the cut, oldest first.
    var crossings: [DeckCrossing]
    /// The race's length in laps (LapCount's total; known from the start, no spoiler).
    var totalLaps: Int
    /// "Show the whole race": no fog.
    var wholeRace: Bool
    /// One reading of the clock: picture time and the main feed's seconds read with it.
    var pictureTime: UTCms
    var playerSeconds: Double
    /// Your driver's racing number, highlighted.
    var favourite: String?
    var drivers: [String: DeckDriver]

    /// The deck at `t` (picture time). The lap chart, the events and the crossings are cut at
    /// `t`, or not at all with `wholeRace`.
    static func make(session: LoadedSession, at t: UTCms, playerSeconds: Double, wholeRace: Bool,
                     favourite: String?) -> DeckState {
        let cut: UTCms? = wholeRace ? nil : t
        let race = session.info.isRace
        let rows = LapChart.rows(until: cut, session: session)
        var drivers: [String: DeckDriver] = [:]
        for (number, info) in session.drivers { drivers[number] = DeckDriver(tla: info.tla, colour: info.teamColour) }
        let crossings = race ? Self.crossings(session: session, cars: Set(rows.map(\.number)).union(session.drivers.keys), cut: cut) : []
        let lastLap = crossings.last?.lap ?? 0
        let total = session.header.at(cut ?? .max).totalLaps ?? (lastLap + 1)
        return DeckState(
            race: race, rows: rows, events: RaceEvents.list(until: cut, session: session), crossings: crossings,
            totalLaps: max(total, lastLap, 1), wholeRace: wholeRace, pictureTime: t, playerSeconds: playerSeconds,
            favourite: favourite, drivers: drivers)
    }

    /// Lights out, then each lap's first crossing by any car, at or before `cut` (nil: all), keeping
    /// only crossings later than the one before (a strictly increasing axis).
    static func crossings(session: LoadedSession, cars: Set<String>, cut: UTCms?) -> [DeckCrossing] {
        let limit = cut ?? .max
        guard let lightsOut = session.sessionStatus.started, lightsOut <= limit else { return [] }
        var first: [Int: UTCms] = [:]
        for car in cars {
            for lap in session.timing.completedLaps(of: car, upTo: limit) where lap.lap >= 1 && lap.crossedAt <= limit {
                first[lap.lap] = min(first[lap.lap] ?? .max, lap.crossedAt)
            }
        }
        var out = [DeckCrossing(lap: 0, at: lightsOut)]
        for lap in first.keys.sorted() {
            guard let at = first[lap], let last = out.last, lap > last.lap, at > last.at else { continue }
            out.append(DeckCrossing(lap: lap, at: at))
        }
        return out
    }

    /// The main feed's seconds at moment `u`: the inverse of picture time, as the timeline marks
    /// do (`TimelineMark.marks`).
    func seconds(of u: UTCms) -> Double {
        playerSeconds + Double(u - pictureTime) / 1000
    }

    /// Picture time where the main feed is at `seconds`; nil for a time that isn't finite (or is
    /// beyond any session).
    func moment(atSeconds seconds: Double) -> UTCms? {
        let ms = ((seconds - playerSeconds) * 1000).rounded()
        guard ms.isFinite, abs(ms) < 1e15 else { return nil }
        return pictureTime + UTCms(ms)
    }

    /// A marker's seek: 5 s before its moment, kept inside the scrubber's span.
    func markerTarget(_ u: UTCms, timeline: ClosedRange<Double>?) -> Double {
        let target = seconds(of: u) - DeckAxis.markerLeadSeconds
        guard let timeline else { return max(target, 0) }
        return min(max(target, timeline.lowerBound), timeline.upperBound)
    }
}

/// One point of the deck's axis: a fraction across its width and the main feed's seconds there.
struct DeckAnchor: Equatable, Sendable {
    var f: Double
    var s: Double
}

/// The Scrub Deck's horizontal axis, between fractions of its width (0–1) and the main feed's
/// seconds, piecewise linear between anchors.
///
/// - A race runs by lap: lap k's first crossing sits at k / total laps, lights out at 0. Up to
///   picture time the anchors are the crossings (and picture time itself, placed by how far the
///   current lap has gone at the last lap's pace). Beyond it is the fog: nothing after picture
///   time is read, so dragging there goes linearly from picture time to the end of the video
///   (the scrubber's span, which the player already shows) and the lap there is unknown.
/// - Any other session runs by time: the scrubber's span from end to end.
struct DeckAxis: Equatable, Sendable {
    /// A marker tap seeks this far before its moment.
    static let markerLeadSeconds = 5.0
    /// Until the leader has finished a lap, the fog's edge places picture time as if a lap took
    /// this long (an estimate for drawing only; no data after picture time).
    static let fallbackLapMs: Int64 = 90_000

    /// Increasing in both values.
    var anchors: [DeckAnchor]
    /// Where the fog starts (picture time); nil with "Show the whole race".
    var fogFrom: Double?
    /// Lap k sits at k / `totalLaps` (races only).
    var totalLaps: Int?

    static let empty = DeckAxis(anchors: [], fogFrom: nil, totalLaps: nil)

    /// The axis for `deck` with the scrubber spanning `timeline` (nil until the main feed knows).
    static func make(_ deck: DeckState, timeline: ClosedRange<Double>?) -> DeckAxis {
        var points: [DeckAnchor] = []
        func add(_ f: Double, _ s: Double) {
            guard f.isFinite, s.isFinite else { return }
            if let last = points.last, !(f > last.f && s > last.s) { return }
            points.append(DeckAnchor(f: min(max(f, 0), 1), s: s))
        }
        // By time: other sessions, and a race whose lights out isn't known (with the whole race on
        // there is then nothing to lay laps out from).
        guard deck.race, !(deck.wholeRace && deck.crossings.isEmpty) else {
            guard let timeline, timeline.upperBound > timeline.lowerBound else { return .empty }
            add(0, timeline.lowerBound)
            add(1, timeline.upperBound)
            let axis = DeckAxis(anchors: points, fogFrom: nil, totalLaps: nil)
            let fog = deck.wholeRace ? nil : axis.fraction(ofSeconds: deck.seconds(of: deck.pictureTime))
            return DeckAxis(anchors: points, fogFrom: fog, totalLaps: nil)
        }
        let total = Double(max(deck.totalLaps, 1))
        for crossing in deck.crossings {
            add(Double(crossing.lap) / total, deck.seconds(of: crossing.at))
        }
        var fog: Double?
        if !deck.wholeRace {
            // Picture time: how far into the lap after the last crossing, at the last lap's pace.
            let t = deck.pictureTime
            var lapNow = 0.0
            if let last = deck.crossings.last {
                let previous = deck.crossings.count >= 2 ? deck.crossings[deck.crossings.count - 2] : nil
                let lapMs = previous.map { last.at - $0.at } ?? fallbackLapMs
                let into = lapMs > 0 ? Double(max(t - last.at, 0)) / Double(lapMs) : 0
                lapNow = Double(last.lap) + min(into, 0.999)
            }
            let f = min(lapNow / total, 1)
            add(f, deck.seconds(of: t))
            fog = points.last?.f ?? f
        }
        if let timeline, let last = points.last, last.f < 1, timeline.upperBound > last.s {
            add(1, timeline.upperBound)
        }
        return DeckAxis(anchors: points, fogFrom: fog, totalLaps: deck.totalLaps)
    }

    /// The main feed's seconds at fraction `f` (clamped to the axis); nil with no axis.
    func seconds(atFraction f: Double) -> Double? {
        guard let first = anchors.first, let last = anchors.last else { return nil }
        guard anchors.count >= 2 else { return first.s }
        let x = min(max(f, first.f), last.f)
        for i in 1..<anchors.count where x <= anchors[i].f {
            let a = anchors[i - 1], b = anchors[i]
            return a.s + (b.s - a.s) * (x - a.f) / (b.f - a.f)
        }
        return last.s
    }

    /// The fraction where the main feed is at `seconds` (clamped to the axis); nil with no axis.
    func fraction(ofSeconds s: Double) -> Double? {
        guard let first = anchors.first, let last = anchors.last, s.isFinite else { return nil }
        guard anchors.count >= 2 else { return first.f }
        let y = min(max(s, first.s), last.s)
        for i in 1..<anchors.count where y <= anchors[i].s {
            let a = anchors[i - 1], b = anchors[i]
            return a.f + (b.f - a.f) * (y - a.s) / (b.s - a.s)
        }
        return last.f
    }

    /// Lap k's place (races).
    func fraction(ofLap lap: Int) -> Double? {
        guard let totalLaps, totalLaps > 0 else { return nil }
        return Double(lap) / Double(totalLaps)
    }

    /// The lap being run at fraction `f`, for the drag readout; nil in the fog (unknown) and
    /// outside races.
    func lap(atFraction f: Double) -> Int? {
        guard let totalLaps, totalLaps > 0 else { return nil }
        if let fogFrom, f > fogFrom { return nil }
        return min(Int((max(f, 0) * Double(totalLaps)).rounded(.down)) + 1, totalLaps)
    }
}

/// A marker on the event strip, placed on the axis.
struct DeckMarker: Equatable, Sendable {
    var event: RaceEvent
    var f: Double
    /// A band's or a pit stop's end (picture time for one still going, unless the whole race).
    var endF: Double?

    /// The events placed on `axis`; one before or after the axis sits at its end.
    static func place(_ deck: DeckState, axis: DeckAxis) -> [DeckMarker] {
        deck.events.compactMap { event in
            guard let f = axis.fraction(ofSeconds: deck.seconds(of: event.t)) else { return nil }
            var endF: Double?
            switch event.kind {
            case .safetyCar, .vsc, .red, .pit:
                // Still going: to picture time, or (the whole race) to the end of the deck.
                if let end = event.end ?? (deck.wholeRace ? nil : deck.pictureTime) {
                    endF = axis.fraction(ofSeconds: deck.seconds(of: end))
                } else {
                    endF = 1
                }
            default:
                break
            }
            return DeckMarker(event: event, f: f, endF: endF)
        }
    }

    var isBand: Bool {
        switch event.kind {
        case .safetyCar, .vsc, .red: return true
        default: return false
        }
    }

    /// The car it belongs to, if any.
    var car: String? {
        switch event.kind {
        case .pit(let car), .fastestLap(let car), .retirement(let car): return car
        default: return nil
        }
    }
}

/// What a tap on the deck means.
enum DeckHitTest {
    /// A 44 pt target, as the map's dots.
    static let radius: Double = 22
    /// How close (vertically) a tap must be to a lap chart line.
    static let lineRadius: Double = 12

    /// The marker nearest `x` (points, and a band's start) within the radius; else a band that
    /// covers `x`. `width` is the strip's width in points.
    static func marker(atX x: Double, in markers: [DeckMarker], width: Double) -> DeckMarker? {
        var best: (marker: DeckMarker, distance: Double)?
        for marker in markers {
            let d = abs(marker.f * width - x)
            if d <= radius, d < (best?.distance ?? .infinity) { best = (marker, d) }
        }
        if let best { return best.marker }
        return markers.last { $0.isBand && x >= $0.f * width && x <= ($0.endF ?? $0.f) * width }
    }

    /// The lap chart line nearest `point` (in a chart of `size` points), within `lineRadius`
    /// vertically, where the line is drawn at that x.
    static func line(at point: (x: Double, y: Double), rows: [LapChartRow], axis: DeckAxis,
                     size: (width: Double, height: Double)) -> String? {
        let places = max(rows.count, 2)
        var best: (number: String, distance: Double)?
        for row in rows {
            guard let y = LapChartGeometry.y(row: row, atX: point.x, axis: axis, size: size, places: places) else { continue }
            let d = abs(y - point.y)
            if d <= lineRadius, d < (best?.distance ?? .infinity) { best = (row.number, d) }
        }
        return best?.number
    }
}

/// Where the lap chart draws: position 1 at the top, the last place at the bottom; lap k at its
/// fraction of the width.
enum LapChartGeometry {
    /// The y of `position` in a chart of `height` with `places` positions (inset by half a row).
    static func y(position: Int, places: Int, height: Double) -> Double {
        let n = max(places, 2)
        let row = height / Double(n)
        return row / 2 + Double(min(max(position, 1), n) - 1) * row
    }

    /// Each lap the row has a position for, as (x, y) in a chart of `size`.
    static func points(_ row: LapChartRow, axis: DeckAxis, size: (width: Double, height: Double),
                       places: Int) -> [(x: Double, y: Double)] {
        row.positions.enumerated().compactMap { index, position in
            guard let position, let f = axis.fraction(ofLap: index + 1) else { return nil }
            return (f * size.width, y(position: position, places: places, height: size.height))
        }
    }

    /// The row's line's y at `x`, between its two points either side; nil where it isn't drawn.
    static func y(row: LapChartRow, atX x: Double, axis: DeckAxis, size: (width: Double, height: Double),
                  places: Int) -> Double? {
        let pts = points(row, axis: axis, size: size, places: places)
        guard let first = pts.first else { return nil }
        if pts.count == 1 { return abs(first.x - x) <= DeckHitTest.radius ? first.y : nil }
        for i in 1..<pts.count where x <= pts[i].x {
            let a = pts[i - 1], b = pts[i]
            guard x >= a.x - DeckHitTest.radius else { return nil }
            if x <= a.x { return a.y }
            return a.y + (b.y - a.y) * (x - a.x) / max(b.x - a.x, 0.0001)
        }
        let last = pts[pts.count - 1]
        return x - last.x <= DeckHitTest.radius ? last.y : nil
    }
}

// MARK: - What a build depends on

/// Everything the console's build depends on: a build whose key matches the current one is
/// reused (paused, nothing new), so the session's history isn't rescanned.
struct ConsoleKey: Equatable, Sendable {
    /// Which loaded session (bumped whenever the timing replaces it: a load, live, a top-up).
    var session: Int
    var car: String
    var t: UTCms
    /// The car data window as it stands: its size and its latest sample.
    var samples: Int
    var lastSample: UTCms?
    var channel45: Channel45Meaning
    var storedPitLossMs: Int?
}

/// Everything the deck's build depends on.
struct DeckKey: Equatable, Sendable {
    var session: Int
    /// Picture time, or nil for the whole race (built once, whatever the moment).
    var cut: UTCms?
    var favourite: String?
}

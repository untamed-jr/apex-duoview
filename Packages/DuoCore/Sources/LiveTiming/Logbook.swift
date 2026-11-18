import Foundation
import F1TV

/// One race control message, with the cars it is about.
public struct RaceControlEntry: Sendable, Equatable {
    public var t: UTCms
    public var text: String
    /// Racing numbers: the message's `RacingNumber`, then every "CAR 44 (HAM)" and every number
    /// in a "CARS 87 (BEA) AND 55 (SAI)" list in the text, each once.
    public var cars: [String]
    /// F1's raw `Category` ("Flag", "Other"…) and `Flag` ("BLUE", "YELLOW"…); nil when absent.
    public var category: String?
    public var flag: String?

    public init(t: UTCms, text: String, cars: [String], category: String? = nil, flag: String? = nil) {
        self.t = t
        self.text = text
        self.cars = cars
        self.category = category
        self.flag = flag
    }
}

/// Race control messages by car, for the Logbook. Whole session: what is shown must be cut at
/// picture time (`entries(for:until:in:)`).
public struct RaceControlLog: Sendable, Equatable {
    /// Oldest first, equal times in the order sent.
    public private(set) var all: [RaceControlEntry] = []
    private var seen: Set<String> = []
    private let streamStart: UTCms

    public init(streamStart: UTCms) { self.streamStart = streamStart }

    public init(lines: [StreamLine], streamStart: UTCms) {
        self.streamStart = streamStart
        for line in lines { add(line) }
    }

    /// Adds a line's messages (the live feed adds lines as they come), read as `TrackFlags` reads
    /// them: a list or index-keyed entries; a message without a readable Utc takes its line's
    /// time. A message sent again with the same time and words is kept once (the first), as
    /// beta.3 listed them. Messages with no text are skipped.
    public mutating func add(_ line: StreamLine) {
        for m in TrackFlags.controlMessages([line], streamStart: streamStart) {
            let text = m.message["Message"].string
            guard !text.isEmpty, seen.insert("\(m.utc)|\(text)").inserted else { continue }
            var cars: [String] = []
            func add(_ number: String) { if !number.isEmpty, !cars.contains(number) { cars.append(number) } }
            add(Self.racingNumber(m.message["RacingNumber"]))
            for number in Self.carNumbers(in: text) { add(number) }
            let category = m.message["Category"].string, flag = m.message["Flag"].string
            let entry = RaceControlEntry(t: m.utc, text: text, cars: cars,
                                         category: category.isEmpty ? nil : category, flag: flag.isEmpty ? nil : flag)
            // After every entry at or before its time: sorted, and arrival order on ties.
            var lo = all.startIndex, hi = all.endIndex
            while lo < hi {
                let mid = (lo + hi) / 2
                if all[mid].t <= entry.t { lo = mid + 1 } else { hi = mid }
            }
            all.insert(entry, at: lo)
        }
    }

    /// The messages of RaceControlMessages lines, oldest first, equal times in the order sent.
    public static func parse(lines: [StreamLine], streamStart: UTCms) -> [RaceControlEntry] {
        RaceControlLog(lines: lines, streamStart: streamStart).all
    }

    /// The entries about `car` at or before `t` (picture time; nil is the whole race), in order.
    public static func entries(for car: String, until t: UTCms?, in all: [RaceControlEntry]) -> [RaceControlEntry] {
        let cut = t ?? .max
        return all.filter { $0.t <= cut && $0.cars.contains(car) }
    }

    /// F1 writes the number as text or as a number.
    private static func racingNumber(_ value: JSONValue) -> String {
        let text = value.string
        if !text.isEmpty { return text }
        if let n = value.int { return String(n) }
        return ""
    }

    /// "CAR 44 (HAM)" and the multi-car "CARS 87 (BEA) AND 55 (SAI)": every "number (CODE)".
    private static let carPattern = try? NSRegularExpression(pattern: #"\b(\d{1,3}) \([A-Z]{3}\)"#)
    private static let singlePattern = try? NSRegularExpression(pattern: #"\bCAR (\d{1,3})\b"#)

    private static func carNumbers(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [(Int, String)] = []
        for regex in [singlePattern, carPattern] {
            guard let regex else { continue }
            for m in regex.matches(in: text, range: range) {
                if let r = Range(m.range(at: 1), in: text) { found.append((m.range.location, String(text[r]))) }
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

/// One pit stop in a car's logbook.
public struct LogbookStop: Sendable, Equatable {
    /// The car's own lap (its laps done plus one) when it came in; nil if its lap count isn't known.
    public var lap: Int?
    /// Time in the pit lane; nil while the car is still in it at picture time.
    public var laneMs: Int?
    /// The compound taken off and the one put on; nil when not known (yet).
    public var off: String?
    public var on: String?

    public init(lap: Int?, laneMs: Int?, off: String?, on: String?) {
        self.lap = lap
        self.laneMs = laneMs
        self.off = off
        self.on = on
    }
}

/// One car's logbook at a moment: everything known about it at or before picture time.
public struct LogbookModel: Sendable, Equatable {
    public var number: String
    public var position: Int?
    /// The tyre on now and the laps it has done.
    public var tyre: (compound: String, laps: Int)?
    /// The last lap time as F1 writes it ("1:29.518").
    public var lastLap: String?
    /// Only this car's clips that exist at picture time (`RadioClips.visible(at:driver:)`), oldest first.
    public var radio: [RadioClip]
    public var laps: [CompletedLap]
    public var stops: [LogbookStop]
    public var raceControl: [RaceControlEntry]
    /// Racing numbers of the cars in the positions either side.
    public var ahead: String?
    public var behind: String?

    public init(number: String, position: Int? = nil, tyre: (compound: String, laps: Int)? = nil, lastLap: String? = nil,
                radio: [RadioClip] = [], laps: [CompletedLap] = [], stops: [LogbookStop] = [],
                raceControl: [RaceControlEntry] = [], ahead: String? = nil, behind: String? = nil) {
        self.number = number
        self.position = position
        self.tyre = tyre
        self.lastLap = lastLap
        self.radio = radio
        self.laps = laps
        self.stops = stops
        self.raceControl = raceControl
        self.ahead = ahead
        self.behind = behind
    }

    public static func == (a: LogbookModel, b: LogbookModel) -> Bool {
        a.number == b.number && a.position == b.position
            && a.tyre?.compound == b.tyre?.compound && a.tyre?.laps == b.tyre?.laps
            && a.lastLap == b.lastLap && a.radio == b.radio && a.laps == b.laps && a.stops == b.stops
            && a.raceControl == b.raceControl && a.ahead == b.ahead && a.behind == b.behind
    }
}

public enum Logbook {
    /// The logbook of `car` (racing number) at picture time `t`; nil `t` is the whole race. Nil
    /// when the session knows no such car (no driver, no timing). Everything is read at or before
    /// `t`: a stop still in the lane has no lane time, and its new tyre is named only once the
    /// stints data at `t` has it.
    public static func at(_ t: UTCms?, car: String, session: LoadedSession, radio: RadioClips,
                          raceControl: [RaceControlEntry]) -> LogbookModel? {
        guard session.drivers[car] != nil || session.timing.cars[car] != nil else { return nil }
        let cut = t ?? .max
        let state = session.timing.state(of: car, at: cut)
        let stints = session.stints.at(cut)[car] ?? []

        var ahead: String?, behind: String?
        if let position = state?.position {
            for (number, other) in session.timing.at(cut) where number != car {
                guard let p = other.position else { continue }
                if p == position - 1 { ahead = number }
                if p == position + 1 { behind = number }
            }
        }

        var stops: [LogbookStop] = []
        for event in RaceEvents.list(until: t, session: session) {
            guard case .pit(let who) = event.kind, who == car else { continue }
            let before = session.stints.at(event.t)[car] ?? []
            // The set after the one on at pit-in (the opening stint when none was known yet).
            let next = max(before.count, 1)
            let lap = session.timing.state(of: car, at: event.t)?.numberOfLaps.map { $0 == .max ? $0 : $0 + 1 }
            stops.append(LogbookStop(
                lap: lap ?? event.lap,
                laneMs: event.end.map { Int(clamping: F1Values.sub($0, event.t)) },
                off: before.last?.compound,
                on: stints.count > next ? stints[next].compound : nil))
        }

        return LogbookModel(
            number: car,
            position: state?.position,
            tyre: stints.last.map { ($0.compound, $0.totalLaps) },
            lastLap: state?.lastLapMs.map(Tower.lapText),
            radio: radio.visible(at: t, driver: car),
            laps: session.timing.completedLaps(of: car, upTo: cut),
            stops: stops,
            raceControl: RaceControlLog.entries(for: car, until: t, in: raceControl),
            ahead: ahead,
            behind: behind)
    }
}

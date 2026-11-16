import Foundation
import LiveTiming
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// The timing views' plain values and the pure arithmetic behind them: no SwiftUI, no UIKit and no
// actor isolation, so all of it can be read (and checked) on its own.

/// Where timing stands for the video being watched.
enum TimingStatus: Equatable, Sendable {
    /// Nothing is attached.
    case idle
    /// Finding and loading the session's timing.
    case loading
    /// Loaded, and picture time comes from the stream's program date.
    case ready
    /// No timing to show, with the reason ("No timing for this session"), or the load failed and
    /// is being tried again ("Map unavailable — trying again…").
    case unavailable(String)
    /// Loaded, but the stream has no program date: picture time is the session start plus the
    /// player's position.
    case estimated
}

/// The floating panels. The raw values name them in `TimingSettings` (no "." allowed there).
enum TimingPanel: String, CaseIterable, Sendable {
    case map
    case tower
}

/// What the 2 Hz views read: every value at picture time, never later.
struct TimingSnapshot: Equatable, Sendable {
    var drivers: [String: DriverInfo]
    var flags: FlagState
    var header: SessionHeader
    var timing: [String: DriverTimingState]
    var stints: [String: [Stint]]
    /// F1's session status at picture time ("Started", "Finished", ...); nil before the first.
    var sessionStatus: String?
    var pictureTime: UTCms?

    static let empty = TimingSnapshot(
        drivers: [:], flags: FlagState(status: .clear), header: SessionHeader(), timing: [:], stints: [:],
        sessionStatus: nil, pictureTime: nil)
}

/// The session header over the tower, at picture time: "Lap 23/71" in a race, else the session
/// clock; the track status; the weather.
struct SessionHeaderState: Equatable, Sendable {
    /// "Lap 23/71", "1:04:12", or "" before either is known.
    var progress: String
    var status: TrackStatusKind
    /// "Air 24° · Track 41°", or "" without weather.
    var weather: String
    var raining: Bool

    static let empty = SessionHeaderState(progress: "", status: .clear, weather: "", raining: false)

    init(progress: String, status: TrackStatusKind, weather: String, raining: Bool) {
        self.progress = progress
        self.status = status
        self.weather = weather
        self.raining = raining
    }

    /// From the header and the flags at picture time. `race`: the lap count shows (F1's LapCount
    /// is only sent for races); otherwise the clock.
    init(header: SessionHeader, flags: FlagState, race: Bool) {
        self.init(
            progress: TimingText.progress(header, race: race),
            status: flags.status,
            weather: TimingText.weather(air: header.airTemp, track: header.trackTemp),
            raining: header.raining)
    }
}

/// A driver card over an onboard at picture time: the DuoCore card and the speed readout.
struct DriverCardState: Equatable, Sendable {
    var card: DriverCardModel
    /// Km/h from the car data at picture time; nil when there is none yet, it is more than 5 s
    /// old, or F1 sent no speed channel (absent is never 0).
    var speedKmh: Int?
}

/// Your driver's rival in a battle, for the map's Battle chip (tapping it opens their onboard).
struct BattleRival: Equatable, Sendable {
    var number: String
    var tla: String

    /// The car the favourite (a racing number) battles with among the tower's glowing rows: the
    /// one ahead first, as the rows run in position order. Nil without a favourite or a battle.
    static func from(_ rows: [TowerRow], favourite: String?) -> BattleRival? {
        guard let favourite, rows.contains(where: { $0.number == favourite && $0.battle }),
              let row = rows.first(where: { $0.battle && $0.number != favourite }) else { return nil }
        return BattleRival(number: row.number, tla: row.tla)
    }
}

/// The fixed texts the tower, header and cards show. Plain functions, no SwiftUI.
enum TimingText {
    /// "Lap 23/71" in a race (or "Lap 23" before the total is known), else the session clock
    /// ("1:04:12", "18:00"); "" when neither is known.
    static func progress(_ header: SessionHeader, race: Bool) -> String {
        if race, let lap = header.lap {
            return header.totalLaps.map { "Lap \(lap)/\($0)" } ?? "Lap \(lap)"
        }
        guard let seconds = header.clockRemaining else { return "" }
        return clock(seconds)
    }

    /// Whole seconds as "h:mm:ss", or "m:ss" under an hour.
    static func clock(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let h = s / 3600, m = s / 60 % 60, r = s % 60
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(r))" : "\(m):\(two(r))"
    }

    /// The track status as the header words it: "Green", "Yellow", or the flag's own label.
    static func status(_ kind: TrackStatusKind) -> String {
        switch kind {
        case .clear: return "Green"
        case .yellow: return "Yellow"
        default: return kind.label ?? ""
        }
    }

    /// "Air 24° · Track 41°", either part alone, or "" with neither.
    static func weather(air: Double?, track: Double?) -> String {
        func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
        var parts: [String] = []
        if let air, air.isFinite { parts.append("Air " + degrees(air)) }
        if let track, track.isFinite { parts.append("Track " + degrees(track)) }
        return parts.joined(separator: " · ")
    }

    /// Km/h in the phone's units: km/h with the metric system, mph with the US and UK ones.
    static func speed(kmh: Int, metric: Bool) -> String {
        metric ? "\(kmh) km/h" : "\(Int((Double(kmh) * 0.621_371).rounded())) mph"
    }

    /// Whether this measurement system shows km/h (only the metric one: the UK's roads are mph).
    static func usesKilometres(_ system: Locale.MeasurementSystem) -> Bool {
        system == .metric
    }
}

/// One car dot on the map.
struct MapCar: Equatable, Sendable {
    var number: String
    var tla: String
    /// The team colour as "RRGGBB"; "" when F1 gives none.
    var colour: String
    /// In archive coordinates; `MapTransform` puts it on screen.
    var point: TrackPoint
    /// In the pits, knocked out or stopped: drawn dimmer and smaller.
    var dimmed: Bool
    /// A flying lap in qualifying (`LapStates`).
    var flyingRing: Bool
}

/// What the map draws at one moment (computed at the display's frame rate).
struct MapState: Equatable, Sendable {
    var cars: [MapCar]
    var flags: FlagState
    var caption: String?
    /// The safety car's dot, just ahead of the leader, while it is out.
    var safetyCar: TrackPoint?

    static let empty = MapState(cars: [], flags: FlagState(status: .clear), caption: nil, safetyCar: nil)
}

/// Where a mark goes on the scrubber.
enum TimelineMarkLayout {
    /// How far in from each end of the slider's frame its track runs (about half the thumb).
    static let trackInset: CGFloat = 14

    /// The x of `seconds` across `width` for a scrubber spanning `range`.
    static func x(of seconds: Double, in range: ClosedRange<Double>, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0, seconds.isFinite, width > 0 else { return 0 }
        let fraction = min(max((seconds - range.lowerBound) / span, 0), 1)
        return CGFloat(fraction) * width
    }
}

/// The circuit as the map draws it.
struct TrackMap: Sendable {
    let geometry: TrackGeometry
    let corners: [Corner]
    /// Outline indices along each marshal sector, by sector number − 1. Empty for a traced outline.
    let sectorRuns: [[Int]]
    /// The outline point at the start/finish line, when the crossings pin it.
    let startIndex: Int?
    /// The cars go round in the outline's index order.
    let forward: Bool
    /// Traced from the cars' own positions (MultiViewer had none, or couldn't be reached).
    let traced: Bool

    /// Each marshal sector's run of outline indices, from its start to the next sector's (the last
    /// back round to the first). Sectors are numbered in driving order; when their starts go round
    /// the outline against its index order, each run is taken the other way so it still covers
    /// only its own stretch. Empty with fewer than 2 starts or 2 outline points.
    static func sectorRuns(outlineCount n: Int, starts: [Int]) -> [[Int]] {
        let m = starts.count
        guard n >= 2, m >= 2, starts.allSatisfy({ (0..<n).contains($0) }) else { return [] }
        // In index order the starts go round exactly once (n in all); against it, m − 1 times.
        var total = 0
        for k in 0..<m { total += (starts[(k + 1) % m] - starts[k] + n) % n }
        let forward = total * 2 <= m * n
        return (0..<m).map { k in
            let a = starts[k], b = starts[(k + 1) % m]
            let (from, to) = forward ? (a, b) : (b, a)
            var run = [from]
            var i = from
            while i != to {
                i = (i + 1) % n
                run.append(i)
            }
            return run
        }
    }

    /// Whether the cars go round in the outline's index order: a vote over a few hundred moments
    /// of the cars with the most samples (2 s apart, as far round as a car really moves).
    static func drivesForward(_ geometry: TrackGeometry, positions: PositionSeries) -> Bool {
        let cars = positions.cars.values.sorted { ($0.times.count, $1.number) > ($1.times.count, $0.number) }.prefix(3)
        var votes = 0
        for car in cars {
            let step = max(car.times.count / 200, 1)
            for i in stride(from: 0, to: car.times.count, by: step) {
                let t = car.times[i]
                guard let a = car.mapPoint(at: t), let b = car.mapPoint(at: t + 2_000) else { continue }
                var d = geometry.progress(of: b) - geometry.progress(of: a)
                if d > 0.5 { d -= 1 } else if d < -0.5 { d += 1 }
                guard abs(d) > 0.000_5, abs(d) < 0.1 else { continue }
                votes += d > 0 ? 1 : -1
            }
        }
        return votes >= 0
    }
}

/// A corner number where the map writes it.
struct CornerLabel: Sendable {
    var text: String
    var at: CGPoint
}

/// The map projected into a box: everything that doesn't move with picture time, computed when
/// the box or the turn changes, never per frame.
struct ProjectedMap: Sendable {
    var outline: [CGPoint]
    var sectors: [[CGPoint]]
    var corners: [CornerLabel]
    /// The chequered line across the track, and where START (ahead of it) and FINISH (behind it) go.
    var startLine: (from: CGPoint, to: CGPoint)?
    var startLabel: CGPoint?
    var finishLabel: CGPoint?

    /// Corner numbers sit this far out from the track, away from the outline's centre.
    static let cornerOffset: CGFloat = 11
    /// Half the start line's length.
    static let startHalfLength: CGFloat = 7

    init(map: TrackMap, transform: MapTransform) {
        let outline = map.geometry.outline.map { transform.point($0) }
        self.outline = outline
        sectors = map.sectorRuns.map { run in run.compactMap { outline.indices.contains($0) ? outline[$0] : nil } }
        let count = CGFloat(max(outline.count, 1))
        let centre = CGPoint(x: outline.reduce(0) { $0 + $1.x } / count, y: outline.reduce(0) { $0 + $1.y } / count)
        corners = map.corners.map { corner in
            let p = transform.point(corner.at)
            let away = Self.unit(CGPoint(x: p.x - centre.x, y: p.y - centre.y))
            return CornerLabel(text: "\(corner.number)\(corner.letter)",
                               at: CGPoint(x: p.x + away.x * Self.cornerOffset, y: p.y + away.y * Self.cornerOffset))
        }
        guard let i = map.startIndex, outline.count >= 3, outline.indices.contains(i) else { return }
        let n = outline.count
        let p = outline[i]
        let ahead = outline[(i + 1) % n], behind = outline[(i - 1 + n) % n]
        var along = Self.unit(CGPoint(x: ahead.x - behind.x, y: ahead.y - behind.y))
        if !map.forward { along = CGPoint(x: -along.x, y: -along.y) }
        let across = CGPoint(x: -along.y, y: along.x)
        let h = Self.startHalfLength
        startLine = (CGPoint(x: p.x - across.x * h, y: p.y - across.y * h), CGPoint(x: p.x + across.x * h, y: p.y + across.y * h))
        startLabel = CGPoint(x: p.x + along.x * 18 + across.x * 12, y: p.y + along.y * 18 + across.y * 12)
        finishLabel = CGPoint(x: p.x - along.x * 18 + across.x * 12, y: p.y - along.y * 18 + across.y * 12)
    }

    static func unit(_ v: CGPoint) -> CGPoint {
        let length = (v.x * v.x + v.y * v.y).squareRoot()
        guard length > 0, length.isFinite else { return CGPoint(x: 0, y: -1) }
        return CGPoint(x: v.x / length, y: v.y / length)
    }
}

/// Which car a tap on the map means.
enum MapHitTest {
    /// The 44 pt touch target: a tap this close to a dot's centre is on it.
    static let radius: CGFloat = 22

    /// The car whose dot is nearest `point`, if within `radius`.
    static func car(at point: CGPoint, among dots: [(number: String, at: CGPoint)], radius: CGFloat = MapHitTest.radius) -> String? {
        var best: (number: String, distance: CGFloat)?
        for dot in dots {
            let d = ((dot.at.x - point.x) * (dot.at.x - point.x) + (dot.at.y - point.y) * (dot.at.y - point.y)).squareRoot()
            if d <= radius, d < (best?.distance ?? .infinity) { best = (dot.number, d) }
        }
        return best?.number
    }
}

/// Floating panel frames: where they start, and how moving, resizing and pinching keep them on
/// screen and usable.
enum PanelLayout {
    static let minimumSize = CGSize(width: 200, height: 150)
    /// Kept clear of the area's edges.
    static let margin: CGFloat = 6

    /// The key a panel's frame is saved under: the fold's posture and whether the screen is wider
    /// than tall ("book-wide", "unknown-tall"), so each shape of screen keeps its own place. No
    /// "." (TimingSettings uses it to separate the parts of a key).
    static func postureKey(posture: String, size: CGSize) -> String {
        let shape = size.width >= size.height ? "wide" : "tall"
        return posture.replacingOccurrences(of: ".", with: "-") + "-" + shape
    }

    /// Where a panel starts: the map at the top right, the tower at the top left, below the
    /// controls' top bar.
    static func defaultFrame(_ panel: TimingPanel, in bounds: CGRect) -> CGRect {
        let top = bounds.minY + 60
        switch panel {
        case .map:
            let size = CGSize(width: 320, height: 230)
            return clamped(CGRect(x: bounds.maxX - size.width - 12, y: top, width: size.width, height: size.height), in: bounds)
        case .tower:
            // Room for every column (position, code, last lap, gap, interval, tyre) and the header.
            let size = CGSize(width: 300, height: 360)
            return clamped(CGRect(x: bounds.minX + 12, y: top, width: size.width, height: size.height), in: bounds)
        }
    }

    /// At least the minimum size (unless the area is smaller), no larger than the area, and
    /// wholly inside it.
    static func clamped(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        let area = bounds.insetBy(dx: margin, dy: margin)
        guard area.width > 0, area.height > 0 else { return frame }
        let finite = frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
        let source = finite ? frame : CGRect(x: area.minX, y: area.minY, width: minimumSize.width, height: minimumSize.height)
        let width = min(max(source.width, min(minimumSize.width, area.width)), area.width)
        let height = min(max(source.height, min(minimumSize.height, area.height)), area.height)
        let x = min(max(source.minX, area.minX), area.maxX - width)
        let y = min(max(source.minY, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func moved(_ frame: CGRect, by translation: CGSize, in bounds: CGRect) -> CGRect {
        clamped(frame.offsetBy(dx: translation.width, dy: translation.height), in: bounds)
    }

    /// Dragging the bottom-trailing corner.
    static func resized(_ frame: CGRect, by translation: CGSize, in bounds: CGRect) -> CGRect {
        let area = bounds.insetBy(dx: margin, dy: margin)
        var out = frame
        out.size.width = min(max(frame.width + translation.width, minimumSize.width), max(area.maxX - frame.minX, minimumSize.width))
        out.size.height = min(max(frame.height + translation.height, minimumSize.height), max(area.maxY - frame.minY, minimumSize.height))
        return clamped(out, in: bounds)
    }

    /// A pinch: scaled about its centre.
    static func scaled(_ frame: CGRect, by scale: CGFloat, in bounds: CGRect) -> CGRect {
        guard scale.isFinite, scale > 0 else { return frame }
        let width = frame.width * scale, height = frame.height * scale
        return clamped(CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), in: bounds)
    }
}

/// The offset as the controls show it: "−7 s", "+2 s", "0 s" (a true minus sign).
enum OffsetText {
    static func text(_ ms: Int64) -> String {
        let seconds = Double(ms) / 1000
        let whole = seconds.rounded() == seconds
        let magnitude = whole ? String(Int64(abs(seconds))) : String(format: "%.1f", abs(seconds))
        if ms == 0 { return "0 s" }
        return (ms < 0 ? "\u{2212}" : "+") + magnitude + " s"
    }
}

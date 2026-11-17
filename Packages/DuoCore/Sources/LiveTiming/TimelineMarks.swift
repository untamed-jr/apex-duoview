import Foundation

/// A mark on a player's timeline, in that player's seconds.
public enum TimelineMark: Equatable, Sendable {
    /// The session's first "Started": "Lights out" for races and sprints, "Session start" otherwise.
    case lightsOut(at: Double, label: String)
    /// Each time the session went to "Finished" (each part of qualifying has one).
    case chequered(at: Double)
    /// A safety car, VSC or red flag period. `to` is infinite only when the whole race is shown
    /// and it is still out at the end of the data.
    case band(FlagSpan.Kind, from: Double, to: Double)

    /// The part inside a scrubber's span (what the player can play); nil when none is.
    public func clipped(to range: ClosedRange<Double>) -> TimelineMark? {
        switch self {
        case .lightsOut(let at, _), .chequered(let at):
            return range.contains(at) ? self : nil
        case .band(let kind, let from, let to):
            let low = max(from, range.lowerBound)
            let high = min(to, range.upperBound)
            guard low < high else { return nil }
            return .band(kind, from: low, to: high)
        }
    }

    /// For VoiceOver: "Lights out", "Chequered flag", "Safety car" ...
    public var label: String {
        switch self {
        case .lightsOut(_, let label): return label
        case .chequered: return "Chequered flag"
        case .band(let kind, _, _):
            switch kind {
            case .safetyCar: return "Safety car"
            case .vsc: return "Virtual safety car"
            case .red: return "Red flag"
            }
        }
    }

    /// A session's marks in player seconds. `playerSeconds` is where the player was when picture
    /// time was `pictureTime` (one reading of its clock, the timing offset already in picture
    /// time), so a moment `u` sits at `playerSeconds + (u − pictureTime) / 1000` (Android's
    /// utc − offset − windowStart). Rounded to a tenth of a second, so the same marks compare
    /// equal from one reading to the next.
    ///
    /// - Lights out and the chequered flag always show: they mark the session's shape (where it
    ///   starts and ends), not what happens in it.
    /// - Safety car, VSC and red flag periods show only up to picture time: one that starts later
    ///   is left out, and one still out at picture time ends there (no spoilers).
    /// - `wholeRace` ("Show the whole race", off by default) shows every period in full; one
    ///   still out at the end of the data runs on (`to` infinite) for the scrubber to clip.
    public static func marks(for session: LoadedSession, pictureTime: UTCms, playerSeconds: Double,
                             wholeRace: Bool) -> [TimelineMark] {
        guard playerSeconds.isFinite else { return [] }
        func seconds(_ u: UTCms) -> Double {
            ((playerSeconds + (Double(u) - Double(pictureTime)) / 1000) * 10).rounded() / 10
        }
        var out: [TimelineMark] = []
        for span in session.flags.spans {
            if wholeRace {
                out.append(.band(span.kind, from: seconds(span.start), to: span.end.map(seconds) ?? .infinity))
                continue
            }
            guard span.start < pictureTime else { continue }
            let end = min(span.end ?? pictureTime, pictureTime)
            out.append(.band(span.kind, from: seconds(span.start), to: seconds(end)))
        }
        if let started = session.sessionStatus.started {
            // The archive types a sprint as a race: both start with lights out.
            out.append(.lightsOut(at: seconds(started), label: session.info.type == "Race" ? "Lights out" : "Session start"))
        }
        var previous: String?
        for change in session.sessionStatus.changes {
            if change.status == "Finished", previous != "Finished", !change.isSnapshot { out.append(.chequered(at: seconds(change.at))) }
            previous = change.status
        }
        return out
    }
}

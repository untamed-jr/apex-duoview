import Foundation
import LiveTiming
import Multiview

// Team radio's plain values and decisions: the lap labels' words, the rows, the empty lines, when
// a playing clip stops and where the Scrub Deck's ticks go. No SwiftUI, no AVFoundation and no
// actor isolation, so the harness checks all of it.
//
// Picture time: everything here takes the *cut*, `showWholeRace ? nil : pictureTime`, where nil
// is the whole race (DuoCore's meaning). With "Show the whole race" off and no picture time yet,
// nothing shows at all: `visible(_:pictureTime:wholeRace:)` gives no clips, `shouldStop` stops,
// and `tickFractions` gives no ticks.

/// A row's transcript, as `TranscriptionQueue` says, read only at the cut.
enum TranscriptLine: Equatable, Sendable {
    case none
    case transcribing
    case text(String)
    case noWords
}

/// One clip in the Radio panel (and Race Engineer's spot).
struct RadioRowModel: Equatable, Sendable, Identifiable {
    /// The clip's path: its identity.
    var path: String
    /// The car's racing number.
    var number: String
    var tla: String
    /// "RRGGBB", or "".
    var teamColour: String
    /// "Lap 23", "Before the start", "Q2 · 8:12 left", "12:24"; nil for an unknown lap.
    var label: String?
    /// The label again when it differs from the row above (the list's lap header); nil otherwise.
    var header: String?
    var transcript: TranscriptLine
    /// Crossed in normal play within the last 3 s: one soft flash.
    var isNew: Bool

    var id: String { path }
}

/// A tick on the Scrub Deck's strip.
struct RadioTick: Equatable, Sendable {
    var path: String
    var utc: UTCms
    /// Across the deck, 0–1.
    var f: Double
    /// Your driver's: drawn taller.
    var mine: Bool
}

enum RadioModels {
    // MARK: Copy

    static let title = "Team radio"
    static let hide = "Hide team radio"
    static let button = "Radio"
    static let firstClip = "Radio shows up here as it happens."
    static let couldNotLoad = "Couldn't load this clip"
    static let couldNotPlay = "Couldn't play that radio clip"
    static let transcribing = "Transcribing\u{2026}"
    static let allChip = "All"
    static let myDriverChip = "My driver"
    static let driverChip = "Driver"

    static func noRadio(from tla: String) -> String { "No radio from \(tla) yet." }

    /// The panel's empty line: "Radio shows up here as it happens." for every clip (on replays and
    /// live alike, so it never hints whether radio is coming); "No radio from {CODE} yet." for one
    /// driver. A driver whose code isn't known gets the first line.
    static func emptyText(filter: RadioFilter, tla: String?) -> String {
        switch filter {
        case .all:
            return firstClip
        case .myDriver, .driver:
            guard let tla, !tla.isEmpty else { return firstClip }
            return noRadio(from: tla)
        }
    }

    /// What a clip fetch came to, as the viewer reads it: nil when there is a file.
    static func loadNotice(_ result: RadioFetchResult) -> String? {
        switch result {
        case .data: return nil
        case .refused, .failed: return couldNotLoad
        }
    }

    // MARK: Lap labels

    /// The Global Constraints' words for a lap label; nil for `.unknown` (no header, nothing on the
    /// row).
    static func label(_ l: RadioLapLabel) -> String? {
        switch l {
        case .lap(let n):
            return "Lap \(n)"
        case .beforeStart:
            return "Before the start"
        case .afterFlag:
            return "After the flag"
        case .qualifying(let part, let remaining):
            guard let part else { return "Qualifying" }
            guard let remaining else { return "Q\(part)" }
            return "Q\(part) \u{00B7} \(clock(remaining)) left"
        case .practice(let elapsed):
            return clock(elapsed)
        case .unknown:
            return nil
        }
    }

    /// "m:ss", or "h:mm:ss" from an hour; whole seconds, rounded down; never negative.
    static func clock(_ ms: Int64) -> String {
        let seconds = max(ms, 0) / 1000
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        func two(_ n: Int64) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }

    // MARK: Which clips

    /// The session's clips to show: those at or before picture time, or every one with the whole
    /// race on; none with the whole race off and no picture time yet.
    static func visible(_ radio: RadioClips, pictureTime: UTCms?, wholeRace: Bool) -> [RadioClip] {
        if wholeRace { return radio.visible(at: nil) }
        guard let pictureTime else { return [] }
        return radio.visible(at: pictureTime)
    }

    /// The cut for `rows`, `transcript(for:at:)` and the like: nil (the whole race) only with the
    /// whole race on.
    static func cut(pictureTime: UTCms?, wholeRace: Bool) -> UTCms? {
        wholeRace ? nil : pictureTime
    }

    /// "My driver" with no driver chosen lists every clip. A remembered driver this session
    /// doesn't have (`drivers`, the session's racing numbers, when known: nil or empty is not
    /// known) lists every clip too.
    static func effective(_ filter: RadioFilter, favourite: String?, drivers: [String]? = nil) -> RadioFilter {
        if case .myDriver = filter, favourite == nil { return .all }
        if case .driver(let number) = filter, let drivers, !drivers.isEmpty, !drivers.contains(number) {
            return .all
        }
        return filter
    }

    /// The clips a filter keeps. `favourite` is your driver's racing number; `drivers` as in
    /// `effective`.
    static func filtered(_ clips: [RadioClip], filter: RadioFilter, favourite: String?,
                         drivers: [String]? = nil) -> [RadioClip] {
        switch effective(filter, favourite: favourite, drivers: drivers) {
        case .all: return clips
        case .myDriver: return clips.filter { $0.racingNumber == favourite }
        case .driver(let number): return clips.filter { $0.racingNumber == number }
        }
    }

    /// The filter's driver, for the empty line: your driver's or the chosen one's racing number.
    static func driver(of filter: RadioFilter, favourite: String?) -> String? {
        switch effective(filter, favourite: favourite) {
        case .all: return nil
        case .myDriver: return favourite
        case .driver(let number): return number
        }
    }

    // MARK: Rows

    /// One row per clip, oldest first, each with its lap label and a header where the label
    /// differs from the row above. `t` is the cut (nil: the whole race): a clip published after it
    /// is left out, and transcripts and the clip being transcribed come only from
    /// `queue.transcript(for:at:)` and `queue.transcribing(visibleAt:in:)`, so nothing later than
    /// picture time reaches a row. `new` holds the paths to flash.
    static func rows(clips: [RadioClip], session: LoadedSession, queue: TranscriptionQueue, at t: UTCms?,
                     new: Set<String> = []) -> [RadioRowModel] {
        let running = queue.transcribing(visibleAt: t, in: session.radio)
        var out: [RadioRowModel] = []
        var above: String?
        for clip in clips where t.map({ clip.utc <= $0 }) ?? true {
            let words = Self.label(RadioClips.lapLabel(for: clip, in: session))
            let header = words != nil && words != above ? words : nil
            above = words
            let transcript: TranscriptLine
            if let text = queue.transcript(for: clip, at: t) {
                transcript = text == TranscriptionQueue.noWords ? .noWords : .text(text)
            } else if running == clip.path {
                transcript = .transcribing
            } else {
                transcript = .none
            }
            let driver = session.drivers[clip.racingNumber]
            out.append(RadioRowModel(
                path: clip.path, number: clip.racingNumber, tla: driver?.tla ?? clip.racingNumber,
                teamColour: driver?.teamColour ?? "", label: words, header: header, transcript: transcript,
                isNew: new.contains(clip.path)))
        }
        return out
    }

    // MARK: Playing

    /// A playing clip stops once picture time is before its `Utc` (a rewind past it), or there is
    /// no picture time. With the whole race on every clip is listed, so none is stopped.
    static func shouldStop(playing: RadioClip, pictureTime: UTCms?, wholeRace: Bool = false) -> Bool {
        if wholeRace { return false }
        guard let pictureTime else { return true }
        return playing.utc > pictureTime
    }

    // MARK: Scrub Deck

    /// The deck's radio ticks: one per clip at or before picture time (every clip with the whole
    /// race on, none without picture time), placed by `fraction` (a moment to 0–1 across the deck;
    /// nil leaves the clip out). Your driver's are `mine`.
    static func tickFractions(clips: RadioClips, pictureTime: UTCms?, wholeRace: Bool, favourite: String?,
                              fraction: (UTCms) -> Double?) -> [RadioTick] {
        visible(clips, pictureTime: pictureTime, wholeRace: wholeRace).compactMap { clip in
            guard let f = fraction(clip.utc), f.isFinite else { return nil }
            return RadioTick(path: clip.path, utc: clip.utc, f: min(max(f, 0), 1),
                             mine: favourite != nil && clip.racingNumber == favourite)
        }
    }

    /// A 44 pt target, as the deck's markers.
    static let tickRadius: Double = 22

    /// The tick nearest `x` within the radius (`width` is the strip's width in points), and how
    /// far it is.
    static func tick(atX x: Double, in ticks: [RadioTick], width: Double) -> (tick: RadioTick, distance: Double)? {
        var best: (tick: RadioTick, distance: Double)?
        for tick in ticks {
            let d = abs(tick.f * width - x)
            if d <= tickRadius, d < (best?.distance ?? .infinity) { best = (tick, d) }
        }
        return best
    }
}

// MARK: - Time jumps

/// Where a player's item was, by the monotonic clock, and how fast it was going (its actual
/// rate: 0 while paused).
struct PlaybackSample: Equatable, Sendable {
    var channelId: Int?
    var seconds: Double
    var uptime: TimeInterval
    var rate: Double
}

/// AVFoundation's `timeJumpedNotification` can also come in normal play (a rate change, a stall's
/// end). It counts as a seek for the radio only when the item's time is more than a second away
/// from where the last sample says it should be (that sample advanced by the wall time × its
/// rate). With no sample (or one for another feed), it counts.
enum TimeJump {
    static let toleranceSeconds = 1.0

    static func isJump(from last: PlaybackSample?, channelId: Int? = nil, to seconds: Double,
                       uptime: TimeInterval) -> Bool {
        guard let last, last.channelId == channelId, seconds.isFinite, last.seconds.isFinite,
              uptime.isFinite, last.uptime.isFinite, last.rate.isFinite else { return true }
        let expected = last.seconds + max(uptime - last.uptime, 0) * last.rate
        return abs(seconds - expected) > toleranceSeconds
    }
}

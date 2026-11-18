import Foundation

/// Which radio clip to turn into text next, and what came of each: the rules of Android's
/// transcription loop (`AppState.transcribeRadio`), as a value the app's transcriber drives.
/// It holds no clips and runs nothing; the app asks `next`, transcribes that clip, and reports
/// back with `finished`, `failed`, `timedOut` or `cancelled`.
///
/// The app's contract:
/// - Transcription runs only while radio is on screen. Closing the panel or leaving the session
///   mid-clip is `cancelled(path:)`: the clip isn't skipped or counted as a failure, and comes
///   back from the next `next` (Android rethrows CancellationException the same way).
/// - The queue never fires a timer. The app's transcriber task enforces the 45 s itself and
///   reports `timedOut(path:)`. While a job runs the app doesn't call `next` except to poll
///   (it returns nil). If `next` ever replaces a running job (its own 45 s skip, once the wall
///   clock is 45 s past the start), the app must cancel the old transcriber task.
/// - `pictureTime` is picture time, or nil in "Show the whole race" (`visible(at: nil)`): then
///   every clip is due, with no 2-minute limit, taken oldest first. Never pass a made-up large
///   time for it.
/// - The UI reads `transcribing(visibleAt:in:)` and `transcript(for:at:)`, never the raw
///   `running` and `results`, which can belong to clips not yet visible.
///
/// - One clip at a time: `next` gives nothing while one is running.
/// - Nearest the picture first: of the clips without a result, not skipped and published no more
///   than 2 minutes after picture time (behind it, any distance), the one whose `Utc` is closest
///   to it; on a tie, the earlier in the list.
/// - A clip not done 45 s after it started is skipped (`next` does it once the 45 s are up, or
///   the app calls `timedOut`). A skip isn't a failure: it doesn't count towards the three.
/// - Three failures in a row wait 2 minutes, then try the failed and skipped clips again.
///   A result ends the run.
/// - Results are kept by clip path, so a clip with one is never queued again (seed `results`
///   with the kept transcripts). Nothing recognised is a result: `noWords`.
///
/// `now` is the wall clock (ms), never picture time: the 45 s and the 2 minutes run while the
/// picture is paused.
public struct TranscriptionQueue: Sendable, Equatable {
    /// How far past picture time clips are transcribed early, so their text is ready.
    public static let aheadMs: Int64 = 120_000
    /// How long one clip may take before it's skipped.
    public static let timeoutMs: Int64 = 45_000
    /// Failures in a row before waiting.
    public static let failuresBeforeWait = 3
    /// How long to wait after them.
    public static let waitMs: Int64 = 120_000
    /// What a clip with nothing recognised stores.
    public static let noWords = "(no words recognised)"

    /// The clip being transcribed and when (wall clock) it started.
    public struct Job: Sendable, Equatable {
        public var path: String
        public var startedAt: Int64
    }

    /// Transcripts by clip path. Internal use: keyed for clips up to 2 minutes ahead of picture
    /// time, so the UI must read `transcript(for:at:)`.
    public private(set) var results: [String: String]
    /// Internal use: can be a clip published after picture time; the UI must read
    /// `transcribing(visibleAt:in:)`.
    public private(set) var running: Job?
    /// Clips that failed or timed out, not tried again until a wait ends.
    public private(set) var skipped: Set<String> = []
    public private(set) var failuresInRow = 0
    /// While waiting after three failures: when the wait ends (wall clock).
    public private(set) var waitingUntil: Int64?

    public init(results: [String: String] = [:]) {
        self.results = results
    }

    /// The path being transcribed, if any. Internal use: it can be a clip not visible yet; the
    /// UI must read `transcribing(visibleAt:in:)`.
    public var transcribing: String? { running?.path }

    /// The path being transcribed ("Transcribing…"), only when that clip is visible at picture
    /// time `t` (`utc ≤ t`; nil is the whole race). Nil when nothing runs or the clip isn't in
    /// `clips`.
    public func transcribing(visibleAt t: UTCms?, in clips: RadioClips) -> String? {
        guard let path = running?.path, let clip = clips.all.first(where: { $0.path == path }) else { return nil }
        return Self.isVisible(clip, at: t) ? path : nil
    }

    /// The transcript for `clip`, only when the clip is visible at picture time `t` (`utc ≤ t`;
    /// nil is the whole race).
    public func transcript(for clip: RadioClip, at t: UTCms?) -> String? {
        Self.isVisible(clip, at: t) ? results[clip.path] : nil
    }

    private static func isVisible(_ clip: RadioClip, at t: UTCms?) -> Bool {
        t.map { clip.utc <= $0 } ?? true
    }

    /// The clip to transcribe now, marked as running from `now`; nil while one runs, while
    /// waiting, or when no clip is due. `pictureTime` is picture time, nil for the whole race
    /// (every clip due, oldest first); `clips` are the session's.
    public mutating func next(from clips: [RadioClip], at pictureTime: UTCms?, now: Int64) -> RadioClip? {
        if let running {
            guard F1Values.sub(now, running.startedAt) >= Self.timeoutMs else { return nil }
            timedOut(path: running.path)
        }
        if let waitingUntil {
            guard now >= waitingUntil else { return nil }
            self.waitingUntil = nil
        }
        let limit = pictureTime.map { F1Values.add($0, Self.aheadMs) }
        var best: RadioClip?
        var bestDistance: Int64 = .max
        for clip in clips where limit.map({ clip.utc <= $0 }) ?? true && results[clip.path] == nil && !skipped.contains(clip.path) {
            // Whole race: no picture to be near, so every distance ties and the earliest in the list wins.
            let distance: Int64
            if let pictureTime {
                distance = clip.utc > pictureTime ? F1Values.sub(clip.utc, pictureTime) : F1Values.sub(pictureTime, clip.utc)
            } else {
                distance = 0
            }
            if best == nil || distance < bestDistance {
                best = clip
                bestDistance = distance
            }
        }
        if let best { running = Job(path: best.path, startedAt: now) }
        return best
    }

    /// The text for `path`; blank (once trimmed) is `noWords`. Kept even when it arrives after
    /// the clip was skipped. Ends a run of failures.
    public mutating func finished(path: String, result: String) {
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        results[path] = text.isEmpty ? Self.noWords : text
        if running?.path == path { running = nil }
        failuresInRow = 0
    }

    /// The running clip failed at `now` (wall clock). It's skipped; the third failure in a row
    /// starts a 2-minute wait, after which the skipped clips are tried again. A report for a clip
    /// that isn't running (it timed out first) changes nothing.
    public mutating func failed(path: String, at now: Int64) {
        guard running?.path == path else { return }
        running = nil
        skipped.insert(path)
        failuresInRow += 1
        if failuresInRow >= Self.failuresBeforeWait {
            failuresInRow = 0
            skipped.removeAll()
            waitingUntil = F1Values.add(now, Self.waitMs)
        }
    }

    /// The running clip took too long: skipped, not counted as a failure.
    public mutating func timedOut(path: String) {
        guard running?.path == path else { return }
        running = nil
        skipped.insert(path)
    }

    /// The running clip was stopped by the app (panel closed, session left): not running any
    /// more, but not skipped and not a failure, so the next `next` hands it out again. Ignored
    /// when `path` isn't the running clip.
    public mutating func cancelled(path: String) {
        guard running?.path == path else { return }
        running = nil
    }
}
